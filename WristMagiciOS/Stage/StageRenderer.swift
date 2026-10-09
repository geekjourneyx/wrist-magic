@preconcurrency import MetalKit
import ARKit
import WristMagicCore

/// Main-actor ownership plus three slots bounds every submitted camera/GPU frame.
@MainActor final class StageRenderer {
  private struct FrameUniforms {
    var viewProjection: simd_float4x4
    var imageUV: simd_float3x3
    var effectCount: UInt32
    var cameraKind: UInt32
  }
  let device: MTLDevice
  private let queue: MTLCommandQueue
  private var cache: CVMetalTextureCache!
  private let composite: MTLRenderPipelineState
  private let present: MTLRenderPipelineState
  private var pool: CVPixelBufferPool!
  private var busy: Set<Int> = []
  weak var preview: MTKView?
  var reducedMotion = false
  private(set) var framesInFlight = 0
  init() throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(), let library = device.makeDefaultLibrary() else { throw MediaError.gpu }
    self.device = device; self.queue = queue
    func pipeline(_ fragment: String) throws -> MTLRenderPipelineState {
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = library.makeFunction(name: "fullScreen")
      descriptor.fragmentFunction = library.makeFunction(name: fragment)
      descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
      return try device.makeRenderPipelineState(descriptor: descriptor)
    }
    composite = try pipeline("composite"); present = try pipeline("present")
    guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess else { throw MediaError.gpu }
    guard CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey:3] as CFDictionary,
      [kCVPixelBufferWidthKey:720,kCVPixelBufferHeightKey:1280,kCVPixelBufferPixelFormatTypeKey:kCVPixelFormatType_32BGRA,kCVPixelBufferMetalCompatibilityKey:true,kCVPixelBufferIOSurfacePropertiesKey:[:]] as CFDictionary, &pool) == kCVReturnSuccess else { throw MediaError.pixelBuffer }
    precondition(MemoryLayout<EffectParameters>.stride == 64 && MemoryLayout<EffectParameters>.alignment == 16)
  }
  func attach(preview: MTKView) {
    self.preview = preview; preview.device = device; preview.colorPixelFormat = .bgra8Unorm
    preview.framebufferOnly = false; preview.isPaused = true; preview.enableSetNeedsDisplay = false
    preview.autoResizeDrawable = false; preview.drawableSize = CameraTransform.outputSize
  }
  private func texture(_ buffer: CVPixelBuffer, format: MTLPixelFormat, plane: Int = 0) throws -> (CVMetalTexture, MTLTexture) {
    let planar = CVPixelBufferIsPlanar(buffer)
    let width = planar ? CVPixelBufferGetWidthOfPlane(buffer,plane) : CVPixelBufferGetWidth(buffer)
    let height = planar ? CVPixelBufferGetHeightOfPlane(buffer,plane) : CVPixelBufferGetHeight(buffer)
    var wrapped: CVMetalTexture?
    guard CVMetalTextureCacheCreateTextureFromImage(nil,cache,buffer,nil,format,width,height,plane,&wrapped) == kCVReturnSuccess, let wrapped, let texture = CVMetalTextureGetTexture(wrapped) else { throw MediaError.gpu }
    return (wrapped,texture)
  }
  /// Completion occurs only after both offscreen and preview GPU work finish. A false return drops
  /// the frame without allocating, buffering, or changing its timestamp.
  @discardableResult func submit(frame: ARFrame, effects: [EffectCue], completion: @escaping @MainActor (Result<CVPixelBuffer, Error>) -> Void) throws -> Bool {
    try submit(image: frame.capturedImage, displayTransform: frame.displayTransform(for: .portrait, viewportSize: CameraTransform.outputSize), viewProjection: CameraTransform.viewProjection(frame.camera), time: frame.timestamp, effects: effects, completion: completion)
  }
  @discardableResult func submit(image: CVPixelBuffer, displayTransform: CGAffineTransform, viewProjection: simd_float4x4, time: Double, effects: [EffectCue], completion: @escaping @MainActor (Result<CVPixelBuffer, Error>) -> Void) throws -> Bool {
    guard let slot = (0..<3).first(where: { !busy.contains($0) }) else { return false }
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil,pool,[kCVPixelBufferPoolAllocationThresholdKey:3] as CFDictionary,&buffer)
    if status == kCVReturnWouldExceedAllocationThreshold { return false }
    guard status == kCVReturnSuccess, let buffer else { throw MediaError.pixelBuffer }
    busy.insert(slot); framesInFlight = busy.count
    do {
      try encode(image: image, displayTransform: displayTransform, viewProjection: viewProjection, time: time, effects: effects, target: buffer) { [self] result in
        self.busy.remove(slot); self.framesInFlight = self.busy.count
        completion(result)
      }
      return true
    } catch { busy.remove(slot); framesInFlight = busy.count; throw error }
  }
  /// Standalone fixture/offscreen entrypoint. Await GPU completion before consuming target.
  func render(frame: ARFrame, effects: [EffectCue], target: CVPixelBuffer) async throws {
    guard let slot = (0..<3).first(where: { !busy.contains($0) }) else { throw MediaError.gpu }
    busy.insert(slot); framesInFlight = busy.count
    try await withCheckedThrowingContinuation { continuation in
      do { try encode(image: frame.capturedImage, displayTransform: frame.displayTransform(for: .portrait, viewportSize: CameraTransform.outputSize), viewProjection: CameraTransform.viewProjection(frame.camera), time: frame.timestamp, effects: effects, target: target) { [self] result in
        self.busy.remove(slot); self.framesInFlight = self.busy.count
        continuation.resume(with: result.map { _ in () })
      } }
      catch { busy.remove(slot); framesInFlight = busy.count; continuation.resume(throwing: error) }
    }
  }
  private func encode(image: CVPixelBuffer, displayTransform: CGAffineTransform, viewProjection: simd_float4x4, time: Double, effects: [EffectCue], target: CVPixelBuffer, completion: @escaping @MainActor (Result<CVPixelBuffer, Error>) -> Void) throws {
    guard CVPixelBufferGetWidth(target) == 720, CVPixelBufferGetHeight(target) == 1280,
      CVPixelBufferGetPixelFormatType(target) == kCVPixelFormatType_32BGRA else { throw MediaError.pixelBuffer }
    let planar = CVPixelBufferIsPlanar(image)
    let camera = try texture(image,format: planar ? .r8Unorm : .bgra8Unorm)
    let chroma = planar ? try texture(image,format:.rg8Unorm,plane:1) : camera
    let output = try texture(target,format:.bgra8Unorm)
    guard let command = queue.makeCommandBuffer() else { throw MediaError.gpu }
    let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = output.1
    pass.colorAttachments[0].loadAction = .dontCare; pass.colorAttachments[0].storeAction = .store
    guard let encoder = command.makeRenderCommandEncoder(descriptor:pass) else { throw MediaError.gpu }
    var parameters = effects.suffix(16).map { EffectTimeline.evaluate($0, at: time, reducedMotion: reducedMotion) }.filter(\.isActive)
    let count = parameters.count
    if parameters.isEmpty { parameters = [.inactive] }
    var uniforms = FrameUniforms(viewProjection:viewProjection,imageUV:CameraTransform.inverseDisplay(displayTransform),effectCount:UInt32(count),cameraKind:planar ? 0 : 1)
    encoder.setRenderPipelineState(composite)
    encoder.setFragmentTexture(camera.1,index:0); encoder.setFragmentTexture(chroma.1,index:1)
    encoder.setFragmentBytes(&uniforms,length:MemoryLayout<FrameUniforms>.stride,index:0)
    parameters.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!,length:$0.count,index:1) }
    encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3); encoder.endEncoding()
    if let preview, let drawable = preview.currentDrawable {
      let display = MTLRenderPassDescriptor(); display.colorAttachments[0].texture = drawable.texture
      display.colorAttachments[0].loadAction = .dontCare; display.colorAttachments[0].storeAction = .store
      if let encoder = command.makeRenderCommandEncoder(descriptor:display) {
        encoder.setRenderPipelineState(present); encoder.setFragmentTexture(output.1,index:0)
        encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3); encoder.endEncoding(); command.present(drawable)
      }
    }
    command.addCompletedHandler { completed in
      // Keep CoreVideo texture wrappers and the camera image alive until GPU completion.
      _ = (camera.0,chroma.0,output.0,image)
      let success = completed.status == .completed
      Task { @MainActor in completion(success ? .success(target) : .failure(MediaError.gpu)) }
    }
    command.commit()
  }
}

import XCTest
@preconcurrency import AVFoundation
@preconcurrency import MetalKit
import UIKit
import WristMagicCore
@testable import WristMagiciOS

private struct PixelSnapshot: Sendable {
  let bytes: Data
  let rowBytes: Int
}
final class SharedRenderExportTests: XCTestCase {
  @MainActor private static func camera() throws -> CVPixelBuffer {
    var buffer:CVPixelBuffer?
    guard CVPixelBufferCreate(nil,720,1280,kCVPixelFormatType_32BGRA,[kCVPixelBufferMetalCompatibilityKey:true] as CFDictionary,&buffer) == kCVReturnSuccess, let buffer else {throw MediaError.pixelBuffer}
    CVPixelBufferLockBaseAddress(buffer,[])
    memset(CVPixelBufferGetBaseAddress(buffer),80,CVPixelBufferGetDataSize(buffer))
    CVPixelBufferUnlockBaseAddress(buffer,[])
    return buffer
  }
  @MainActor private static func pixels(_ buffer:CVPixelBuffer) -> PixelSnapshot {
    CVPixelBufferLockBaseAddress(buffer,.readOnly); defer {CVPixelBufferUnlockBaseAddress(buffer,.readOnly)}
    return PixelSnapshot(bytes:Data(bytes:CVPixelBufferGetBaseAddress(buffer)!,count:CVPixelBufferGetDataSize(buffer)),rowBytes:CVPixelBufferGetBytesPerRow(buffer))
  }
  @MainActor private static func readback(_ texture:MTLTexture,device:MTLDevice) async throws -> PixelSnapshot {
    let rowBytes = 3072
    guard let buffer = device.makeBuffer(length:rowBytes*1280,options:.storageModeShared), let queue = device.makeCommandQueue(), let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {throw MediaError.gpu}
    blit.copy(from:texture,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:720,height:1280,depth:1),to:buffer,destinationOffset:0,destinationBytesPerRow:rowBytes,destinationBytesPerImage:rowBytes*1280)
    blit.endEncoding()
    let _:Void = try await MediaTestSupport.callback { complete in
      command.addCompletedHandler { @Sendable completed in
        let success = completed.status == .completed
        Task { @MainActor in complete(success ? .success(()) : .failure(MediaError.gpu)) }
      }
      command.commit()
    }
    guard command.status == .completed else {throw MediaError.gpu}
    return PixelSnapshot(bytes:Data(bytes:buffer.contents(),count:rowBytes*1280),rowBytes:rowBytes)
  }
  private static func regionError(_ a:PixelSnapshot,_ b:PixelSnapshot,effectRegion:Bool) -> Double {
    var error = 0.0; var count = 0
    let xs = effectRegion ? Array(stride(from:320,to:560,by:7)) : [20,40,680,700]
    let ys = effectRegion ? Array(stride(from:200,to:800,by:7)) : [20,40,1240,1260]
    for y in ys { for x in xs { for channel in 0..<3 {
      error += abs(Double(a.bytes[y*a.rowBytes+x*4+channel])-Double(b.bytes[y*b.rowBytes+x*4+channel])); count += 1
    } } }
    return error/Double(count)
  }
  @MainActor func testActualMTKPreviewAndH264ExportMatchAtTimelineReferenceFrames() async throws {
    guard MTLCreateSystemDefaultDevice() != nil else {throw XCTSkip("Simulator does not provide Metal")}
    let renderer = try StageRenderer()
    let window = UIWindow(frame:CGRect(x:0,y:0,width:720,height:1280))
    let controller = UIViewController(); window.rootViewController = controller
    let preview = MTKView(frame:window.bounds,device:renderer.device)
    controller.view.addSubview(preview); renderer.attach(preview:preview)
    // This belongs to UIKit only and must never enter either Metal surface or encoded video.
    let overlay = UILabel(frame:CGRect(x:220,y:500,width:350,height:100))
    overlay.text = "UI MUST STAY OUT"; overlay.textColor = .yellow; overlay.backgroundColor = .black
    controller.view.addSubview(overlay); window.makeKeyAndVisible()
    defer {window.isHidden = true}
    controller.view.layoutIfNeeded(); preview.layoutIfNeeded()
    await Task.yield()
    let camera = try Self.camera()
    let references:Set<Int> = [0,9,24,45] // 0 / .3 / .8 / 1.5 seconds at30fps
    for spell in SpellID.allCases {
      let url = ClipWriter.temporaryURL()
      let writer = try ClipWriter(url:url); try writer.start(at:.zero)
      var expected:[Int:PixelSnapshot] = [:]
      let cue = EffectCue(eventID:UUID(),spell:spell,start:0,seed:27,origin:.zero,direction:SIMD3(0.4,0,0))
      for index in 0..<60 {
        try await MediaTestSupport.waitUntilReady(writer)
        // MTKView caches currentDrawable for this frame. Retain the actual presented texture.
        guard let drawable = preview.currentDrawable else {throw MediaError.gpu}
        // Completed CAMetalDrawable wrappers may be recycled. Fresh-frame correctness
        // is proved below by reading the actual presented texture at changing cue times.
        let pixels:PixelSnapshot = try await MediaTestSupport.callback { complete in
          do {
            let accepted = try renderer.submit(image:camera,displayTransform:.identity,viewProjection:matrix_identity_float4x4,time:Double(index)/30,effects:[cue]) { result in
              do {
                let buffer = try result.get()
                guard try writer.append(buffer:buffer,pts:CMTime(value:Int64(index),timescale:30)) else {throw MediaError.writerFailed}
                complete(.success(Self.pixels(buffer)))
              } catch {complete(.failure(error))}
            }
            if !accepted {complete(.failure(MediaError.gpu))}
          } catch {complete(.failure(error))}
        }
        if references.contains(index) {
          expected[index] = pixels
          let presented = try await Self.readback(drawable.texture,device:renderer.device)
          XCTAssertLessThanOrEqual(Self.regionError(pixels,presented,effectRegion:true),2,"\(spell) preview at\(index)")
          XCTAssertLessThanOrEqual(Self.regionError(pixels,presented,effectRegion:false),2)
        }
      }
      let finished = try await MediaTestSupport.deadline { try await writer.finish() }; defer {try? FileManager.default.removeItem(at:finished)}
      _ = try await ClipValidator.validate(url:finished,expectedDuration:2,requiresAudio:false)
      let asset = AVURLAsset(url:finished)
      guard let track = try await asset.loadTracks(withMediaType:.video).first else {throw MediaError.invalidClip}
      let reader = try AVAssetReader(asset:asset)
      let output = AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
      reader.add(output); XCTAssertTrue(reader.startReading())
      var compared:Set<Int> = []
      while let sample = output.copyNextSampleBuffer() {
        let index = Int((CMSampleBufferGetPresentationTimeStamp(sample).seconds*30).rounded())
        if let reference = expected[index], let buffer = CMSampleBufferGetImageBuffer(sample) {
          let decoded = Self.pixels(buffer)
          XCTAssertLessThanOrEqual(Self.regionError(reference,decoded,effectRegion:true),20,"\(spell) H264 at\(index)")
          XCTAssertLessThanOrEqual(Self.regionError(reference,decoded,effectRegion:false),10)
          compared.insert(index)
        }
      }
      XCTAssertEqual(reader.status,.completed); XCTAssertEqual(compared,references)
      XCTAssertGreaterThan(Self.regionError(expected[9]!,expected[45]!,effectRegion:true),0.1,"Spell must appear before its1.5s ending")
    }
  }
  @MainActor func testRetainedCompletedBufferCannotBeReusedByLaterGPUFrames() async throws {
    guard MTLCreateSystemDefaultDevice() != nil else {throw XCTSkip("Simulator does not provide Metal")}
    let renderer = try StageRenderer(); let camera = try Self.camera()
    var retained:[CVPixelBuffer] = []
    func render(_ spell:SpellID) async throws -> PixelSnapshot {
      try await MediaTestSupport.callback { complete in
        do {
          let cue = EffectCue(eventID:UUID(),spell:spell,start:0,seed:8,origin:.zero,direction:SIMD3(0.4,0,0))
          let accepted = try renderer.submit(image:camera,displayTransform:.identity,viewProjection:matrix_identity_float4x4,time:0.3,effects:[cue]) { result in
            switch result {
            case .failure(let error):complete(.failure(error))
            case .success(let buffer): retained.append(buffer); complete(.success(Self.pixels(buffer)))
            }
          }
          if !accepted {complete(.failure(MediaError.gpu))}
        } catch {complete(.failure(error))}
      }
    }
    let original = try await render(.fireball)
    _ = try await render(.lightning); _ = try await render(.forcePush)
    XCTAssertEqual(renderer.framesInFlight,0)
    XCTAssertEqual(Self.pixels(retained[0]).bytes,original.bytes)
    XCTAssertFalse(try renderer.submit(image:camera,displayTransform:.identity,viewProjection:matrix_identity_float4x4,time:1,effects:[],completion:{_ in XCTFail("Retained pool unexpectedly submitted")}))
    retained.removeLast()
    _ = try await render(.lightning)
    XCTAssertEqual(Self.pixels(retained[0]).bytes,original.bytes)
    retained.removeAll()
  }
}

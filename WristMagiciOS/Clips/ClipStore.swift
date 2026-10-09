import Foundation
import CryptoKit

struct ClipRecord: Codable, Sendable, Identifiable {
  let id: UUID
  let url: URL
  let createdAt: Date
  let duration: Double
  let interrupted: Bool
  var reviewed: Bool
}
/// Persist only ID-derived filenames; Application Support container paths can change.
private struct StoredClip: Codable {
  let id: UUID
  let filename: String
  let createdAt: Date
  let duration: Double
  let interrupted: Bool
  let reviewed: Bool
  init(_ record: ClipRecord) {
    id = record.id; filename = "\(record.id).mp4"; createdAt = record.createdAt
    duration = record.duration; interrupted = record.interrupted; reviewed = record.reviewed
  }
  func record(in directory: URL) throws -> ClipRecord {
    guard filename == "\(id).mp4" else { throw MediaError.storage }
    return ClipRecord(id:id,url:directory.appendingPathComponent(filename),createdAt:createdAt,duration:duration,interrupted:interrupted,reviewed:reviewed)
  }
}

/// Real file IO; index is replaced atomically only after moving a validated clip into place.
@MainActor final class ClipStore {
  let directory: URL
  private var records: [ClipRecord] = []
  private var leases: [UUID: Int] = [:]
  private let manager: FileManager
  init(directory: URL? = nil, manager: FileManager = .default) throws {
    self.manager = manager
    self.directory = try directory ?? manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Clips",isDirectory:true)
    try manager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    var excluded = self.directory
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    try excluded.setResourceValues(values)
    let index = self.directory.appendingPathComponent("index.json")
    if manager.fileExists(atPath:index.path) {
      let data = try Data(contentsOf:index)
      if let relative = try? JSONDecoder().decode([StoredClip].self,from:data) {
        records = try relative.map { try $0.record(in:self.directory) }
      } else {
        // Migrate the old absolute URL schema before orphan cleanup. A container relocation
        // does not change the clip ID/filename; never follow paths out of this directory.
        let legacy = try JSONDecoder().decode([ClipRecord].self,from:data)
        records = try legacy.map { try StoredClip($0).record(in:self.directory) }
      }
    }
    records = records.filter { manager.fileExists(atPath:$0.url.path) }
    let indexed = Set(records.map { $0.url.lastPathComponent })
    for file in try manager.contentsOfDirectory(at:self.directory,includingPropertiesForKeys:nil) where file.pathExtension == "partial" || (file.pathExtension == "mp4" && !indexed.contains(file.lastPathComponent)) {
      try manager.removeItem(at:file)
    }
    try persist(records)
  }
  private func persist(_ records: [ClipRecord]) throws {
    try JSONEncoder().encode(records.map(StoredClip.init)).write(to:directory.appendingPathComponent("index.json"),options:.atomic)
  }
  func commit(tempURL: URL, report: ClipReport, interrupted: Bool = false) throws -> ClipRecord {
    guard report.valid, let digest = report.validatedSHA256, manager.fileExists(atPath:tempURL.path),
      SHA256.hash(data:try Data(contentsOf:tempURL)).description == digest else { throw MediaError.invalidClip }
    let size = try tempURL.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
    guard size > 0 else { throw MediaError.invalidClip }
    let available = try directory.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    if let available, available < Int64(size) + 1_048_576 { throw MediaError.storage }
    let id = UUID(); let target = directory.appendingPathComponent("\(id).mp4")
    let partial = directory.appendingPathComponent("\(id).partial")
    // Copy into same filesystem before the final atomic rename; source survives all failures.
    do {
      try manager.copyItem(at:tempURL,to:partial)
      try manager.moveItem(at:partial,to:target)
      let record = ClipRecord(id:id,url:target,createdAt:Date(),duration:report.duration,interrupted:interrupted,reviewed:false)
      let updated = records + [record]
      try persist(updated); records = updated
      try? manager.removeItem(at:tempURL)
      return record
    } catch {
      try? manager.removeItem(at:partial); try? manager.removeItem(at:target); throw error
    }
  }
  func latestRecoverable() -> ClipRecord? { records.filter { !$0.reviewed }.max { $0.createdAt < $1.createdAt } }
  func acquire(_ id: UUID) throws {
    guard records.contains(where: { $0.id == id }), manager.fileExists(atPath:records.first(where:{$0.id == id})!.url.path) else { throw MediaError.storage }
    leases[id,default:0] += 1
  }
  func release(_ id: UUID) { let count = leases[id,default:0]; if count <= 1 { leases[id] = nil } else { leases[id] = count - 1 } }
  func markReviewed(_ id: UUID) throws {
    var updated = records
    guard let index = updated.firstIndex(where:{$0.id == id}) else { return }
    updated[index].reviewed = true; try persist(updated); records = updated
  }
  func remove(_ id: UUID) throws {
    guard leases[id] == nil, let record = records.first(where:{$0.id == id}) else { throw MediaError.storage }
    let updated = records.filter {$0.id != id}; try persist(updated); records = updated
    try manager.removeItem(at:record.url)
  }
  func prune(now: Date = Date()) throws {
    let ordered = records.sorted { $0.createdAt > $1.createdAt }
    let retained = Set(ordered.prefix(10).map(\.id))
    let deleted = records.filter { leases[$0.id] == nil && (!retained.contains($0.id) || now.timeIntervalSince($0.createdAt) > 7 * 86400) }
    let ids = Set(deleted.map(\.id)); let updated = records.filter { !ids.contains($0.id) }
    // Persist first: if deletion fails, the orphan is safely cleaned at next launch.
    try persist(updated); records = updated
    for record in deleted { try manager.removeItem(at:record.url) }
  }
}

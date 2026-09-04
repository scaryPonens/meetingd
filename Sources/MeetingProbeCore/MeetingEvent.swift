import Foundation

public enum MeetingEventKind: String, Codable, Equatable, Sendable {
  case meetingStarted = "meeting_started"
  case meetingEnded = "meeting_ended"
}

public struct MeetingEvent: Codable, Equatable, Sendable {
  public let event: MeetingEventKind
  public let platform: MeetingPlatform
  public let timestamp: String
  public let meetingID: String
  public let title: String?
  public let confidence: Double?

  public init(
    event: MeetingEventKind,
    platform: MeetingPlatform,
    timestamp: String,
    meetingID: String,
    title: String? = nil,
    confidence: Double? = nil
  ) {
    self.event = event
    self.platform = platform
    self.timestamp = timestamp
    self.meetingID = meetingID
    self.title = title
    self.confidence = confidence
  }

  enum CodingKeys: String, CodingKey {
    case event
    case platform
    case timestamp
    case meetingID = "meeting_id"
    case title
    case confidence
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(event, forKey: .event)
    try container.encode(platform, forKey: .platform)
    try container.encode(timestamp, forKey: .timestamp)
    try container.encode(meetingID, forKey: .meetingID)
    try container.encodeIfPresent(title, forKey: .title)
    try container.encodeIfPresent(confidence, forKey: .confidence)
  }
}

public protocol EventEmitter: Sendable {
  func emit(_ event: MeetingEvent) throws
}

public struct StdoutNDJSONEventEmitter: EventEmitter {
  public init() {}

  public func emit(_ event: MeetingEvent) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(event)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }
}

public final class CollectingEventEmitter: EventEmitter, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [MeetingEvent] = []

  public init() {}

  public func emit(_ event: MeetingEvent) throws {
    lock.lock()
    storage.append(event)
    lock.unlock()
  }

  public func events() -> [MeetingEvent] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

import Foundation

public struct PlatformRuntimeStatus: Codable, Equatable, Sendable {
  public var platform: MeetingPlatform
  public var state: MeetingLifecycleState
  public var confidence: Double
  public var meetingID: String?
  public var startedAt: String?
  public var signals: DetectionSignals
  public var axStatus: AccessibilityScanStatus

  public init(
    platform: MeetingPlatform,
    state: MeetingLifecycleState = .idle,
    confidence: Double = 0,
    meetingID: String? = nil,
    startedAt: String? = nil,
    signals: DetectionSignals = DetectionSignals(),
    axStatus: AccessibilityScanStatus = .appNotRunning
  ) {
    self.platform = platform
    self.state = state
    self.confidence = confidence
    self.meetingID = meetingID
    self.startedAt = startedAt
    self.signals = signals
    self.axStatus = axStatus
  }

  enum CodingKeys: String, CodingKey {
    case platform
    case state
    case confidence
    case meetingID = "meeting_id"
    case startedAt = "started_at"
    case signals
    case axStatus = "ax_status"
  }
}

public struct DaemonStatusSnapshot: Codable, Equatable, Sendable {
  public var timestamp: String
  public var accessibilityTrusted: Bool
  public var platforms: [PlatformRuntimeStatus]

  public init(
    timestamp: String,
    accessibilityTrusted: Bool,
    platforms: [PlatformRuntimeStatus]
  ) {
    self.timestamp = timestamp
    self.accessibilityTrusted = accessibilityTrusted
    self.platforms = platforms
  }
}

public enum StatusStore {
  public static var defaultDirectoryURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/meetingd", isDirectory: true)
  }

  public static var defaultStatusURL: URL {
    defaultDirectoryURL.appendingPathComponent("status.json", isDirectory: false)
  }

  public static func write(_ snapshot: DaemonStatusSnapshot, to url: URL = defaultStatusURL)
    throws
  {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(snapshot).write(to: url, options: .atomic)
  }

  public static func read(from url: URL = defaultStatusURL) throws -> DaemonStatusSnapshot {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(DaemonStatusSnapshot.self, from: data)
  }
}

public enum StatusFormatter {
  public static func humanReadable(_ snapshot: DaemonStatusSnapshot) -> String {
    var lines = [
      "Updated: \(snapshot.timestamp)",
      "Accessibility: \(snapshot.accessibilityTrusted)",
    ]

    for platform in snapshot.platforms {
      lines.append("")
      lines.append("Platform: \(displayName(platform.platform))")
      lines.append("State: \(platform.state.rawValue)")
      if let meetingID = platform.meetingID {
        lines.append("Meeting ID: \(meetingID)")
      }
      if let startedAt = platform.startedAt {
        lines.append("Started: \(startedAt)")
      }
      lines.append(String(format: "Confidence: %.2f", platform.confidence))
      lines.append("AX status: \(platform.axStatus.rawValue)")
    }
    return lines.joined(separator: "\n")
  }

  public static func debugReadable(
    snapshot: ProbeSnapshot,
    readings: [DetectionReading],
    statuses: [PlatformRuntimeStatus]
  ) -> String {
    var lines = [ProbeFormatter.humanReadable(snapshot), "", "Confidence"]
    for reading in readings {
      let status = statuses.first { $0.platform == reading.platform }
      lines.append(
        "\(reading.platform.rawValue) participating=\(reading.participating) confidence=\(String(format: "%.2f", reading.confidence)) state=\(status?.state.rawValue ?? "IDLE")"
      )
      let signalText = reading.signals.dictionary
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: " ")
      lines.append("  signals \(signalText)")
    }
    return lines.joined(separator: "\n")
  }

  private static func displayName(_ platform: MeetingPlatform) -> String {
    switch platform {
    case .googleMeet: "Google Meet"
    case .slackHuddle: "Slack Huddle"
    }
  }
}

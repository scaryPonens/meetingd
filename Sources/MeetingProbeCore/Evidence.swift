import Foundation

public enum MeetingPlatform: String, Codable, CaseIterable, Sendable {
  case googleMeet = "google_meet"
  case slackHuddle = "slack_huddle"
}

public struct ApplicationSignal: Codable, Equatable, Sendable {
  public let name: String
  public let bundleID: String
  public let pid: Int32
  public let platform: MeetingPlatform

  public init(name: String, bundleID: String, pid: Int32, platform: MeetingPlatform) {
    self.name = name
    self.bundleID = bundleID
    self.pid = pid
    self.platform = platform
  }
}

public struct AudioProcessSignal: Codable, Equatable, Sendable {
  public let bundleID: String
  public let pid: Int32
  public let inputActive: Bool
  public let outputActive: Bool
  public let platform: MeetingPlatform

  public init(
    bundleID: String,
    pid: Int32,
    inputActive: Bool,
    outputActive: Bool,
    platform: MeetingPlatform
  ) {
    self.bundleID = bundleID
    self.pid = pid
    self.inputActive = inputActive
    self.outputActive = outputActive
    self.platform = platform
  }
}

public struct PowerAssertionSignal: Codable, Equatable, Sendable {
  public let pid: Int32
  public let processName: String
  public let bundleID: String?
  public let assertionName: String
  public let assertionType: String
  public let platform: MeetingPlatform

  public init(
    pid: Int32,
    processName: String,
    bundleID: String?,
    assertionName: String,
    assertionType: String,
    platform: MeetingPlatform
  ) {
    self.pid = pid
    self.processName = processName
    self.bundleID = bundleID
    self.assertionName = assertionName
    self.assertionType = assertionType
    self.platform = platform
  }

  public var indicatesWebRTC: Bool {
    let text = assertionName.lowercased()
    return text.contains("webrtc") || text.contains("peerconnection")
  }
}

public enum CollectorStatus: String, Codable, Equatable, Sendable {
  case ok
  case unsupported
  case failed
}

public struct SignalCollection<Signal: Codable & Equatable & Sendable>:
  Codable, Equatable, Sendable
{
  public let status: CollectorStatus
  public let values: [Signal]

  public init(status: CollectorStatus, values: [Signal]) {
    self.status = status
    self.values = values
  }
}

public enum AccessibilityScanStatus: String, Codable, Equatable, Sendable {
  case ok
  case appNotRunning = "app_not_running"
  case permissionDenied = "permission_denied"
  case failed
}

public struct AccessibilityEvidence: Codable, Equatable, Sendable {
  public let platform: MeetingPlatform
  public var status: AccessibilityScanStatus
  public var scannedNodeCount: Int
  public var truncated: Bool

  public var meetTabCount: Int
  public var meetWebAreaCount: Int
  public var meetCallControls: Bool
  public var meetLeaveCallControl: Bool
  public var meetPresentationControl: Bool

  public var slackHuddleWindow: Bool
  public var slackHuddleToolbar: Bool
  public var slackLeaveHuddleControl: Bool

  public init(platform: MeetingPlatform, status: AccessibilityScanStatus = .ok) {
    self.platform = platform
    self.status = status
    scannedNodeCount = 0
    truncated = false
    meetTabCount = 0
    meetWebAreaCount = 0
    meetCallControls = false
    meetLeaveCallControl = false
    meetPresentationControl = false
    slackHuddleWindow = false
    slackHuddleToolbar = false
    slackLeaveHuddleControl = false
  }

  public var joinedCallControlsPresent: Bool {
    switch platform {
    case .googleMeet:
      meetWebAreaCount > 0
        && meetCallControls
        && meetLeaveCallControl
        && meetPresentationControl
    case .slackHuddle:
      slackHuddleToolbar && slackLeaveHuddleControl
    }
  }

  public mutating func merge(_ other: AccessibilityEvidence) {
    guard platform == other.platform else { return }
    status = mergedStatus(status, other.status)
    scannedNodeCount += other.scannedNodeCount
    truncated = truncated || other.truncated
    meetTabCount += other.meetTabCount
    meetWebAreaCount += other.meetWebAreaCount
    meetCallControls = meetCallControls || other.meetCallControls
    meetLeaveCallControl = meetLeaveCallControl || other.meetLeaveCallControl
    meetPresentationControl = meetPresentationControl || other.meetPresentationControl
    slackHuddleWindow = slackHuddleWindow || other.slackHuddleWindow
    slackHuddleToolbar = slackHuddleToolbar || other.slackHuddleToolbar
    slackLeaveHuddleControl = slackLeaveHuddleControl || other.slackLeaveHuddleControl
  }

  private func mergedStatus(
    _ lhs: AccessibilityScanStatus,
    _ rhs: AccessibilityScanStatus
  ) -> AccessibilityScanStatus {
    if lhs == .ok || rhs == .ok { return .ok }
    if lhs == .failed || rhs == .failed { return .failed }
    if lhs == .permissionDenied || rhs == .permissionDenied { return .permissionDenied }
    return .appNotRunning
  }
}

public struct AccessibilityNodeSignal: Equatable, Sendable {
  public let role: String?
  public let subrole: String?
  public let title: String?
  public let description: String?

  public init(role: String?, subrole: String?, title: String?, description: String?) {
    self.role = role
    self.subrole = subrole
    self.title = title
    self.description = description
  }
}

public struct PlatformEvidence: Codable, Equatable, Sendable {
  public let platform: MeetingPlatform
  public let runningApplications: [String]
  public let audioInputActive: Bool
  public let audioOutputActive: Bool
  public let webRTCPeerConnection: Bool
  public let accessibility: AccessibilityEvidence

  public init(
    platform: MeetingPlatform,
    runningApplications: [String],
    audioInputActive: Bool,
    audioOutputActive: Bool,
    webRTCPeerConnection: Bool,
    accessibility: AccessibilityEvidence
  ) {
    self.platform = platform
    self.runningApplications = runningApplications
    self.audioInputActive = audioInputActive
    self.audioOutputActive = audioOutputActive
    self.webRTCPeerConnection = webRTCPeerConnection
    self.accessibility = accessibility
  }
}

public struct ProbeSnapshot: Codable, Equatable, Sendable {
  public let timestamp: String
  public let accessibilityTrusted: Bool
  public let audioCollectorStatus: CollectorStatus
  public let powerAssertionCollectorStatus: CollectorStatus
  public let applications: [ApplicationSignal]
  public let audioProcesses: [AudioProcessSignal]
  public let powerAssertions: [PowerAssertionSignal]
  public let platforms: [PlatformEvidence]

  public init(
    timestamp: String,
    accessibilityTrusted: Bool,
    applications: [ApplicationSignal],
    audioCollectorStatus: CollectorStatus,
    audioProcesses: [AudioProcessSignal],
    powerAssertionCollectorStatus: CollectorStatus,
    powerAssertions: [PowerAssertionSignal],
    accessibilityEvidence: [MeetingPlatform: AccessibilityEvidence]
  ) {
    self.timestamp = timestamp
    self.accessibilityTrusted = accessibilityTrusted
    self.applications = applications
    self.audioCollectorStatus = audioCollectorStatus
    self.audioProcesses = audioProcesses
    self.powerAssertions = powerAssertions
    self.powerAssertionCollectorStatus = powerAssertionCollectorStatus
    platforms = MeetingPlatform.allCases.map { platform in
      let platformApps =
        applications
        .filter { $0.platform == platform }
        .map(\.name)
        .sorted()
      let platformAudio = audioProcesses.filter { $0.platform == platform }
      let platformAssertions = powerAssertions.filter { $0.platform == platform }
      return PlatformEvidence(
        platform: platform,
        runningApplications: platformApps,
        audioInputActive: platformAudio.contains(where: \.inputActive),
        audioOutputActive: platformAudio.contains(where: \.outputActive),
        webRTCPeerConnection: platformAssertions.contains(where: \.indicatesWebRTC),
        accessibility: accessibilityEvidence[platform]
          ?? AccessibilityEvidence(platform: platform, status: .appNotRunning)
      )
    }
  }
}

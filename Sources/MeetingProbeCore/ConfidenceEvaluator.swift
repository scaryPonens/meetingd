import Foundation

public struct DetectionSignals: Codable, Equatable, Sendable {
  public var appRunning: Bool
  public var axJoinedControls: Bool
  public var axAuthoritative: Bool
  public var webRTCPeerConnection: Bool
  public var audioInputActive: Bool
  public var audioOutputActive: Bool
  public var meetContext: Bool
  public var huddleWindow: Bool

  public init(
    appRunning: Bool = false,
    axJoinedControls: Bool = false,
    axAuthoritative: Bool = false,
    webRTCPeerConnection: Bool = false,
    audioInputActive: Bool = false,
    audioOutputActive: Bool = false,
    meetContext: Bool = false,
    huddleWindow: Bool = false
  ) {
    self.appRunning = appRunning
    self.axJoinedControls = axJoinedControls
    self.axAuthoritative = axAuthoritative
    self.webRTCPeerConnection = webRTCPeerConnection
    self.audioInputActive = audioInputActive
    self.audioOutputActive = audioOutputActive
    self.meetContext = meetContext
    self.huddleWindow = huddleWindow
  }

  public var dictionary: [String: Bool] {
    [
      "app_running": appRunning,
      "ax_joined_controls": axJoinedControls,
      "ax_authoritative": axAuthoritative,
      "webrtc_peer_connection": webRTCPeerConnection,
      "audio_input": audioInputActive,
      "audio_output": audioOutputActive,
      "meet_context": meetContext,
      "huddle_window": huddleWindow,
    ]
  }
}

public struct DetectionReading: Codable, Equatable, Sendable {
  public let platform: MeetingPlatform
  public let participating: Bool
  public let confidence: Double
  public let signals: DetectionSignals
  public let axStatus: AccessibilityScanStatus

  public init(
    platform: MeetingPlatform,
    participating: Bool,
    confidence: Double,
    signals: DetectionSignals,
    axStatus: AccessibilityScanStatus
  ) {
    self.platform = platform
    self.participating = participating
    self.confidence = confidence
    self.signals = signals
    self.axStatus = axStatus
  }
}

public enum ConfidenceEvaluator {
  public static func evaluate(_ evidence: PlatformEvidence) -> DetectionReading {
    let accessibility = evidence.accessibility
    let axAuthoritative = accessibility.status == .ok
    let meetContext =
      accessibility.meetTabCount > 0 || accessibility.meetWebAreaCount > 0
    let signals = DetectionSignals(
      appRunning: !evidence.runningApplications.isEmpty,
      axJoinedControls: accessibility.joinedCallControlsPresent,
      axAuthoritative: axAuthoritative,
      webRTCPeerConnection: evidence.webRTCPeerConnection,
      audioInputActive: evidence.audioInputActive,
      audioOutputActive: evidence.audioOutputActive,
      meetContext: meetContext,
      huddleWindow: accessibility.slackHuddleWindow
    )

    let (participating, confidence) = score(signals: signals)
    return DetectionReading(
      platform: evidence.platform,
      participating: participating,
      confidence: confidence,
      signals: signals,
      axStatus: accessibility.status
    )
  }

  public static func evaluate(snapshot: ProbeSnapshot) -> [DetectionReading] {
    snapshot.platforms.map(evaluate)
  }

  static func score(signals: DetectionSignals) -> (participating: Bool, confidence: Double) {
    if signals.axJoinedControls {
      return (true, 0.95)
    }

    let mediaActive = signals.audioInputActive || signals.audioOutputActive
    if !signals.axAuthoritative,
      signals.appRunning,
      signals.webRTCPeerConnection,
      mediaActive
    {
      return (true, 0.75)
    }

    if signals.appRunning, signals.webRTCPeerConnection {
      return (false, 0.45)
    }

    if signals.appRunning, signals.meetContext || signals.huddleWindow {
      return (false, 0.20)
    }

    if signals.appRunning {
      return (false, 0.05)
    }

    return (false, 0.0)
  }
}

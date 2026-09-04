import Foundation

public enum ProbeFormatter {
  public static func humanReadable(_ snapshot: ProbeSnapshot) -> String {
    var lines = [
      "\(snapshot.timestamp) permissions accessibility=\(snapshot.accessibilityTrusted)",
      "\(snapshot.timestamp) collectors audio=\(snapshot.audioCollectorStatus.rawValue) power_assertions=\(snapshot.powerAssertionCollectorStatus.rawValue)",
    ]

    for platform in snapshot.platforms {
      let accessibility = platform.accessibility
      let apps =
        platform.runningApplications.isEmpty
        ? "-"
        : platform.runningApplications.joined(separator: ",")
      var fields = [
        "app_running=\(!platform.runningApplications.isEmpty)",
        "apps=\(quoted(apps))",
        "audio_input=\(platform.audioInputActive)",
        "audio_output=\(platform.audioOutputActive)",
        "webrtc_peer_connection=\(platform.webRTCPeerConnection)",
        "ax_status=\(accessibility.status.rawValue)",
        "ax_joined_controls=\(accessibility.joinedCallControlsPresent)",
        "ax_nodes=\(accessibility.scannedNodeCount)",
        "ax_truncated=\(accessibility.truncated)",
      ]
      switch platform.platform {
      case .googleMeet:
        fields.append(contentsOf: [
          "meet_tabs=\(accessibility.meetTabCount)",
          "meet_web_areas=\(accessibility.meetWebAreaCount)",
          "call_controls=\(accessibility.meetCallControls)",
          "leave_call=\(accessibility.meetLeaveCallControl)",
          "presentation_control=\(accessibility.meetPresentationControl)",
        ])
      case .slackHuddle:
        fields.append(contentsOf: [
          "huddle_window=\(accessibility.slackHuddleWindow)",
          "huddle_toolbar=\(accessibility.slackHuddleToolbar)",
          "leave_huddle=\(accessibility.slackLeaveHuddleControl)",
        ])
      }
      lines.append(
        "\(snapshot.timestamp) \(platform.platform.rawValue) \(fields.joined(separator: " "))")
    }

    for process in snapshot.audioProcesses where process.inputActive || process.outputActive {
      lines.append(
        "  audio platform=\(process.platform.rawValue) pid=\(process.pid) bundle=\(quoted(process.bundleID)) input=\(process.inputActive) output=\(process.outputActive)"
      )
    }
    for assertion in snapshot.powerAssertions {
      lines.append(
        "  assertion platform=\(assertion.platform.rawValue) pid=\(assertion.pid) process=\(quoted(assertion.processName)) type=\(quoted(assertion.assertionType)) name=\(quoted(assertion.assertionName))"
      )
    }
    return lines.joined(separator: "\n")
  }

  public static func jsonLine(_ snapshot: ProbeSnapshot) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(snapshot), as: UTF8.self)
  }

  private static func quoted(_ value: String) -> String {
    String(reflecting: value)
  }
}

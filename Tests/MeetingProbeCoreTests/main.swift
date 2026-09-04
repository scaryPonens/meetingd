import Foundation
import MeetingProbeCore

private enum HarnessError: Error {
  case requirementFailed(String)
}

private final class TestRunner {
  private(set) var failures = 0
  private(set) var checks = 0

  func expect(
    _ condition: @autoclosure () throws -> Bool,
    _ message: String,
    file: StaticString = #fileID,
    line: UInt = #line
  ) {
    checks += 1
    do {
      if try !condition() {
        failures += 1
        print("FAIL \(file):\(line): \(message)")
      }
    } catch {
      failures += 1
      print("FAIL \(file):\(line): \(message) threw \(error)")
    }
  }

  func test(_ name: String, _ body: () throws -> Void) {
    let before = failures
    do {
      try body()
    } catch {
      failures += 1
      print("FAIL \(name): \(error)")
    }
    if failures == before {
      print("PASS \(name)")
    }
  }
}

private func require<T>(_ value: T?, _ message: String) throws -> T {
  guard let value else { throw HarnessError.requirementFailed(message) }
  return value
}

private let runner = TestRunner()

runner.test("process classification") {
  runner.expect(
    ProcessClassifier.platform(bundleID: "com.google.Chrome.helper.renderer") == .googleMeet,
    "Chrome helper should classify as Google Meet evidence")
  runner.expect(
    ProcessClassifier.platform(bundleID: "com.tinyspeck.slackmacgap.helper") == .slackHuddle,
    "Slack helper should classify as Slack Huddle evidence")
  runner.expect(
    ProcessClassifier.platform(bundleID: nil, processName: "Brave Browser Helper") == .googleMeet,
    "browser process-name fallback should classify")
  runner.expect(
    ProcessClassifier.platform(bundleID: "com.apple.TextEdit") == nil,
    "unrelated app should not classify")
  runner.expect(
    ProcessClassifier.isSupportedMainApplication(bundleID: "com.apple.Safari"),
    "Safari main app should be supported")
  runner.expect(
    !ProcessClassifier.isSupportedMainApplication(
      bundleID: "com.apple.Safari.SandboxBroker"
    ),
    "Safari helper should not appear as a main app")
}

runner.test("Meet Accessibility reduction") {
  var evidence = AccessibilityEvidence(platform: .googleMeet)
  let nodes = [
    AccessibilityNodeSignal(
      role: "AXRadioButton",
      subrole: "AXTabButton",
      title: nil,
      description: "Meet - Engineering"
    ),
    AccessibilityNodeSignal(
      role: "AXWebArea",
      subrole: nil,
      title: "Meet - Engineering",
      description: nil
    ),
    AccessibilityNodeSignal(
      role: "AXGroup",
      subrole: "AXLandmarkRegion",
      title: nil,
      description: " Call   Controls "
    ),
    AccessibilityNodeSignal(
      role: "AXButton",
      subrole: nil,
      title: nil,
      description: "Leave call"
    ),
    AccessibilityNodeSignal(
      role: "AXButton",
      subrole: nil,
      title: nil,
      description: "Present now"
    ),
  ]
  for node in nodes {
    AccessibilityReducer.ingest(node, into: &evidence)
  }

  runner.expect(evidence.meetTabCount == 1, "Meet tab should be counted")
  runner.expect(evidence.meetWebAreaCount == 1, "Meet web area should be counted")
  runner.expect(
    evidence.joinedCallControlsPresent, "complete Meet control set should confirm UI evidence")
}

runner.test("Meet lobby does not look joined") {
  var evidence = AccessibilityEvidence(platform: .googleMeet)
  AccessibilityReducer.ingest(
    AccessibilityNodeSignal(
      role: "AXRadioButton",
      subrole: "AXTabButton",
      title: "Meet",
      description: nil
    ),
    into: &evidence
  )

  runner.expect(evidence.meetTabCount == 1, "Meet tab should remain observable")
  runner.expect(!evidence.joinedCallControlsPresent, "Meet tab alone must not confirm joined UI")
}

runner.test("Slack Accessibility reduction") {
  var evidence = AccessibilityEvidence(platform: .slackHuddle)
  AccessibilityReducer.ingest(
    AccessibilityNodeSignal(
      role: "AXWindow",
      subrole: "AXStandardWindow",
      title: "Huddle: Project room",
      description: nil
    ),
    into: &evidence
  )
  runner.expect(evidence.slackHuddleWindow, "Huddle window should be observed")
  runner.expect(!evidence.joinedCallControlsPresent, "window alone must not confirm joined UI")

  AccessibilityReducer.ingest(
    AccessibilityNodeSignal(
      role: "AXToolbar",
      subrole: nil,
      title: nil,
      description: "Huddle window actions"
    ),
    into: &evidence
  )
  AccessibilityReducer.ingest(
    AccessibilityNodeSignal(
      role: "AXButton",
      subrole: nil,
      title: nil,
      description: "Leave huddle"
    ),
    into: &evidence
  )
  runner.expect(
    evidence.joinedCallControlsPresent, "toolbar and leave control should confirm Huddle UI")
}

runner.test("platform aggregation") {
  let chrome = ApplicationSignal(
    name: "Google Chrome",
    bundleID: "com.google.Chrome",
    pid: 10,
    platform: .googleMeet
  )
  let audio = AudioProcessSignal(
    bundleID: "com.google.Chrome.helper",
    pid: 11,
    inputActive: true,
    outputActive: false,
    platform: .googleMeet
  )
  let assertion = PowerAssertionSignal(
    pid: 11,
    processName: "Google Chrome Helper",
    bundleID: "com.google.Chrome.helper",
    assertionName: "WebRTC has active PeerConnections",
    assertionType: "NoIdleSleepAssertion",
    platform: .googleMeet
  )
  let snapshot = ProbeSnapshot(
    timestamp: "2026-09-03T12:00:00Z",
    accessibilityTrusted: false,
    applications: [chrome],
    audioCollectorStatus: .ok,
    audioProcesses: [audio],
    powerAssertionCollectorStatus: .ok,
    powerAssertions: [assertion],
    accessibilityEvidence: [
      .googleMeet: AccessibilityEvidence(
        platform: .googleMeet,
        status: .permissionDenied
      )
    ]
  )

  let meet = try require(
    snapshot.platforms.first { $0.platform == .googleMeet },
    "Meet aggregate missing"
  )
  runner.expect(meet.runningApplications == ["Google Chrome"], "running app should aggregate")
  runner.expect(meet.audioInputActive, "input activity should aggregate")
  runner.expect(!meet.audioOutputActive, "inactive output should remain false")
  runner.expect(meet.webRTCPeerConnection, "WebRTC assertion should aggregate")

  let slack = try require(
    snapshot.platforms.first { $0.platform == .slackHuddle },
    "Slack aggregate missing"
  )
  runner.expect(slack.runningApplications.isEmpty, "Slack should remain absent")
  runner.expect(
    slack.accessibility.status == .appNotRunning, "absent Slack AX status should be explicit")
}

runner.test("injected sampler") {
  let sampler = ProbeSampler(
    applications: { [] },
    audioProcesses: { SignalCollection(status: .ok, values: []) },
    powerAssertions: { SignalCollection(status: .ok, values: []) },
    accessibility: { applications, trusted, maxNodes in
      runner.expect(applications.isEmpty, "injected app list should flow to Accessibility provider")
      runner.expect(trusted, "injected permission should flow to Accessibility provider")
      runner.expect(maxNodes == 456, "configured node cap should flow to Accessibility provider")
      return [:]
    },
    accessibilityTrusted: { true },
    timestamp: { "fixed" },
    maxAccessibilityNodesPerApplication: 456
  )

  let snapshot = sampler.sample()
  runner.expect(snapshot.timestamp == "fixed", "injected timestamp should be used")
  runner.expect(snapshot.accessibilityTrusted, "injected permission result should be used")
}

runner.test("human and JSON formatting") {
  let snapshot = ProbeSnapshot(
    timestamp: "fixed",
    accessibilityTrusted: false,
    applications: [],
    audioCollectorStatus: .ok,
    audioProcesses: [],
    powerAssertionCollectorStatus: .ok,
    powerAssertions: [],
    accessibilityEvidence: [:]
  )

  let output = ProbeFormatter.humanReadable(snapshot)
  runner.expect(
    output.contains("permissions accessibility=false"), "permission state should be visible")
  runner.expect(
    output.contains("collectors audio=ok power_assertions=ok"),
    "collector health should be visible"
  )
  runner.expect(output.contains("google_meet app_running=false"), "Meet absence should be visible")
  runner.expect(
    output.contains("slack_huddle app_running=false"), "Slack absence should be visible")
  runner.expect(output.contains("ax_status=app_not_running"), "AX reason should be visible")

  let line = try ProbeFormatter.jsonLine(snapshot)
  runner.expect(!line.contains("\n"), "JSON output should be one line")
  runner.expect(
    try JSONDecoder().decode(ProbeSnapshot.self, from: Data(line.utf8)) == snapshot,
    "JSON output should round-trip")
}

runner.test("CLI options") {
  let options = try ProbeOptions.parse([
    "--once",
    "--json",
    "--interval", "0.5",
    "--max-ax-nodes", "500",
    "--request-accessibility",
  ])

  runner.expect(options.runOnce, "--once should parse")
  runner.expect(options.json, "--json should parse")
  runner.expect(options.interval == 0.5, "--interval should parse")
  runner.expect(options.maxAccessibilityNodes == 500, "--max-ax-nodes should parse")
  runner.expect(options.requestAccessibility, "--request-accessibility should parse")

  do {
    _ = try ProbeOptions.parse(["--interval", "0.1"])
    runner.expect(false, "unsafe polling rate should fail")
  } catch is ProbeOptionError {
    runner.expect(true, "unsafe polling rate rejected")
  }

  do {
    _ = try ProbeOptions.parse(["--record"])
    runner.expect(false, "unknown recording option should fail")
  } catch is ProbeOptionError {
    runner.expect(true, "unknown option rejected")
  }
}

if runner.failures == 0 {
  print("PASS \(runner.checks) checks")
} else {
  print("FAIL \(runner.failures) of \(runner.checks) checks")
  exit(1)
}

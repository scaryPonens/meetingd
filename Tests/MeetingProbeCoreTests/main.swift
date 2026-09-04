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

private func meetEvidence(
  joined: Bool,
  appRunning: Bool = true,
  webrtc: Bool = false,
  audioIn: Bool = false,
  audioOut: Bool = false,
  axStatus: AccessibilityScanStatus = .ok,
  meetTabs: Int = 0
) -> PlatformEvidence {
  var accessibility = AccessibilityEvidence(platform: .googleMeet, status: axStatus)
  if joined {
    accessibility.meetWebAreaCount = 1
    accessibility.meetCallControls = true
    accessibility.meetLeaveCallControl = true
    accessibility.meetPresentationControl = true
  }
  accessibility.meetTabCount = meetTabs
  return PlatformEvidence(
    platform: .googleMeet,
    runningApplications: appRunning ? ["Google Chrome"] : [],
    audioInputActive: audioIn,
    audioOutputActive: audioOut,
    webRTCPeerConnection: webrtc,
    accessibility: accessibility
  )
}

private func slackEvidence(
  joined: Bool,
  appRunning: Bool = true,
  inviteWindow: Bool = false,
  axStatus: AccessibilityScanStatus = .ok
) -> PlatformEvidence {
  var accessibility = AccessibilityEvidence(platform: .slackHuddle, status: axStatus)
  accessibility.slackHuddleWindow = inviteWindow || joined
  if joined {
    accessibility.slackHuddleToolbar = true
    accessibility.slackLeaveHuddleControl = true
  }
  return PlatformEvidence(
    platform: .slackHuddle,
    runningApplications: appRunning ? ["Slack"] : [],
    audioInputActive: false,
    audioOutputActive: false,
    webRTCPeerConnection: false,
    accessibility: accessibility
  )
}

runner.test("confidence ignores lobby and invite") {
  let lobby = ConfidenceEvaluator.evaluate(
    meetEvidence(joined: false, meetTabs: 1)
  )
  runner.expect(!lobby.participating, "Meet lobby must not participate")
  runner.expect(lobby.confidence == 0.20, "Meet tab context should be low confidence")

  let invite = ConfidenceEvaluator.evaluate(
    slackEvidence(joined: false, inviteWindow: true)
  )
  runner.expect(!invite.participating, "Huddle invite/window alone must not participate")
}

runner.test("confidence accepts joined AX and fallback media") {
  let joined = ConfidenceEvaluator.evaluate(meetEvidence(joined: true))
  runner.expect(joined.participating, "joined AX controls should participate")
  runner.expect(joined.confidence == 0.95, "joined AX confidence")

  let fallback = ConfidenceEvaluator.evaluate(
    meetEvidence(
      joined: false,
      webrtc: true,
      audioIn: true,
      axStatus: .permissionDenied
    )
  )
  runner.expect(fallback.participating, "AX-denied WebRTC+audio fallback should participate")
  runner.expect(fallback.confidence == 0.75, "fallback confidence")
}

runner.test("Meet lifecycle join and leave") {
  var machine = LifecycleStateMachine(
    platform: .googleMeet,
    configuration: LifecycleConfiguration(startConfirmations: 2, endConfirmations: 3),
    makeMeetingID: { "meet-1" }
  )

  let lobby = ConfidenceEvaluator.evaluate(meetEvidence(joined: false, meetTabs: 1))
  runner.expect(machine.observe(lobby, at: "t0").events.isEmpty, "lobby emits nothing")

  let joined = ConfidenceEvaluator.evaluate(meetEvidence(joined: true))
  runner.expect(machine.observe(joined, at: "t1").events.isEmpty, "first join poll waits")
  let started = machine.observe(joined, at: "t2")
  runner.expect(started.events.count == 1, "second join poll starts meeting")
  runner.expect(started.events.first?.event == .meetingStarted, "emits meeting_started")
  runner.expect(started.state == .active, "state becomes ACTIVE")

  let muted = ConfidenceEvaluator.evaluate(
    meetEvidence(joined: true, audioIn: false, audioOut: false)
  )
  runner.expect(machine.observe(muted, at: "t3").events.isEmpty, "mute remains active")

  let background = ConfidenceEvaluator.evaluate(meetEvidence(joined: true))
  runner.expect(machine.observe(background, at: "t4").events.isEmpty, "background remains active")

  let left = ConfidenceEvaluator.evaluate(meetEvidence(joined: false, meetTabs: 1))
  runner.expect(machine.observe(left, at: "t5").events.isEmpty, "first leave poll waits")
  runner.expect(machine.observe(left, at: "t6").events.isEmpty, "second leave poll waits")
  let ended = machine.observe(left, at: "t7")
  runner.expect(ended.events.count == 1, "third leave poll ends meeting")
  runner.expect(ended.events.first?.event == .meetingEnded, "emits meeting_ended")
  runner.expect(ended.events.first?.meetingID == "meet-1", "ended reuses meeting id")
  runner.expect(ended.state == .idle, "state returns IDLE")
}

runner.test("Slack lifecycle join and leave") {
  var machine = LifecycleStateMachine(
    platform: .slackHuddle,
    configuration: LifecycleConfiguration(startConfirmations: 2, endConfirmations: 2),
    makeMeetingID: { "huddle-1" }
  )

  let invite = ConfidenceEvaluator.evaluate(slackEvidence(joined: false, inviteWindow: true))
  runner.expect(machine.observe(invite, at: "t0").events.isEmpty, "invite emits nothing")

  let joined = ConfidenceEvaluator.evaluate(slackEvidence(joined: true))
  _ = machine.observe(joined, at: "t1")
  let started = machine.observe(joined, at: "t2")
  runner.expect(started.events.first?.event == .meetingStarted, "huddle starts")

  let left = ConfidenceEvaluator.evaluate(slackEvidence(joined: false, appRunning: true))
  _ = machine.observe(left, at: "t3")
  let ended = machine.observe(left, at: "t4")
  runner.expect(ended.events.first?.event == .meetingEnded, "huddle ends")
}

runner.test("transient signal loss does not end meeting") {
  var machine = LifecycleStateMachine(
    platform: .googleMeet,
    configuration: LifecycleConfiguration(startConfirmations: 1, endConfirmations: 3),
    makeMeetingID: { "meet-2" }
  )
  let joined = ConfidenceEvaluator.evaluate(meetEvidence(joined: true))
  _ = machine.observe(joined, at: "t0")
  let lost = ConfidenceEvaluator.evaluate(meetEvidence(joined: false, meetTabs: 1))
  runner.expect(machine.observe(lost, at: "t1").events.isEmpty, "one lost poll keeps meeting")
  let recovered = machine.observe(joined, at: "t2")
  runner.expect(recovered.events.isEmpty, "recovery emits no second start")
  runner.expect(recovered.state == .active, "recovery returns ACTIVE")
}

runner.test("rapid join leave and crash") {
  var machine = LifecycleStateMachine(
    platform: .googleMeet,
    configuration: LifecycleConfiguration(startConfirmations: 1, endConfirmations: 1),
    makeMeetingID: { "meet-3" }
  )
  let joined = ConfidenceEvaluator.evaluate(meetEvidence(joined: true))
  let started = machine.observe(joined, at: "t0")
  runner.expect(started.events.count == 1, "rapid start")

  let crashed = ConfidenceEvaluator.evaluate(meetEvidence(joined: false, appRunning: false))
  let ended = machine.observe(crashed, at: "t1")
  runner.expect(ended.events.count == 1, "crash ends meeting")
  runner.expect(ended.state == .idle, "crash returns idle")
}

runner.test("daemon runtime emits NDJSON-shaped events") {
  let collector = CollectingEventEmitter()
  final class IDSource: @unchecked Sendable {
    private var values = ["id-a", "id-b"]
    func next() -> String {
      values.isEmpty ? "id-overflow" : values.removeFirst()
    }
  }
  let ids = IDSource()
  var runtime = DaemonRuntime(
    configuration: LifecycleConfiguration(startConfirmations: 1, endConfirmations: 1),
    emitter: collector,
    writeStatus: false,
    makeMeetingID: { ids.next() }
  )

  var accessibility = AccessibilityEvidence(platform: .googleMeet, status: .ok)
  accessibility.meetWebAreaCount = 1
  accessibility.meetCallControls = true
  accessibility.meetLeaveCallControl = true
  accessibility.meetPresentationControl = true

  let activeSnapshot = ProbeSnapshot(
    timestamp: "2026-09-04T12:00:00Z",
    accessibilityTrusted: true,
    applications: [
      ApplicationSignal(
        name: "Google Chrome",
        bundleID: "com.google.Chrome",
        pid: 1,
        platform: .googleMeet
      )
    ],
    audioCollectorStatus: .ok,
    audioProcesses: [],
    powerAssertionCollectorStatus: .ok,
    powerAssertions: [],
    accessibilityEvidence: [.googleMeet: accessibility]
  )
  _ = try runtime.process(activeSnapshot)
  let idleSnapshot = ProbeSnapshot(
    timestamp: "2026-09-04T12:00:01Z",
    accessibilityTrusted: true,
    applications: [],
    audioCollectorStatus: .ok,
    audioProcesses: [],
    powerAssertionCollectorStatus: .ok,
    powerAssertions: [],
    accessibilityEvidence: [:]
  )
  _ = try runtime.process(idleSnapshot)

  let events = collector.events()
  runner.expect(events.count == 2, "runtime should emit start and end")
  runner.expect(events[0].event == .meetingStarted, "first event is start")
  runner.expect(events[1].event == .meetingEnded, "second event is end")
  runner.expect(events[0].meetingID == events[1].meetingID, "ids match")

  let line = String(decoding: try JSONEncoder().encode(events[0]), as: UTF8.self)
  runner.expect(line.contains("\"event\":\"meeting_started\""), "event key encoded")
  runner.expect(line.contains("\"meeting_id\""), "meeting_id key encoded")
}

runner.test("daemon CLI options") {
  let options = try DaemonOptions.parse([
    "run",
    "--interval", "1",
    "--start-confirmations", "2",
    "--end-confirmations", "3",
    "--status-file", "/tmp/meetingd-status.json",
  ])
  runner.expect(options.command == .run, "run command")
  runner.expect(options.interval == 1, "interval")
  runner.expect(options.startConfirmations == 2, "start confirmations")
  runner.expect(options.endConfirmations == 3, "end confirmations")
  runner.expect(options.statusPath == "/tmp/meetingd-status.json", "status path")

  do {
    _ = try DaemonOptions.parse(["record"])
    runner.expect(false, "unknown command should fail")
  } catch is DaemonOptionError {
    runner.expect(true, "unknown command rejected")
  }
}

if runner.failures == 0 {
  print("PASS \(runner.checks) checks")
} else {
  print("FAIL \(runner.failures) of \(runner.checks) checks")
  exit(1)
}

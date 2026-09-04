import Foundation

public enum DaemonRuntimeError: Error, CustomStringConvertible {
  case statusUnavailable(path: String)

  public var description: String {
    switch self {
    case .statusUnavailable(let path):
      "no status file at \(path); start `meetingd run` first or pass --status-file"
    }
  }
}

public struct DaemonRuntime {
  private var machines: [MeetingPlatform: LifecycleStateMachine]
  private let emitter: any EventEmitter
  private let statusURL: URL
  private let writeStatus: Bool

  public init(
    configuration: LifecycleConfiguration = LifecycleConfiguration(),
    emitter: any EventEmitter = StdoutNDJSONEventEmitter(),
    statusURL: URL = StatusStore.defaultStatusURL,
    writeStatus: Bool = true,
    makeMeetingID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) {
    self.emitter = emitter
    self.statusURL = statusURL
    self.writeStatus = writeStatus
    var machines: [MeetingPlatform: LifecycleStateMachine] = [:]
    for platform in MeetingPlatform.allCases {
      machines[platform] = LifecycleStateMachine(
        platform: platform,
        configuration: configuration,
        makeMeetingID: makeMeetingID
      )
    }
    self.machines = machines
  }

  @discardableResult
  public mutating func process(_ snapshot: ProbeSnapshot) throws -> DaemonStatusSnapshot {
    let readings = ConfidenceEvaluator.evaluate(snapshot: snapshot)
    var platformStatuses: [PlatformRuntimeStatus] = []

    for reading in readings {
      guard var machine = machines[reading.platform] else { continue }
      let transition = machine.observe(reading, at: snapshot.timestamp)
      machines[reading.platform] = machine
      for event in transition.events {
        try emitter.emit(event)
      }
      platformStatuses.append(
        PlatformRuntimeStatus(
          platform: reading.platform,
          state: transition.state,
          confidence: reading.confidence,
          meetingID: transition.activeMeeting?.meetingID,
          startedAt: transition.activeMeeting?.startedAt,
          signals: reading.signals,
          axStatus: reading.axStatus
        )
      )
    }

    platformStatuses.sort { $0.platform.rawValue < $1.platform.rawValue }
    let status = DaemonStatusSnapshot(
      timestamp: snapshot.timestamp,
      accessibilityTrusted: snapshot.accessibilityTrusted,
      platforms: platformStatuses
    )
    if writeStatus {
      try StatusStore.write(status, to: statusURL)
    }
    return status
  }

  public func currentStatuses() -> [PlatformRuntimeStatus] {
    MeetingPlatform.allCases.compactMap { platform in
      guard let machine = machines[platform] else { return nil }
      return PlatformRuntimeStatus(
        platform: platform,
        state: machine.state,
        confidence: machine.activeMeeting?.confidence ?? 0,
        meetingID: machine.activeMeeting?.meetingID,
        startedAt: machine.activeMeeting?.startedAt
      )
    }
  }
}

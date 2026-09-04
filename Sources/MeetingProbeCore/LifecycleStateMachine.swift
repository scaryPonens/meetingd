import Foundation

public enum MeetingLifecycleState: String, Codable, Equatable, Sendable {
  case idle = "IDLE"
  case possibleMeeting = "POSSIBLE_MEETING"
  case active = "ACTIVE"
  case possibleEnd = "POSSIBLE_END"
}

public struct LifecycleConfiguration: Equatable, Sendable {
  public var startConfirmations: Int
  public var endConfirmations: Int

  public init(startConfirmations: Int = 2, endConfirmations: Int = 3) {
    self.startConfirmations = max(1, startConfirmations)
    self.endConfirmations = max(1, endConfirmations)
  }
}

public struct ActiveMeeting: Equatable, Sendable {
  public let meetingID: String
  public let platform: MeetingPlatform
  public let startedAt: String
  public var confidence: Double

  public init(
    meetingID: String,
    platform: MeetingPlatform,
    startedAt: String,
    confidence: Double
  ) {
    self.meetingID = meetingID
    self.platform = platform
    self.startedAt = startedAt
    self.confidence = confidence
  }
}

public struct LifecycleTransition: Equatable, Sendable {
  public let state: MeetingLifecycleState
  public let events: [MeetingEvent]
  public let activeMeeting: ActiveMeeting?

  public init(
    state: MeetingLifecycleState,
    events: [MeetingEvent] = [],
    activeMeeting: ActiveMeeting? = nil
  ) {
    self.state = state
    self.events = events
    self.activeMeeting = activeMeeting
  }
}

public struct LifecycleStateMachine: Sendable {
  public private(set) var platform: MeetingPlatform
  public private(set) var state: MeetingLifecycleState
  public private(set) var activeMeeting: ActiveMeeting?
  public private(set) var positiveStreak: Int
  public private(set) var negativeStreak: Int
  public var configuration: LifecycleConfiguration

  private let makeMeetingID: @Sendable () -> String

  public init(
    platform: MeetingPlatform,
    configuration: LifecycleConfiguration = LifecycleConfiguration(),
    makeMeetingID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) {
    self.platform = platform
    self.state = .idle
    self.activeMeeting = nil
    self.positiveStreak = 0
    self.negativeStreak = 0
    self.configuration = configuration
    self.makeMeetingID = makeMeetingID
  }

  public mutating func observe(
    _ reading: DetectionReading,
    at timestamp: String
  ) -> LifecycleTransition {
    precondition(reading.platform == platform)

    if reading.participating {
      positiveStreak += 1
      negativeStreak = 0
    } else {
      negativeStreak += 1
      positiveStreak = 0
    }

    var events: [MeetingEvent] = []

    switch state {
    case .idle:
      if reading.participating {
        state = .possibleMeeting
        if positiveStreak >= configuration.startConfirmations {
          events.append(contentsOf: activate(confidence: reading.confidence, at: timestamp))
        }
      } else if reading.confidence > 0 {
        state = .possibleMeeting
      }

    case .possibleMeeting:
      if reading.participating {
        if positiveStreak >= configuration.startConfirmations {
          events.append(contentsOf: activate(confidence: reading.confidence, at: timestamp))
        }
      } else if reading.confidence == 0 {
        state = .idle
      }

    case .active:
      if let meeting = activeMeeting {
        activeMeeting = ActiveMeeting(
          meetingID: meeting.meetingID,
          platform: meeting.platform,
          startedAt: meeting.startedAt,
          confidence: reading.confidence
        )
      }
      if !reading.participating {
        state = .possibleEnd
        if negativeStreak >= configuration.endConfirmations {
          events.append(contentsOf: deactivate(at: timestamp))
        }
      }

    case .possibleEnd:
      if reading.participating {
        state = .active
        if let meeting = activeMeeting {
          activeMeeting = ActiveMeeting(
            meetingID: meeting.meetingID,
            platform: meeting.platform,
            startedAt: meeting.startedAt,
            confidence: reading.confidence
          )
        }
      } else if negativeStreak >= configuration.endConfirmations {
        events.append(contentsOf: deactivate(at: timestamp))
      }
    }

    return LifecycleTransition(state: state, events: events, activeMeeting: activeMeeting)
  }

  private mutating func activate(confidence: Double, at timestamp: String) -> [MeetingEvent] {
    let meeting = ActiveMeeting(
      meetingID: makeMeetingID(),
      platform: platform,
      startedAt: timestamp,
      confidence: confidence
    )
    activeMeeting = meeting
    state = .active
    positiveStreak = 0
    negativeStreak = 0
    return [
      MeetingEvent(
        event: .meetingStarted,
        platform: platform,
        timestamp: timestamp,
        meetingID: meeting.meetingID,
        title: nil,
        confidence: confidence
      )
    ]
  }

  private mutating func deactivate(at timestamp: String) -> [MeetingEvent] {
    let meetingID = activeMeeting?.meetingID
    activeMeeting = nil
    state = .idle
    positiveStreak = 0
    negativeStreak = 0
    guard let meetingID else { return [] }
    return [
      MeetingEvent(
        event: .meetingEnded,
        platform: platform,
        timestamp: timestamp,
        meetingID: meetingID,
        title: nil,
        confidence: nil
      )
    ]
  }
}

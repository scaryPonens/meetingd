import Foundation
import UserNotifications

public protocol DesktopNotifier: Sendable {
  func postMeetingDetected(platform: MeetingPlatform, meetingID: String)
}

/// UserNotifications requires a real .app bundle; bare SPM/CLI binaries crash otherwise.
public enum DesktopNotifierSupport {
  public static func canUseUserNotifications(bundle: Bundle = .main) -> Bool {
    bundle.bundleURL.pathExtension.lowercased() == "app"
      && bundle.bundleIdentifier != nil
  }

  public static func makeDefaultNotifier() -> any DesktopNotifier {
    if canUseUserNotifications() {
      return UserNotificationsDesktopNotifier()
    }
    return AppleScriptDesktopNotifier()
  }
}

public struct AppleScriptDesktopNotifier: DesktopNotifier {
  public init() {}

  public func postMeetingDetected(platform: MeetingPlatform, meetingID: String) {
    let title = "meetingd"
    let body = "\(platform.displayName) detected"
    let script =
      "display notification \"\(Self.escape(body))\" with title \"\(Self.escape(title))\""
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      // Non-fatal: NDJSON events still emit.
    }
  }

  public static func escape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }
}

public struct UserNotificationsDesktopNotifier: DesktopNotifier {
  public init() {}

  public func postMeetingDetected(platform: MeetingPlatform, meetingID: String) {
    let content = UNMutableNotificationContent()
    content.title = "meetingd"
    content.body = "\(platform.displayName) detected"
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: meetingID,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
  }

  /// Requests notification authorization. Returns whether alerts were granted.
  /// Denial is non-fatal for the daemon; callers may log and continue.
  /// Must not be called unless ``DesktopNotifierSupport/canUseUserNotifications`` is true.
  public static func requestAuthorization(timeout: TimeInterval = 5) -> Bool {
    guard DesktopNotifierSupport.canUseUserNotifications() else {
      return false
    }
    final class Box: @unchecked Sendable {
      var granted = false
    }
    let box = Box()
    let semaphore = DispatchSemaphore(value: 0)
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
      ok,
      _ in
      box.granted = ok
      semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + timeout)
    return box.granted
  }
}

public struct DesktopNotificationEventEmitter: EventEmitter {
  private let notifier: any DesktopNotifier

  public init(notifier: (any DesktopNotifier)? = nil) {
    self.notifier = notifier ?? DesktopNotifierSupport.makeDefaultNotifier()
  }

  public func emit(_ event: MeetingEvent) throws {
    guard event.event == .meetingStarted else { return }
    notifier.postMeetingDetected(platform: event.platform, meetingID: event.meetingID)
  }
}

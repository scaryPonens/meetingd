import AppKit
@preconcurrency import ApplicationServices
import CoreAudio
import Foundation
import IOKit.pwr_mgt

public enum SystemCollectors {
  public static func supportedApplications() -> [ApplicationSignal] {
    NSWorkspace.shared.runningApplications.compactMap { application in
      guard let bundleID = application.bundleIdentifier,
        ProcessClassifier.isSupportedMainApplication(bundleID: bundleID),
        let platform = ProcessClassifier.platform(bundleID: bundleID)
      else {
        return nil
      }
      return ApplicationSignal(
        name: application.localizedName ?? bundleID,
        bundleID: bundleID,
        pid: application.processIdentifier,
        platform: platform
      )
    }
    .sorted { lhs, rhs in
      if lhs.platform != rhs.platform { return lhs.platform.rawValue < rhs.platform.rawValue }
      return lhs.pid < rhs.pid
    }
  }

  public static func audioProcesses() -> SignalCollection<AudioProcessSignal> {
    guard #available(macOS 14.2, *) else {
      return SignalCollection(status: .unsupported, values: [])
    }

    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    let systemObject = AudioObjectID(kAudioObjectSystemObject)
    guard
      AudioObjectGetPropertyDataSize(
        systemObject,
        &address,
        0,
        nil,
        &dataSize
      ) == noErr
    else {
      return SignalCollection(status: .failed, values: [])
    }
    guard dataSize > 0 else {
      return SignalCollection(status: .ok, values: [])
    }

    var objectIDs = [AudioObjectID](
      repeating: 0,
      count: Int(dataSize) / MemoryLayout<AudioObjectID>.stride
    )
    guard
      AudioObjectGetPropertyData(
        systemObject,
        &address,
        0,
        nil,
        &dataSize,
        &objectIDs
      ) == noErr
    else {
      return SignalCollection(status: .failed, values: [])
    }

    let values: [AudioProcessSignal] = objectIDs.compactMap { objectID -> AudioProcessSignal? in
      guard
        let bundleID = stringProperty(
          objectID,
          selector: kAudioProcessPropertyBundleID
        ), !bundleID.isEmpty,
        let platform = ProcessClassifier.platform(bundleID: bundleID)
      else {
        return nil
      }
      return AudioProcessSignal(
        bundleID: bundleID,
        pid: int32Property(objectID, selector: kAudioProcessPropertyPID) ?? -1,
        inputActive: uint32Property(
          objectID,
          selector: kAudioProcessPropertyIsRunningInput
        ) != 0,
        outputActive: uint32Property(
          objectID,
          selector: kAudioProcessPropertyIsRunningOutput
        ) != 0,
        platform: platform
      )
    }
    .sorted { lhs, rhs in
      if lhs.platform != rhs.platform { return lhs.platform.rawValue < rhs.platform.rawValue }
      return lhs.pid < rhs.pid
    }
    return SignalCollection(status: .ok, values: values)
  }

  public static func powerAssertions() -> SignalCollection<PowerAssertionSignal> {
    var unmanagedAssertions: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&unmanagedAssertions) == kIOReturnSuccess,
      let assertions = unmanagedAssertions?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
    else {
      return SignalCollection(status: .failed, values: [])
    }

    var values: [PowerAssertionSignal] = []
    for (pidNumber, processAssertions) in assertions {
      let pid = pidNumber.int32Value
      let runningApplication = NSRunningApplication(processIdentifier: pid)
      let bundleID = runningApplication?.bundleIdentifier

      for assertion in processAssertions {
        let processName =
          assertion["Process Name"] as? String
          ?? runningApplication?.localizedName
          ?? "unknown"
        guard
          let platform = ProcessClassifier.platform(
            bundleID: bundleID,
            processName: processName
          )
        else {
          continue
        }
        values.append(
          PowerAssertionSignal(
            pid: pid,
            processName: processName,
            bundleID: bundleID,
            assertionName: assertion["AssertName"] as? String ?? "",
            assertionType: assertion["AssertType"] as? String ?? "",
            platform: platform
          )
        )
      }
    }

    values.sort { lhs, rhs in
      if lhs.platform != rhs.platform { return lhs.platform.rawValue < rhs.platform.rawValue }
      if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
      return lhs.assertionName < rhs.assertionName
    }
    return SignalCollection(status: .ok, values: values)
  }

  public static func accessibilityEvidence(
    applications: [ApplicationSignal],
    trusted: Bool,
    maxNodesPerApplication: Int
  ) -> [MeetingPlatform: AccessibilityEvidence] {
    var result: [MeetingPlatform: AccessibilityEvidence] = [:]
    for platform in MeetingPlatform.allCases {
      let platformApplications = applications.filter { $0.platform == platform }
      guard !platformApplications.isEmpty else {
        result[platform] = AccessibilityEvidence(
          platform: platform,
          status: .appNotRunning
        )
        continue
      }
      guard trusted else {
        result[platform] = AccessibilityEvidence(
          platform: platform,
          status: .permissionDenied
        )
        continue
      }

      var combined = AccessibilityEvidence(platform: platform)
      for application in platformApplications {
        combined.merge(
          scanAccessibilityTree(
            pid: application.pid,
            platform: platform,
            maxNodes: maxNodesPerApplication
          )
        )
      }
      result[platform] = combined
    }
    return result
  }

  public static func accessibilityIsTrusted(prompt: Bool = false) -> Bool {
    guard prompt else { return AXIsProcessTrusted() }
    let options =
      [
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
      ] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  private static func scanAccessibilityTree(
    pid: Int32,
    platform: MeetingPlatform,
    maxNodes: Int
  ) -> AccessibilityEvidence {
    guard maxNodes > 0 else {
      var evidence = AccessibilityEvidence(platform: platform, status: .failed)
      evidence.truncated = true
      return evidence
    }

    let root = AXUIElementCreateApplication(pid)
    var stack = [root]
    stack.reserveCapacity(128)
    var evidence = AccessibilityEvidence(platform: platform)

    while let element = stack.popLast() {
      if evidence.scannedNodeCount >= maxNodes {
        evidence.truncated = true
        break
      }
      evidence.scannedNodeCount += 1
      AccessibilityReducer.ingest(
        AccessibilityNodeSignal(
          role: stringAttribute(element, kAXRoleAttribute),
          subrole: stringAttribute(element, kAXSubroleAttribute),
          title: stringAttribute(element, kAXTitleAttribute),
          description: stringAttribute(element, kAXDescriptionAttribute)
        ),
        into: &evidence
      )

      if let children = elementAttribute(element, kAXChildrenAttribute) as? [AXUIElement] {
        stack.append(contentsOf: children.reversed())
      }
    }
    return evidence
  }

  private static func elementAttribute(
    _ element: AXUIElement,
    _ attribute: String
  ) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
      return nil
    }
    return value
  }

  private static func stringAttribute(
    _ element: AXUIElement,
    _ attribute: String
  ) -> String? {
    elementAttribute(element, attribute) as? String
  }

  private static func propertyAddress(
    _ selector: AudioObjectPropertySelector
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  private static func stringProperty(
    _ objectID: AudioObjectID,
    selector: AudioObjectPropertySelector
  ) -> String? {
    var address = propertyAddress(selector)
    var dataSize = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, pointer)
    }
    guard status == noErr, let value else { return nil }
    return value as String
  }

  private static func uint32Property(
    _ objectID: AudioObjectID,
    selector: AudioObjectPropertySelector
  ) -> UInt32 {
    var address = propertyAddress(selector)
    var dataSize = UInt32(MemoryLayout<UInt32>.size)
    var value: UInt32 = 0
    guard
      AudioObjectGetPropertyData(
        objectID,
        &address,
        0,
        nil,
        &dataSize,
        &value
      ) == noErr
    else {
      return 0
    }
    return value
  }

  private static func int32Property(
    _ objectID: AudioObjectID,
    selector: AudioObjectPropertySelector
  ) -> Int32? {
    var address = propertyAddress(selector)
    var dataSize = UInt32(MemoryLayout<Int32>.size)
    var value: Int32 = 0
    guard
      AudioObjectGetPropertyData(
        objectID,
        &address,
        0,
        nil,
        &dataSize,
        &value
      ) == noErr
    else {
      return nil
    }
    return value
  }
}

public struct ProbeSampler {
  public typealias ApplicationProvider = () -> [ApplicationSignal]
  public typealias AudioProvider = () -> SignalCollection<AudioProcessSignal>
  public typealias AssertionProvider = () -> SignalCollection<PowerAssertionSignal>
  public typealias AccessibilityProvider = (
    _ applications: [ApplicationSignal],
    _ trusted: Bool,
    _ maxNodesPerApplication: Int
  ) -> [MeetingPlatform: AccessibilityEvidence]
  public typealias PermissionProvider = () -> Bool
  public typealias TimestampProvider = () -> String

  private let applications: ApplicationProvider
  private let audioProcesses: AudioProvider
  private let powerAssertions: AssertionProvider
  private let accessibility: AccessibilityProvider
  private let accessibilityTrusted: PermissionProvider
  private let timestamp: TimestampProvider
  private let maxAccessibilityNodesPerApplication: Int

  public init(
    applications: @escaping ApplicationProvider = SystemCollectors.supportedApplications,
    audioProcesses: @escaping AudioProvider = SystemCollectors.audioProcesses,
    powerAssertions: @escaping AssertionProvider = SystemCollectors.powerAssertions,
    accessibility: @escaping AccessibilityProvider = SystemCollectors.accessibilityEvidence,
    accessibilityTrusted: @escaping PermissionProvider = {
      SystemCollectors.accessibilityIsTrusted()
    },
    timestamp: @escaping TimestampProvider = {
      ISO8601DateFormatter().string(from: Date())
    },
    maxAccessibilityNodesPerApplication: Int = 3_000
  ) {
    self.applications = applications
    self.audioProcesses = audioProcesses
    self.powerAssertions = powerAssertions
    self.accessibility = accessibility
    self.accessibilityTrusted = accessibilityTrusted
    self.timestamp = timestamp
    self.maxAccessibilityNodesPerApplication = maxAccessibilityNodesPerApplication
  }

  public func sample() -> ProbeSnapshot {
    let runningApplications = applications()
    let audio = audioProcesses()
    let assertions = powerAssertions()
    let trusted = accessibilityTrusted()
    return ProbeSnapshot(
      timestamp: timestamp(),
      accessibilityTrusted: trusted,
      applications: runningApplications,
      audioCollectorStatus: audio.status,
      audioProcesses: audio.values,
      powerAssertionCollectorStatus: assertions.status,
      powerAssertions: assertions.values,
      accessibilityEvidence: accessibility(
        runningApplications,
        trusted,
        maxAccessibilityNodesPerApplication
      )
    )
  }
}

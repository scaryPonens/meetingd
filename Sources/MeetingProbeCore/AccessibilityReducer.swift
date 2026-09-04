import Foundation

public enum AccessibilityReducer {
  public static func ingest(
    _ node: AccessibilityNodeSignal,
    into evidence: inout AccessibilityEvidence
  ) {
    let role = node.role ?? ""
    let subrole = node.subrole ?? ""
    let title = normalize(node.title)
    let description = normalize(node.description)

    switch evidence.platform {
    case .googleMeet:
      if role == "AXRadioButton",
        subrole == "AXTabButton",
        isMeetLabel(description.isEmpty ? title : description)
      {
        evidence.meetTabCount += 1
      }
      if role == "AXWebArea", isMeetLabel(title) {
        evidence.meetWebAreaCount += 1
      }
      if role == "AXGroup",
        subrole == "AXLandmarkRegion",
        description == "call controls"
      {
        evidence.meetCallControls = true
      }
      if role == "AXButton", description == "leave call" {
        evidence.meetLeaveCallControl = true
      }
      if role == "AXButton", isPresentationControl(description) {
        evidence.meetPresentationControl = true
      }

    case .slackHuddle:
      if role == "AXWindow", title.hasPrefix("huddle:") {
        evidence.slackHuddleWindow = true
      }
      if role == "AXToolbar",
        description == "huddle window actions" || description == "huddles actions"
      {
        evidence.slackHuddleToolbar = true
      }
      if role == "AXButton", description == "leave huddle" {
        evidence.slackLeaveHuddleControl = true
      }
    }
  }

  static func normalize(_ value: String?) -> String {
    value?
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .lowercased() ?? ""
  }

  private static func isMeetLabel(_ value: String) -> Bool {
    value == "meet" || value.hasPrefix("meet -") || value.hasPrefix("meet:")
  }

  private static func isPresentationControl(_ value: String) -> Bool {
    value == "share screen"
      || value == "share your screen"
      || value == "present now"
      || value == "stop presenting"
      || value.hasSuffix(" is presenting")
  }
}

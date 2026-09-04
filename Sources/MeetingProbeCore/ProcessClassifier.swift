import Foundation

public enum ProcessClassifier {
  private static let browserBundlePrefixes = [
    "com.google.chrome",
    "com.microsoft.edgemac",
    "com.brave.browser",
    "org.chromium.chromium",
    "company.thebrowser.browser",
    "com.apple.safari",
  ]

  private static let supportedMainBundleIDs: Set<String> = [
    "com.google.chrome",
    "com.google.chrome.beta",
    "com.google.chrome.dev",
    "com.google.chrome.canary",
    "com.microsoft.edgemac",
    "com.microsoft.edgemac.beta",
    "com.microsoft.edgemac.dev",
    "com.microsoft.edgemac.canary",
    "com.brave.browser",
    "com.brave.browser.beta",
    "com.brave.browser.nightly",
    "org.chromium.chromium",
    "company.thebrowser.browser",
    "com.apple.safari",
    "com.apple.safaritechnologypreview",
    "com.tinyspeck.slackmacgap",
  ]

  private static let slackBundlePrefix = "com.tinyspeck.slackmacgap"

  private static let browserProcessNames = [
    "google chrome",
    "chromium",
    "microsoft edge",
    "brave browser",
    "arc",
    "safari",
  ]

  public static func platform(bundleID: String?, processName: String? = nil) -> MeetingPlatform? {
    if let bundleID {
      let normalized = bundleID.lowercased()
      if normalized == slackBundlePrefix || normalized.hasPrefix(slackBundlePrefix + ".") {
        return .slackHuddle
      }
      if browserBundlePrefixes.contains(where: {
        normalized == $0 || normalized.hasPrefix($0 + ".")
      }) {
        return .googleMeet
      }
    }

    guard let processName else { return nil }
    let normalizedName = processName.lowercased()
    if normalizedName == "slack" || normalizedName.hasPrefix("slack helper") {
      return .slackHuddle
    }
    if browserProcessNames.contains(where: {
      normalizedName == $0 || normalizedName.hasPrefix($0 + " helper")
    }) {
      return .googleMeet
    }
    return nil
  }

  public static func isSupportedMainApplication(bundleID: String) -> Bool {
    supportedMainBundleIDs.contains(bundleID.lowercased())
  }
}

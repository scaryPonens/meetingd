import AppKit
import Foundation
import MeetingProbeCore

private func writeStandardOutput(_ line: String) {
  FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

private func writeStandardError(_ line: String) {
  FileHandle.standardError.write(Data((line + "\n").utf8))
}

private func bootstrapAppKit(foreground: Bool) {
  let app = NSApplication.shared
  app.setActivationPolicy(foreground ? .regular : .accessory)
  if foreground {
    app.activate(ignoringOtherApps: true)
  }
}

private func accessibilitySettingsURL() -> URL? {
  URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
}

private func waitForAccessibilityGrant() {
  bootstrapAppKit(foreground: true)
  _ = SystemCollectors.accessibilityIsTrusted(prompt: true)
  if let url = accessibilitySettingsURL() {
    NSWorkspace.shared.open(url)
  }

  while !SystemCollectors.accessibilityIsTrusted(prompt: false) {
    let alert = NSAlert()
    alert.messageText = "Allow MeetingProbe in Accessibility"
    alert.informativeText = """
      System Settings → Privacy & Security → Accessibility should now be open.

      1. Click +
      2. Press Cmd+Shift+G and paste:
      \(Bundle.main.bundlePath)
      3. Enable MeetingProbe
      4. Click Recheck here

      Leave this dialog open until Recheck succeeds. Do not rebuild the app in between.
      """
    alert.addButton(withTitle: "Recheck")
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Continue without Accessibility")
    NSApp.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    if response == .alertSecondButtonReturn {
      if let url = accessibilitySettingsURL() {
        NSWorkspace.shared.open(url)
      }
      continue
    }
    if response == .alertThirdButtonReturn {
      return
    }
  }
}

private func run() throws {
  bootstrapAppKit(foreground: false)

  let options = try ProbeOptions.parse(Array(CommandLine.arguments.dropFirst()))
  if options.showHelp {
    writeStandardOutput(ProbeOptions.usage)
    return
  }

  if options.requestAccessibility {
    waitForAccessibilityGrant()
  }

  let sampler = ProbeSampler(
    maxAccessibilityNodesPerApplication: options.maxAccessibilityNodes
  )
  while true {
    let snapshot = sampler.sample()
    if options.json {
      writeStandardOutput(try ProbeFormatter.jsonLine(snapshot))
    } else {
      writeStandardOutput(ProbeFormatter.humanReadable(snapshot))
    }

    if options.runOnce { return }
    Thread.sleep(forTimeInterval: options.interval)
  }
}

do {
  try run()
} catch let error as ProbeOptionError {
  writeStandardError("meeting-probe: \(error)")
  writeStandardError(ProbeOptions.usage)
  exit(64)
} catch {
  writeStandardError("meeting-probe: \(error)")
  exit(1)
}

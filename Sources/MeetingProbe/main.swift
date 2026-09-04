import Foundation
import MeetingProbeCore

private func writeStandardOutput(_ line: String) {
  FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

private func writeStandardError(_ line: String) {
  FileHandle.standardError.write(Data((line + "\n").utf8))
}

private func run() throws {
  let options = try ProbeOptions.parse(Array(CommandLine.arguments.dropFirst()))
  if options.showHelp {
    writeStandardOutput(ProbeOptions.usage)
    return
  }

  if options.requestAccessibility {
    _ = SystemCollectors.accessibilityIsTrusted(prompt: true)
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

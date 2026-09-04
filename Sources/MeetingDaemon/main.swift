import Foundation
import MeetingProbeCore

private func writeStandardOutput(_ line: String) {
  FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

private func writeStandardError(_ line: String) {
  FileHandle.standardError.write(Data((line + "\n").utf8))
}

private func runCommand(_ options: DaemonOptions) throws {
  if options.requestAccessibility {
    _ = SystemCollectors.accessibilityIsTrusted(prompt: true)
  }

  let sampler = ProbeSampler(
    maxAccessibilityNodesPerApplication: options.maxAccessibilityNodes
  )
  var runtime = DaemonRuntime(
    configuration: LifecycleConfiguration(
      startConfirmations: options.startConfirmations,
      endConfirmations: options.endConfirmations
    ),
    statusURL: options.statusURL
  )

  while true {
    _ = try runtime.process(sampler.sample())
    Thread.sleep(forTimeInterval: options.interval)
  }
}

private func statusCommand(_ options: DaemonOptions) throws {
  do {
    let snapshot = try StatusStore.read(from: options.statusURL)
    writeStandardOutput(StatusFormatter.humanReadable(snapshot))
  } catch {
    throw DaemonRuntimeError.statusUnavailable(path: options.statusURL.path)
  }
}

private func debugCommand(_ options: DaemonOptions) throws {
  if options.requestAccessibility {
    _ = SystemCollectors.accessibilityIsTrusted(prompt: true)
  }

  let sampler = ProbeSampler(
    maxAccessibilityNodesPerApplication: options.maxAccessibilityNodes
  )
  let probe = sampler.sample()
  var runtime = DaemonRuntime(
    configuration: LifecycleConfiguration(
      startConfirmations: options.startConfirmations,
      endConfirmations: options.endConfirmations
    ),
    emitter: CollectingEventEmitter(),
    statusURL: options.statusURL,
    writeStatus: false
  )
  let status = try runtime.process(probe)
  let readings = ConfidenceEvaluator.evaluate(snapshot: probe)
  writeStandardOutput(
    StatusFormatter.debugReadable(
      snapshot: probe,
      readings: readings,
      statuses: status.platforms
    )
  )
}

private func run() throws {
  let options = try DaemonOptions.parse(Array(CommandLine.arguments.dropFirst()))
  if options.showHelp || options.command == .help {
    writeStandardOutput(DaemonOptions.usage)
    return
  }

  switch options.command {
  case .run:
    try runCommand(options)
  case .status:
    try statusCommand(options)
  case .debug:
    try debugCommand(options)
  case .help:
    writeStandardOutput(DaemonOptions.usage)
  }
}

do {
  try run()
} catch let error as DaemonOptionError {
  writeStandardError("meetingd: \(error)")
  writeStandardError(DaemonOptions.usage)
  exit(64)
} catch {
  writeStandardError("meetingd: \(error)")
  exit(1)
}

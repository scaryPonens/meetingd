import Foundation

public struct ProbeOptions: Equatable, Sendable {
  public var runOnce = false
  public var json = false
  public var requestAccessibility = false
  public var showHelp = false
  public var interval: TimeInterval = 3
  public var maxAccessibilityNodes = 3_000

  public init() {}

  public static func parse(_ arguments: [String]) throws -> ProbeOptions {
    var options = ProbeOptions()
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--once":
        options.runOnce = true
      case "--json":
        options.json = true
      case "--request-accessibility":
        options.requestAccessibility = true
      case "--help", "-h":
        options.showHelp = true
      case "--interval":
        index += 1
        guard index < arguments.count,
          let value = TimeInterval(arguments[index]),
          value >= 0.25
        else {
          throw ProbeOptionError.invalidValue(
            option: "--interval",
            requirement: "a number of seconds greater than or equal to 0.25"
          )
        }
        options.interval = value
      case "--max-ax-nodes":
        index += 1
        guard index < arguments.count,
          let value = Int(arguments[index]),
          value >= 100
        else {
          throw ProbeOptionError.invalidValue(
            option: "--max-ax-nodes",
            requirement: "an integer greater than or equal to 100"
          )
        }
        options.maxAccessibilityNodes = value
      default:
        throw ProbeOptionError.unknownOption(argument)
      }
      index += 1
    }
    return options
  }

  public static let usage = """
    Usage: meeting-probe [options]

    Continuously print local Google Meet and Slack Huddle evidence.

      --once                     Collect one snapshot and exit
      --json                     Emit one JSON object per snapshot
      --interval SECONDS         Poll interval (default: 3; minimum: 0.25)
      --max-ax-nodes COUNT       Accessibility scan cap per app (default: 3000)
      --request-accessibility    Ask macOS to open the Accessibility permission flow
      -h, --help                 Show this help
    """
}

public enum ProbeOptionError: Error, Equatable, CustomStringConvertible {
  case unknownOption(String)
  case invalidValue(option: String, requirement: String)

  public var description: String {
    switch self {
    case .unknownOption(let option):
      "unknown option: \(option)"
    case .invalidValue(let option, let requirement):
      "\(option) requires \(requirement)"
    }
  }
}

import Foundation

public enum DaemonCommand: String, Equatable, Sendable {
  case run
  case status
  case debug
  case help
}

public struct DaemonOptions: Equatable, Sendable {
  public var command: DaemonCommand = .help
  public var interval: TimeInterval = 1
  public var maxAccessibilityNodes = 3_000
  public var requestAccessibility = false
  public var startConfirmations = 2
  public var endConfirmations = 3
  public var statusPath: String?
  public var showHelp = false

  public init() {}

  public static func parse(_ arguments: [String]) throws -> DaemonOptions {
    var options = DaemonOptions()
    guard let first = arguments.first else {
      options.command = .help
      options.showHelp = true
      return options
    }

    switch first {
    case "run":
      options.command = .run
    case "status":
      options.command = .status
    case "debug":
      options.command = .debug
    case "help", "--help", "-h":
      options.command = .help
      options.showHelp = true
      return options
    default:
      throw DaemonOptionError.unknownCommand(first)
    }

    var index = 1
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--help", "-h":
        options.showHelp = true
        options.command = .help
      case "--request-accessibility":
        options.requestAccessibility = true
      case "--interval":
        index += 1
        guard index < arguments.count,
          let value = TimeInterval(arguments[index]),
          value >= 0.25
        else {
          throw DaemonOptionError.invalidValue(
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
          throw DaemonOptionError.invalidValue(
            option: "--max-ax-nodes",
            requirement: "an integer greater than or equal to 100"
          )
        }
        options.maxAccessibilityNodes = value
      case "--start-confirmations":
        index += 1
        guard index < arguments.count,
          let value = Int(arguments[index]),
          value >= 1
        else {
          throw DaemonOptionError.invalidValue(
            option: "--start-confirmations",
            requirement: "an integer greater than or equal to 1"
          )
        }
        options.startConfirmations = value
      case "--end-confirmations":
        index += 1
        guard index < arguments.count,
          let value = Int(arguments[index]),
          value >= 1
        else {
          throw DaemonOptionError.invalidValue(
            option: "--end-confirmations",
            requirement: "an integer greater than or equal to 1"
          )
        }
        options.endConfirmations = value
      case "--status-file":
        index += 1
        guard index < arguments.count else {
          throw DaemonOptionError.invalidValue(
            option: "--status-file",
            requirement: "a file path"
          )
        }
        options.statusPath = arguments[index]
      default:
        throw DaemonOptionError.unknownOption(argument)
      }
      index += 1
    }
    return options
  }

  public var statusURL: URL {
    if let statusPath {
      return URL(fileURLWithPath: statusPath)
    }
    return StatusStore.defaultStatusURL
  }

  public static let usage = """
    Usage: meetingd <command> [options]

    Commands:
      run       Continuously detect meetings and emit NDJSON events
      status    Print the latest daemon status snapshot
      debug     Print one probe snapshot with confidence and lifecycle state
      help      Show this help

    Options:
      --interval SECONDS            Poll interval for run (default: 1; minimum: 0.25)
      --max-ax-nodes COUNT          Accessibility scan cap per app (default: 3000)
      --start-confirmations COUNT   Consecutive participating polls to start (default: 2)
      --end-confirmations COUNT     Consecutive non-participating polls to end (default: 3)
      --status-file PATH            Status JSON path (default: ~/Library/Application Support/meetingd/status.json)
      --request-accessibility       Ask macOS to open the Accessibility permission flow
      -h, --help                    Show this help
    """
}

public enum DaemonOptionError: Error, Equatable, CustomStringConvertible {
  case unknownCommand(String)
  case unknownOption(String)
  case invalidValue(option: String, requirement: String)

  public var description: String {
    switch self {
    case .unknownCommand(let command):
      "unknown command: \(command)"
    case .unknownOption(let option):
      "unknown option: \(option)"
    case .invalidValue(let option, let requirement):
      "\(option) requires \(requirement)"
    }
  }
}

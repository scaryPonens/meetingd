// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "meetingd",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "meeting-probe", targets: ["MeetingProbe"]),
    .executable(name: "meetingd", targets: ["MeetingDaemon"]),
    .executable(name: "meeting-probe-tests", targets: ["MeetingProbeTests"]),
  ],
  targets: [
    .target(
      name: "MeetingProbeCore",
      linkerSettings: [
        .linkedFramework("ApplicationServices"),
        .linkedFramework("AppKit"),
        .linkedFramework("CoreAudio"),
        .linkedFramework("IOKit"),
        .linkedFramework("UserNotifications"),
      ]
    ),
    .executableTarget(
      name: "MeetingProbe",
      dependencies: ["MeetingProbeCore"],
      linkerSettings: [
        .linkedFramework("AppKit")
      ]
    ),
    .executableTarget(
      name: "MeetingDaemon",
      dependencies: ["MeetingProbeCore"]
    ),
    .executableTarget(
      name: "MeetingProbeTests",
      dependencies: ["MeetingProbeCore"],
      path: "Tests/MeetingProbeCoreTests"
    ),
  ]
)

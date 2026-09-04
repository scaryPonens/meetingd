# **Build a macOS Google Meet + Slack Huddle Detector**

Build a small, reliable, local-first macOS tool that detects when I enter and leave:

1. A Google Meet meeting
2. A Slack Huddle

The tool will eventually trigger local audio capture and transcription, but **do not implement recording or transcription yet**.

The goal of V1 is to solve meeting lifecycle detection reliably.

## **Primary behavior**

Run continuously in the background on macOS.

When I actually enter a Google Meet or Slack Huddle, emit a structured `meeting_started` event.

When I leave/end the meeting or huddle, emit a structured `meeting_ended` event.

Example:

```json
{
  "event": "meeting_started",
  "platform": "google_meet",
  "timestamp": "2026-09-03T09:00:12-03:00",
  "title": "Engineering Standup",
  "meeting_id": "abc-defg-hij"
}
```

and later:

```json
{
  "event": "meeting_ended",
  "platform": "google_meet",
  "timestamp": "2026-09-03T09:32:47-03:00",
  "meeting_id": "abc-defg-hij"
}
```

Slack should produce the same schema with:

```json
"platform": "slack_huddle"
```

## **Important distinction**

Do not merely detect that:

- Slack is running
- Chrome is running
- a `meet.google.com` tab exists
- a Slack channel containing a huddle exists

Detect that **I am actually participating in an active call** as reliably as macOS allows.

A Google Meet lobby/pre-join screen should ideally not trigger `meeting_started`.

An open Meet tab after leaving should not keep the meeting active.

Likewise, Slack merely being open or displaying huddle-related UI should not be considered sufficient evidence that I am currently participating.

## **Architecture**

Design this as a small daemon:

```text
meetingd
│
├── detectors/
│   ├── google_meet
│   └── slack_huddle
│
├── state/
│   └── meeting lifecycle state machine
│
├── events/
│   └── structured event emitter
│
└── cli/
```

Keep platform detection separate from lifecycle/state management.

I want to eventually plug this into:

```text
meetingd
   │
   ├── meeting_started
   │        ↓
   │   start audio capture
   │
   └── meeting_ended
            ↓
       stop capture
            ↓
       local Whisper
            ↓
       Obsidian
```

Do not couple V1 to any of those downstream systems.

## **Detection strategy**

Research the best mechanisms available on current macOS rather than immediately committing to one implementation.

Investigate, in order of preference:

1. Native macOS APIs/frameworks
2. Accessibility APIs
3. Application/window state
4. Browser tab/window information
5. Audio-session/activity information exposed by macOS
6. Process inspection
7. AppleScript / System Events
8. Other observable local signals

For Google Meet, consider Chrome, Chromium-based browsers, and Safari where practical.

For Slack, target the native Slack macOS desktop application first.

Multiple signals may need to be combined.

For example:

```text
Google Meet

meet.google.com tab exists
        +
browser indicates active call UI
        +
system/microphone/call activity
        ↓
high confidence meeting active
```

Do not assume this exact strategy is correct. Investigate what signals are actually available.

## **State machine**

Implement an explicit lifecycle state machine rather than emitting events directly from raw observations.

Something along the lines of:

```text
IDLE
 ↓
POSSIBLE_MEETING
 ↓
ACTIVE
 ↓
POSSIBLE_END
 ↓
IDLE
```

Use debounce/hysteresis where appropriate.

For example, a window disappearing for 500 ms should not necessarily terminate a meeting.

Likewise, detecting a Meet URL for one polling cycle should not necessarily start one.

Exactly one `meeting_started` and one `meeting_ended` event should normally be emitted per meeting.

## **Confidence**

Internally represent detection confidence/evidence.

For example:

```json
{
  "platform": "google_meet",
  "active": true,
  "confidence": 0.95,
  "signals": {
    "meeting_url": true,
    "in_call_ui": true,
    "audio_activity": true
  }
}
```

This does not have to be the public API, but I want observability into **why** the detector thinks a meeting is active.

Avoid opaque boolean logic scattered throughout the implementation.

## **CLI**

Provide a simple CLI.

Examples:

```bash
meetingd run
```

Runs continuously.

```bash
meetingd status
```

Example:

```text
Platform: Google Meet
State: ACTIVE
Meeting: Engineering Standup
Started: 09:00:12
Confidence: 0.96
```

And:

```bash
meetingd debug
```

should expose the raw detector signals so detection failures can be diagnosed.

Example:

```text
Google Meet
-----------
browser_running: true
meet_tab: true
meet_url: https://meet.google.com/abc-defg-hij
in_call_ui: true
microphone_active: true

Slack
-----
running: true
huddle_ui: false
audio_activity: false
```

Observability is important. I want to be able to determine exactly why a false positive or false negative occurred.

## **Event output**

Initially support newline-delimited JSON to stdout:

```json
{"event":"meeting_started","platform":"google_meet",...}
{"event":"meeting_ended","platform":"google_meet",...}
```

Design the event emitter behind an interface so later I can add:

- shell hooks
- Unix sockets
- HTTP callbacks
- file output

without changing the detectors.

## **Background execution**

The eventual deployment target is a macOS LaunchAgent.

Design accordingly:

```text
~/Library/LaunchAgents/...
        ↓
     meetingd
        ↓
runs automatically after login
```

Do not require a GUI application.

A CLI/background daemon is preferable.

## **Permissions**

Identify exactly which macOS permissions are required.

Potential examples include:

- Accessibility
- microphone information/access
- Screen & System Audio Recording
- Automation

Request the minimum permissions necessary.

Document why each permission is required.

Do not request microphone or screen-recording access merely because the future transcription system will need it. V1 should only request permissions necessary for detection.

## **Language**

Prefer Swift if native macOS APIs materially improve reliability.

Otherwise, consider Rust or another appropriate systems language.

Do not choose Python simply because it makes prototyping easy if doing so forces us into brittle shell/AppleScript integration that could be implemented robustly through native macOS APIs.

The resulting daemon should:

- have low CPU usage
- have negligible memory impact
- start quickly
- run indefinitely
- recover if Slack/browser processes restart
- handle sleep/wake
- handle network transitions
- not require a cloud service

## **Privacy**

Everything must operate locally.

Do not:

- send meeting information to external APIs
- use cloud services
- inspect meeting content
- record audio
- transcribe audio

The detector should determine only whether a meeting is active and collect basic metadata that is locally observable.

## **Tests**

Build the detector logic so observations can be injected into the state machine.

I want deterministic tests such as:

```text
Meet tab appears
→ no event

Meet lobby appears
→ no event

Join meeting
→ meeting_started

browser window loses focus
→ remain ACTIVE

switch to another application
→ remain ACTIVE

Meet tab remains open but call ends
→ meeting_ended
```

Slack:

```text
Slack starts
→ no event

Huddle invitation appears
→ no event

Join huddle
→ meeting_started

minimize Slack
→ remain ACTIVE

leave huddle
→ meeting_ended
```

Also test:

- rapid join/leave
- application crashes
- browser crashes
- computer sleep during meeting
- wake after meeting ended
- switching from one meeting to another
- duplicate detector observations
- temporary loss of a detection signal

## **Development process**

Before implementing the full daemon:

1. Research current macOS APIs and how Google Meet and Slack expose observable call state.
2. Inspect existing open-source implementations for meeting detection.
3. Document candidate signals for Google Meet and Slack.
4. Rank those signals by reliability and brittleness.
5. Create a small spike/probe that prints raw signals.
6. Have me manually test those signals while joining/leaving a Google Meet and Slack Huddle.
7. Only after validating the signals, implement the lifecycle state machine and daemon.

Do not prematurely build abstractions around an unverified detection mechanism.

The first milestone should therefore be something like:

```bash
meeting-probe
```

which continuously outputs observations:

```text
09:01:01 google_meet meet_tab=true in_call=false
09:01:05 google_meet meet_tab=true in_call=true
09:01:05 EVENT meeting_started
...
09:32:40 google_meet meet_tab=true in_call=false
09:32:42 EVENT meeting_ended
```

Once this reliably distinguishes actual participation from merely having Slack/Meet open, turn the probe into `meetingd`.

## **Deliverables**

Produce:

- source code
- README
- architecture/design notes
- documented macOS permissions
- `meeting-probe`
- `meetingd`
- automated tests
- LaunchAgent example
- installation instructions
- uninstall instructions
- troubleshooting/debugging instructions

Keep the project small.

The core objective is:

Reliably turn “I joined/left a Google Meet or Slack Huddle” into a local machine-readable event.

Everything else is secondary.
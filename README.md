# meetingd

Local-first macOS meeting lifecycle detection research and probe for Google Meet and Slack Huddles.

This repository is currently at the **signal-validation milestone**. It contains `meeting-probe`, which continuously reports locally observable evidence. It does not yet decide meeting lifecycle or emit `meeting_started`/`meeting_ended`; those rules would be premature until the signals are tested during real calls.

Recording, transcription, audio capture, screenshots, cloud services, and meeting-content inspection are intentionally absent.

## Requirements

- macOS 14.2 or newer for Core Audio process metadata
- Swift 6.2 or newer
- Native Slack for Huddle testing
- A supported Meet browser: Google Chrome, Chromium, Microsoft Edge, Brave, Arc, or Safari

## Build

```sh
swift build
```

## Install the probe

Build an optimized binary and copy it onto the user PATH:

```sh
swift build --configuration release
mkdir -p "$HOME/.local/bin"
install -m 755 .build/release/meeting-probe "$HOME/.local/bin/meeting-probe"
```

Grant Accessibility only after installing so macOS records the stable installed path. Rebuild and repeat the `install` command after source changes.

Uninstall the probe:

```sh
rm "$HOME/.local/bin/meeting-probe"
```

The probe creates no configuration, cache, LaunchAgent, or application-support files. Remove its Accessibility entry in System Settings if it was granted.

## Run the probe

One snapshot:

```sh
swift run meeting-probe --once
```

Continuous human-readable output, every three seconds by default:

```sh
swift run meeting-probe
```

Faster polling for a manual call test:

```sh
swift run meeting-probe --interval 1
```

Newline-delimited JSON:

```sh
swift run meeting-probe --json
```

Show every option:

```sh
swift run meeting-probe --help
```

The output deliberately describes evidence rather than a final `active` boolean. Example fields:

- `app_running`: a supported browser or Slack main app is running;
- `collectors`: distinguishes successful, unsupported, and failed Core Audio or power-assertion collection from an empty result;
- `audio_input` / `audio_output`: a classified Core Audio process has an active stream;
- `webrtc_peer_connection`: a classified process owns a power assertion containing `WebRTC` or `PeerConnection`;
- `ax_status`: whether semantic UI scanning succeeded, lacks permission, was truncated, or had no target app;
- `ax_joined_controls`: the exact joined-call control set was observed;
- platform-specific Accessibility fields explaining that result;
- indented `audio` and `assertion` records identifying the contributing local processes.

None of these fields alone is currently treated as meeting participation.

## Permissions

The low-permission signals work immediately. Accessibility is optional for running the probe and necessary to evaluate its strongest UI hypothesis:

```sh
swift run meeting-probe --request-accessibility --once
```

No Microphone, Screen Recording, Camera, or Automation permission is requested. See [Permissions and privacy](docs/permissions.md).

## Tests

Run the zero-dependency deterministic harness:

```sh
swift run meeting-probe-tests
```

It covers process classification, Meet lobby versus joined-control reduction, Slack Huddle control reduction, platform aggregation, injected collection providers, human/JSON output, and CLI option boundaries.

## Architecture

```text
meeting-probe executable
        |
        v
ProbeSampler                  injectable provider boundary
        |
        +-- NSWorkspace       supported app presence
        +-- Core Audio        per-process input/output state
        +-- IOKit             process power assertions
        +-- AXUIElement       reduced call-control evidence
        |
        v
ProbeSnapshot                 raw structured evidence
        |
        +-- human formatter
        +-- NDJSON formatter
```

Collection, evidence reduction, and formatting live in `MeetingProbeCore`. The executable owns only argument parsing, polling, and stdout/stderr. No lifecycle state machine or event emitter has been introduced.

## Research and validation

- [Signal research and ranking](docs/signal-research.md)
- [Manual Meet and Slack validation procedure](docs/manual-validation.md)
- [Permissions and privacy](docs/permissions.md)

Manual validation is mandatory before implementing `meetingd`. It must cover lobby/invitation false positives, muted and backgrounded participation, stale tabs/channels after leaving, app crashes, sleep/wake, transient signal loss, and call switching.

## Current boundary

Implemented:

- native, local signal collection;
- bounded semantic Accessibility scans;
- continuous human and NDJSON diagnostic output;
- injectable collectors and deterministic tests;
- permission/privacy and manual-validation documentation.

Deferred until validation evidence exists:

- confidence thresholds;
- debounce and hysteresis durations;
- lifecycle states;
- `meeting_started` and `meeting_ended` events;
- background daemon and LaunchAgent;
- installation/uninstallation of a daemon;
- all recording and transcription behavior.

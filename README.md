# meetingd

Local-first macOS meeting lifecycle detection for Google Meet and Slack Huddles.

`meeting-probe` reports raw evidence. `meetingd` turns validated signal combinations into `meeting_started` / `meeting_ended` NDJSON events with an explicit lifecycle state machine.

Recording, transcription, audio capture, screenshots, cloud services, and meeting-content inspection are intentionally absent.

## Requirements

- macOS 14.2 or newer for Core Audio process metadata
- Swift 6.2 or newer
- Native Slack for Huddle testing
- A supported Meet browser: Google Chrome, Chromium, Microsoft Edge, Brave, Arc, or Safari
- Accessibility permission for reliable joined-call UI detection

## Build

```sh
swift build
```

## Install

```sh
swift build --configuration release
mkdir -p "$HOME/.local/bin"
install -m 755 .build/release/meeting-probe "$HOME/.local/bin/meeting-probe"
install -m 755 .build/release/meetingd "$HOME/.local/bin/meetingd"
```

Grant Accessibility to the installed `meetingd` binary under **System Settings → Privacy & Security → Accessibility**. Rebuild and reinstall after source changes so macOS keeps a stable path.

Uninstall:

```sh
rm -f "$HOME/.local/bin/meeting-probe" "$HOME/.local/bin/meetingd"
rm -rf "$HOME/Library/Application Support/meetingd"
rm -f "$HOME/Library/LaunchAgents/com.meetingd.agent.plist"
# if loaded:
launchctl bootout "gui/$(id -u)/com.meetingd.agent" 2>/dev/null || true
```

Remove the Accessibility entries for the binaries if present.

## meeting-probe

One snapshot:

```sh
meeting-probe --once
```

Continuous evidence (default interval 3s):

```sh
meeting-probe --interval 1
```

NDJSON evidence:

```sh
meeting-probe --json
```

## meetingd

Run the daemon (NDJSON events on stdout; status file updated each poll):

```sh
meetingd run --interval 1
```

Example events:

```json
{"confidence":0.95,"event":"meeting_started","meeting_id":"…","platform":"google_meet","timestamp":"…"}
{"event":"meeting_ended","meeting_id":"…","platform":"google_meet","timestamp":"…"}
```

Inspect the latest evaluated state:

```sh
meetingd status
```

Inspect one raw probe plus confidence/signals:

```sh
meetingd debug --request-accessibility
```

### LaunchAgent

1. Copy [docs/launchagent/com.meetingd.agent.plist](docs/launchagent/com.meetingd.agent.plist).
2. Replace `REPLACE_ME` with your username and confirm the `meetingd` path.
3. Create the log directory: `mkdir -p "$HOME/Library/Logs/meetingd"`.
4. Install and load:

```sh
cp docs/launchagent/com.meetingd.agent.plist "$HOME/Library/LaunchAgents/com.meetingd.agent.plist"
# edit paths, then:
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.meetingd.agent.plist"
```

Unload:

```sh
launchctl bootout "gui/$(id -u)/com.meetingd.agent"
```

## Permissions

| Permission | Required? | Why |
|---|---:|---|
| Accessibility | Strongly recommended | Joined-call control labels are the primary participation signal |
| Microphone | No | Core Audio process metadata only |
| Screen Recording | No | No pixels or titles from capture APIs |
| Automation | No | Browser tab URLs deferred |

See [docs/permissions.md](docs/permissions.md).

## Tests

```sh
swift run meeting-probe-tests
```

Covers classification, AX reduction, confidence policy, lifecycle hysteresis, daemon runtime events, and CLI parsing.

## Architecture

```text
meeting-probe / meetingd
        |
        v
ProbeSampler                  injectable collectors
        |
        v
ProbeSnapshot                 raw evidence
        |
        v
ConfidenceEvaluator           participating + confidence + signals
        |
        v
LifecycleStateMachine         IDLE → POSSIBLE_MEETING → ACTIVE → POSSIBLE_END
        |
        +-- EventEmitter      NDJSON stdout (extensible)
        +-- StatusStore       ~/Library/Application Support/meetingd/status.json
```

Default hysteresis: 2 consecutive participating polls to start, 3 to end (at a 1s `meetingd run` interval). Policy details live in [docs/validation-results.md](docs/validation-results.md).

## Docs

- [Signal research](docs/signal-research.md)
- [Manual validation procedure](docs/manual-validation.md)
- [Validation results / detector policy](docs/validation-results.md)
- [Permissions](docs/permissions.md)
- [Original product brief](docs/prompt.md)

## Troubleshooting

- `meetingd status` fails: run `meetingd run` at least once, or pass `--status-file`.
- AX fields stay `permission_denied`: grant Accessibility to the installed binary and restart it.
- False starts without Accessibility: fallback requires WebRTC **and** audio; prefer granting Accessibility.
- No events while in a call: run `meetingd debug` and check `ax_joined_controls`, `webrtc_peer_connection`, and audio flags.

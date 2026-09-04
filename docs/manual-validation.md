# Manual signal validation

This is the required gate between `meeting-probe` and lifecycle-detector work. Run it with the actual browser and Slack versions used on this Mac. Do not infer success from unit tests.

## Prepare

Build and start a one-second probe:

```sh
swift build
swift run meeting-probe --request-accessibility --interval 1
```

If `permissions accessibility=false` remains after granting access, stop the process, verify its entry under **System Settings → Privacy & Security → Accessibility**, and restart it.

For a machine-readable capture suitable for comparing transitions:

```sh
swift run meeting-probe --json --interval 1
```

Redirecting output persists process metadata and assertion names. Store such logs locally and delete them after analysis.

## Record observations

For every step, record which fields change, how many polling cycles the change takes, and whether any field briefly disappears. The fields are evidence, not final meeting state.

### Google Meet

Use the browser normally used for Meet, then repeat in other supported browsers that matter.

| Step | Required distinction | Candidate expected evidence |
|---|---|---|
| Browser closed | Absence baseline | `app_running=false`; no browser audio/assertion details |
| Browser open on unrelated page | Not a meeting | app presence may be true; joined controls must remain false |
| Meet lobby/pre-join screen | Must not count as joined | `meet_tabs`/`meet_web_areas` may appear; complete `ax_joined_controls` should remain false |
| Join a meeting | Joined transition | complete Accessibility controls should appear; WebRTC and audio evidence may appear |
| Mute microphone | Must remain joined | determine whether Core Audio input remains active; Accessibility should remain joined |
| Mute incoming audio if practical | Must remain joined | determine whether output remains active |
| Switch application | Must remain joined | signals should persist |
| Minimize browser | Must remain joined | measure Accessibility visibility and any transient loss |
| Change macOS Space | Must remain joined | measure Accessibility visibility and any transient loss |
| Leave but keep Meet tab open | Must end | joined controls and WebRTC assertion should disappear even if Meet tab context remains |
| Close browser during meeting | Must end | app and associated process evidence should disappear |

Also note whether Google Meet's presentation control label differs from `Present now`, `Share screen`, `Share your screen`, `Stop presenting`, or `<name> is presenting`.

### Slack Huddle

| Step | Required distinction | Candidate expected evidence |
|---|---|---|
| Slack closed | Absence baseline | `app_running=false`; no Slack audio/assertion details |
| Slack open normally | Not a Huddle | app presence may be true; complete Huddle controls must remain false |
| Huddle invitation visible | Must not count as joined | invite UI must not produce toolbar + leave-control evidence |
| Join a Huddle | Joined transition | `huddle_toolbar`, `leave_huddle`, and `ax_joined_controls` should become true; audio/WebRTC may appear |
| Mute microphone | Must remain joined | determine whether input activity persists |
| Switch application | Must remain joined | evidence should persist |
| Minimize Slack | Must remain joined | measure Accessibility visibility and transient loss |
| Change macOS Space | Must remain joined | measure Accessibility visibility and transient loss |
| Leave Huddle but keep channel open | Must end | toolbar/leave control and media evidence should disappear |
| Quit or crash Slack during Huddle | Must end | app and associated process evidence should disappear |

## Timing and resilience runs

Measure these separately:

- rapid join then leave;
- temporary signal loss over one or more polls;
- browser/Slack restart;
- sleep during a call and wake after it ended;
- switch directly between two Meet meetings;
- switch between Meet and a Slack Huddle;
- duplicate identical observations over at least one minute.

## Acceptance gate

The probe is validated only when the observations show a repeatable distinction between:

1. app/tab/lobby/invitation present but not participating;
2. actually participating, including muted and backgrounded states;
3. participation ended while the app or tab remains open.

Capture the tested app versions, macOS version, observed transition timing, selector labels, and counterexamples. Those results determine the future detector's signal combination, confidence model, start/end debounce, and sleep/wake policy. Do not implement the lifecycle state machine before this evidence exists.

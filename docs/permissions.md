# Permissions and privacy

## Current probe

| Permission | Required? | Reason |
|---|---:|---|
| Accessibility | Optional but needed for the strongest UI evidence | Reads semantic roles and exact call-control labels from supported browser and Slack processes |
| Microphone | No | The probe reads Core Audio process-state metadata; it never opens an input device or receives samples |
| Screen & System Audio Recording | No | The probe does not enumerate capture content, take screenshots, inspect pixels, or create an audio process tap |
| Automation / Apple Events | No | Browser scripting is intentionally deferred |
| Camera | No | The camera is neither opened nor queried |

Without Accessibility permission, `meeting-probe` still reports application presence, Core Audio process activity, and power assertions. Accessibility fields report `ax_status=permission_denied`; they are not silently treated as negative evidence.

To start the macOS Accessibility permission flow:

```sh
swift run meeting-probe --request-accessibility --once
```

macOS returns the current authorization immediately and opens the relevant System Settings flow asynchronously when access is missing. After enabling the executable under **System Settings → Privacy & Security → Accessibility**, restart the probe. Development builds can move as Swift rebuilds them; if macOS retains a stale entry, remove it, run the command again, and enable the newly presented executable.

## Data handling

All collection and output are local:

- no network client or cloud dependency exists in the package;
- no audio stream is opened and no audio samples are read;
- no pixels, screenshots, or meeting content are captured;
- arbitrary Accessibility text is not emitted or retained;
- Accessibility nodes are reduced in memory to counts and booleans for exact roles/control labels;
- the output includes app/process identifiers, Core Audio activity flags, and relevant power-assertion names;
- nothing is persisted unless the operator redirects stdout to a file.

Meeting titles, participant names, chat, captions, and tab URLs are deliberately absent from this milestone.

## Why Accessibility is justified

An open Meet tab, a running Slack process, browser audio, or a WebRTC connection does not prove participation. Joined-call controls are materially stronger:

- Google Meet: a Meet web area plus the call-controls region, leave-call button, and presentation control;
- Slack: a Huddle toolbar plus the leave-huddle button.

The scan is capped per process (`--max-ax-nodes`, default `3000`) to bound work. Only exact English control labels are recognized. Manual testing must determine whether these selectors survive backgrounding, minimizing, Spaces, and current application versions before Accessibility becomes a required permission for `meetingd`.

## Future permission rule

The future daemon must request only permissions proven necessary by manual validation. Recording and transcription remain out of scope. Do not add Microphone or Screen Recording permission preemptively for future features.

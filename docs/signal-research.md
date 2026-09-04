# Meeting detection signal research

Research date: 2026-09-03. Target: current macOS, native Slack, and Google Meet in Chrome-family browsers or Safari.

## Decision

The probe measures four local signals without deciding meeting lifecycle:

1. supported application presence through `NSWorkspace`;
2. per-process Core Audio input/output activity;
3. process-owned IOKit power assertions, especially Chromium's active WebRTC peer-connection assertion;
4. narrowly reduced Accessibility evidence for Meet call controls and Slack Huddle controls.

The first three work without a privacy permission prompt. Accessibility is the only optional permission used by the probe. The probe does not request Microphone, Screen & System Audio Recording, or Automation access, and it does not capture pixels, audio, or meeting content.

No single signal is authoritative before manual testing. The future detector should require validated combinations and apply hysteresis in a separate lifecycle state machine.

## Ranked candidates

| Rank | Signal | Participation reliability | False-positive risk | Permission cost | Probe decision |
|---:|---|---|---|---|---|
| 1 | Exact Accessibility controls: Meet `call controls` + `leave call` + presentation control; Slack Huddle toolbar + `leave huddle` | High candidate: controls exist inside joined-call UI rather than lobby/channel UI | UI labels, roles, localization, and product updates can drift; background/hidden windows must be tested | Accessibility | Measure |
| 2 | `kAudioProcessPropertyIsRunningInput` and `...IsRunningOutput` for browser/Slack Core Audio process objects | Medium-high supporting evidence of live media I/O | Browser media, Slack clips/voice messages, muted calls, helper attribution, and idle audio engines can differ | None observed; metadata only, no stream opened | Measure |
| 3 | `IOPMCopyAssertionsByProcess`, particularly an assertion containing `WebRTC` or `PeerConnection` | Medium-high supporting evidence for active Chromium/Electron real-time media | Any WebRTC session can match; process attribution and assertion text are undocumented behavior | None | Measure |
| 4 | Supported app presence via `NSWorkspace.runningApplications` | Low; useful only to establish absence or identify PIDs for other probes | An open app is not a call | None | Measure |
| 5 | Browser tab URLs through each browser's Apple-event dictionary | Medium context signal; reliably identifies a Meet URL | Lobby and post-call tabs remain open, and each browser needs separate scripting support | Automation per browser; hardened apps also need an entitlement and usage string | Defer |
| 6 | Window names from Core Graphics or ScreenCaptureKit | Low-medium context signal | Titles are optional, privacy-filtered, and do not prove participation | Screen Recording may be required for other apps' names | Reject for initial probe |
| 7 | Generic Accessibility text/tree scraping | Medium, but potentially adaptable | Large trees, UI churn, localization, and accidental inspection of unrelated meeting/channel text | Accessibility | Restrict to exact roles and control labels |
| 8 | Screen pixels/OCR or audio capture | Potentially high after content analysis | Intrusive, expensive, and contrary to the V1 privacy boundary | Screen Recording and/or Microphone | Reject |

## Native API evidence

### Core Audio process state

The current SDK's `AudioHardware.h` defines:

- `kAudioHardwarePropertyProcessObjectList`: Core Audio process objects for clients connected to the HAL;
- `kAudioProcessPropertyPID` and `kAudioProcessPropertyBundleID`;
- `kAudioProcessPropertyIsRunningInput`: the process is running I/O with at least one active input stream;
- `kAudioProcessPropertyIsRunningOutput`: the corresponding output-stream state.

The API reports activity metadata. Reading it does not open an audio device or receive samples. It cannot, by itself, distinguish a call from other browser or Slack audio behavior.

Apple references:

- [Core Audio process object list](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertyprocessobjectlist)
- [`kAudioProcessPropertyIsRunningInput`](https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertyisrunninginput)
- [`AudioHardwareProcess`](https://developer.apple.com/documentation/coreaudio/audiohardwareprocess)

### IOKit power assertions

`IOPMCopyAssertionsByProcess` returns active power assertions grouped by PID. Chromium currently uses an assertion named like `WebRTC has active PeerConnections` while a peer connection is active. This is useful evidence but not a supported meeting API; its spelling and lifecycle must be validated and treated as fallible.

### Accessibility

`AXIsProcessTrusted` exposes current Accessibility authorization. `AXUIElement` can inspect another app's semantic UI tree after authorization. The probe reads roles, subroles, titles, descriptions, and children, then immediately reduces them to boolean/count evidence. It neither stores nor emits arbitrary UI text.

Apple reference: [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)

### Browser Apple events

Chromium's scripting dictionary exposes browser windows, tabs, and tab URLs. This is a strong `meet.google.com` context signal but not participation evidence. It also adds per-browser Automation approval and future packaging requirements, so it is intentionally absent from the initial probe.

Sources:

- [Chromium scripting dictionary](https://chromium.googlesource.com/chromium/src.git/+/lkgr/chrome/browser/ui/cocoa/applescript/scripting.sdef)
- [Apple `NSAppleEventsUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)

### Window and capture APIs

`CGWindowListCopyWindowInfo` and ScreenCaptureKit can enumerate windows, but useful names may be unavailable without Screen Recording access. ScreenCaptureKit is designed around capture-capable content. V1 does not need pixels and should not request this permission just to obtain a weak title signal.

Sources:

- [`CGWindowListCopyWindowInfo`](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:))
- [`SCShareableContent`](https://developer.apple.com/documentation/screencapturekit/scshareablecontent)
- [`CGPreflightScreenCaptureAccess`](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess())

## Comparable implementations

### Meeting Pulse

[`mknmohit/meeting-pulse`](https://github.com/mknmohit/meeting-pulse) is a Swift macOS detector for this exact Meet/Slack pair. Its current implementation uses Accessibility and avoids Screen Recording. Relevant source:

- [Meet and Slack source detectors](https://github.com/mknmohit/meeting-pulse/blob/main/mac-app/Packages/MPDetection/Sources/MPDetection/SourceDetectors.swift)
- [Exact Accessibility selectors](https://github.com/mknmohit/meeting-pulse/blob/main/mac-app/Packages/MPDetection/Sources/MPDetection/AXSelectors.swift)

Its selectors require joined-call controls rather than merely a Meet tab or Slack Huddle window. It also latches identified windows across transient visibility loss. Those are useful precedents, but this project must validate the selectors on this Mac before adopting lifecycle behavior.

### Meeting Transcriber

[`pasrom/meeting-transcriber`](https://github.com/pasrom/meeting-transcriber) independently demonstrates both metadata-only signal families:

- [`MicInputDetector.swift`](https://github.com/pasrom/meeting-transcriber/blob/main/app/MeetingTranscriber/Sources/MicInputDetector.swift) enumerates Core Audio process objects and reads input activity;
- [`PowerAssertionDetector.swift`](https://github.com/pasrom/meeting-transcriber/blob/main/app/MeetingTranscriber/Sources/PowerAssertionDetector.swift) reads process power assertions and recognizes Chromium's WebRTC peer-connection assertion.

Its own comments document the critical limitations: microphone use can be a voice message, and a WebRTC assertion identifies a real-time connection rather than a particular meeting provider.

## Hypotheses to validate

Google Meet participation should produce a stronger pattern than an open lobby or stale tab:

- joined-call Accessibility controls are all present;
- a browser-owned WebRTC peer-connection assertion is present;
- browser audio input and/or output is active.

Slack Huddle participation should produce:

- Slack Huddle toolbar and leave-control Accessibility evidence;
- Slack or Slack-helper input/output activity;
- possibly a Slack-owned WebRTC peer-connection assertion.

Manual runs must establish which signals survive muting, minimizing, changing Spaces, switching apps, sleep/wake, and leaving while the Meet tab or Slack channel remains open. Until then these are hypotheses, not detector rules.

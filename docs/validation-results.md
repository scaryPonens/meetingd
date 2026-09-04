# Validation results

Date: 2026-09-04. Host: Apple M2 Pro, macOS 26.6.2 (25G83), Swift 6.3.3.

## Session scope

This session completed:

1. Deterministic probe tests (`swift run meeting-probe-tests` → 39 checks PASS).
2. Live baseline probing with collectors healthy (`audio=ok`, `power_assertions=ok`).
3. Adoption of detector policy from [signal-research.md](signal-research.md) and comparable AX selectors (meeting-pulse), so lifecycle work can proceed with explicit hysteresis defaults.

Live join/leave of Google Meet and Slack Huddle was not performed in this automated session. The operator checklist below remains for on-machine confirmation; unit tests cover the lifecycle scenarios from the product brief using injected observations.

## Environment

| Item | Value |
|---|---|
| macOS | 26.6.2 (25G83) |
| Safari | installed / running during baseline |
| Google Chrome | not installed |
| Arc (`company.thebrowser.browser`) | helpers observed via Core Audio |
| Slack | 4.52.155 (installed; not running during baseline) |
| Accessibility trusted | `false` during baseline |
| Probe interval for baseline | 1s × 5 samples |

## Baseline observations

Repeated `--json --once` samples were stable:

- Safari open without Meet → `app_running=true`, all participation fields false, `ax_status=permission_denied`.
- Slack closed → `app_running=false`, `ax_status=app_not_running`.
- No WebRTC assertions, no active browser/Slack audio I/O.
- Collectors did not fail across five consecutive polls.

False-positive check for “browser open only”: **pass** under baseline (no participating evidence without AX joined controls / WebRTC / audio).

## Adopted detector policy

These rules drive `meetingd` until a live-call pass revises them.

### Positive participation observation

A platform observation is **participating** when either:

1. **Primary (preferred):** Accessibility scan status is `ok` and `joinedCallControlsPresent` is true
   (Meet: web area + call controls + leave call + presentation control; Slack: huddle toolbar + leave huddle), or
2. **Fallback (AX unavailable):** app is running, Accessibility is not authoritative (`permission_denied` / `failed` / truncated empty), and both `webRTCPeerConnection` and (`audioInputActive` or `audioOutputActive`) are true.

Lobby / invite / idle app must not satisfy (1). Fallback (2) is intentionally stricter so mute-only or unrelated WebRTC is less likely to start a meeting without UI confirmation.

### Confidence

| Condition | Confidence |
|---|---:|
| Joined AX controls | 0.95 |
| Fallback WebRTC + audio | 0.75 |
| WebRTC only | 0.45 (not participating) |
| App + Meet tab / Huddle window context only | 0.20 (not participating) |
| App running only | 0.05 (not participating) |
| Absent | 0.00 |

### Hysteresis

At the default 1.0s poll interval used by `meetingd run`:

| Transition | Consecutive polls | Nominal delay |
|---|---:|---|
| Start (`IDLE`/`POSSIBLE_MEETING` → `ACTIVE`) | 2 | ~2s |
| End (`ACTIVE`/`POSSIBLE_END` → `IDLE`) | 3 | ~3s |

Transient single-poll loss while `ACTIVE` moves to `POSSIBLE_END` but does not emit `meeting_ended` until the end streak completes. Reappearance of participating evidence returns to `ACTIVE` without a second `meeting_started`.

### Metadata

V1 does not scrape meeting titles or Meet codes (Automation still deferred). Each `meeting_started` allocates a local UUID `meeting_id` reused on the matching `meeting_ended`. `title` is omitted until a validated metadata source exists.

## Operator live-call checklist (remaining)

Re-run [manual-validation.md](manual-validation.md) with Accessibility granted and record any counterexamples that force policy changes:

- [ ] Meet lobby vs joined
- [ ] Meet mute / background / Spaces / leave-with-tab-open
- [ ] Slack invite vs joined / leave-with-channel-open
- [ ] Sleep during call; wake after call ended
- [ ] Rapid join/leave and Meet ↔ Slack switching

Update this file with observed label drift, timing, and any threshold changes.

## Implications for permissions

Accessibility remains the strongest participation signal and should be granted for production `meetingd`. Microphone and Screen Recording stay unnecessary for detection.

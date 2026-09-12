# First departure holder — pending native verification

Base: `lc/native-stabilization-v2`, `e37f4d32ffae80290a1252e84c367283591a8f6b`
(`stabilize bounded local live activity lifecycle`). Verification commit/push to this branch was explicitly authorized by the user.

## Scope

Fix only the physically observed empty Lock Screen after Stop on the first event.
No changes to NativeAlarmContract, leaveAt calculation, provisioning, reconciliation
history, build identity, production schedule, main, or native-design-v1.

- A visible amber Commander holder is requested only in the foreground, before leaveAt,
  only for the nearest event without a canonical predecessor, and only after its event
  activity is prepared. Its identity includes schedule version, full target alarm and icon.
- AlarmKit alert-only requires actual unique active/stale holder read-back plus the
  canonical scheduled event activity. Otherwise the existing AlarmKit countdown is used.
- Stop selects the existing holder, ends it with the established red final presentation
  and `.after(startAt)`. No new Activity.request is reachable from Stop.
- The already scheduled event activity starts at startAt. Duplicate, invalid, obsolete
  and unsupported amber holders are removed; an ended red holder is retained to startAt.
- The existing predecessor/free-time handoff remains a separate, unchanged selection path.
- Physical preflight now also requires the first holder before READY.

## Regression coverage added, not yet executed

DepartureHolderTests: foreground/running prerequisites; unique active canonical read-back;
missing/rejected/pending/duplicate fallback; Stop selection and red retention through the
start boundary; all identity fields; duplicate/invalid/obsolete cleanup; unchanged second
handoff; presentation-context changes; supplementary UI/Stop wiring guard.
PhysicalAcceptanceTests: first alert-only read-back with holder proof, missing proof,
duplicate countdown, and missing prepared running activity.

## Actual validation in this workspace

- Public schedule suite: 38 passed.
- Brand assets: 10 passed.
- Calendar sync: 26 passed.
- Keyless authentication: 5 passed.
- Refresh launcher: 18 passed.
- git diff --check: passed.
- Swift test attempted: blocked, `swift: command not found`.
- iPhone/Physical Acceptance/Watch builds: not run (Linux, no Xcode).
- Connected Mac was offline. No new GitHub Actions runs; do not reuse earlier green
  results as evidence for this patch. No physical verification of the patch.

## Next step

Obtain macOS verification. The user has authorized a verification commit/push to this branch. Inspect Native stability (Swift, iPhone plus extensions, Physical Acceptance, Watch)
and Public schedule on that exact commit, fix only failures caused by this patch.
Do not change protected branches or claim all green before these gates complete.

## Short physical test, after native gates pass

Launch a fresh Physical Acceptance run in the foreground; wait for READY. Confirm one
amber Odchod za card, lock the iPhone and leave the app closed. At the first alarm
(about minute 4), press Stop on the Lock Screen: the same Commander card must immediately
show red VYRAZIT TEĎ and stay red until the first meal (about minute 6), when Právě jídlo
must appear without opening the app. Stop evaluating at that point; the previously
verified free-time, second alarm, Watch and Magnetoterapie sequence is not repeated.

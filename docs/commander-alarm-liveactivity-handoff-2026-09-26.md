# Commander — AlarmKit / Live Activity / Dynamic Island handoff

Date: 2026-09-26
Branch: `lc/alarm-liveactivity-unification-v1`
Base before this block: `35ad9a4 Finalize Commander dashboard live-state UX`

## What is physically proven already

Historical acceptance evidence and the 2026-09-26 run prove these separately:

- AlarmKit real alarms fire on the physical iPhone.
- AlarmKit sound has reached iPhone / Watch in earlier physical runs.
- AlarmKit countdown / alert system presentation has been physically observed.
- A Commander procedure Live Activity can render on the iPhone Lock Screen.
- A Commander procedure Live Activity can replicate to Apple Watch Smart Stack/detail.
- The short visual probe also proved Dynamic Island rendering when a Commander Activity actually exists.
- `Právě probíhá / Do konce` has been physically exercised in older runs.

The unresolved point was not rendering. It was **creation timing**.

## Rejected architecture: create Commander from Stop

The former contract made `CommanderAlarmStopIntent` the only creator of the first Commander Live Activity.

That route is now rejected. Multiple physical runs produced the same ActivityKit visibility failure while the intent executed in the background:

`The operation couldn’t be completed. Target is not foreground`

Retiring the AlarmKit activity first did not remove the system restriction reliably. Repeating the same Stop-create experiment therefore does not add useful evidence.

## Current architecture

### AlarmKit remains the safety layer

- canonical `leaveAt` is still the alarm deadline,
- AlarmKit owns departure countdown and the real audible alert,
- existing reconciliation/read-back/repair logic remains independent from ActivityKit success.

### One Commander Live Activity, prepared before Stop

`CommanderProcedureLiveActivityCoordinator` is now the only production creator of `CommanderProcedureLiveActivityAttributes`.

- creation happens only from normal foreground/bootstrap reconciliation,
- if the first still-relevant mandatory procedure is in the future, ActivityKit receives a scheduled start at that procedure's canonical `leaveAt`,
- scheduled start uses bundled `CommanderSilentAlert.wav` so ActivityKit does not add a second audible alert next to AlarmKit,
- if `leaveAt` has already passed while the app is legitimately foregrounded, the same coordinator may request the activity immediately,
- maximum concurrent Commander activities remains one,
- a pending scheduled activity is replaced if its anchor, schedule version, projection revision, or canonical `leaveAt` changes before activation,
- old duplicates are ended,
- Stop never calls `Activity.request`.

### Planning rules are now pure and testable

`CommanderLiveActivityPlan` lives in `LazenskyCommanderCore` and chooses:

- the first remaining `procedure` as the mandatory anchor,
- activation at the anchor's effective canonical `leaveAt`, including local lead-time overrides,
- at most six queued events,
- only events that fit inside a 7 h 50 min activity window.

This deliberately leaves optional meal-only periods to AlarmKit if no mandatory procedure is available. It also avoids pretending one ActivityKit instance can cover a 10+ hour spa day.

## System-surface story

Before the Commander scheduled start, AlarmKit may show the departure countdown.

At the anchor `leaveAt`:

- AlarmKit owns the real alarm / `Čas vyrazit`,
- the already scheduled Commander Activity becomes active system-side,
- after Stop there is no background create attempt to fail.

Commander then renders one queue as:

`Následuje → Právě probíhá → Potom / Současně → Skončilo`

The same ActivityKit instance is the source for Lock Screen, Dynamic Island and system replication to Apple Watch.

## Automated gate before another physical test

Do not ask Petr to repeat the old 15-minute Stop-create sequence.

Before one final targeted physical proof, require:

1. all Swift tests,
2. production iOS build,
3. Physical Acceptance build,
4. Watch build,
5. `git diff --check`,
6. static regression guard: Stop intent contains no `Activity.request`,
7. scheduled-create path exists only in the serialized coordinator,
8. bundled silent alert exists in both production and Physical Acceptance app bundles,
9. simulator scheduled-start probe transitions a Commander activity from pending to active.

Only after these pass is one physical scheduled-start proof justified.

## Current test baseline

The core suite now includes `CommanderLiveActivityPlanTests` covering:

- first mandatory procedure anchoring,
- 7 h 50 min lifetime window,
- exclusion of early/late optional meals outside the window,
- fallback to the next procedure after an earlier one ends,
- no meal-only Commander activity,
- override-adjusted canonical `leaveAt`.

Physical Acceptance READY now requires a real Commander activity to be present as pending/active before the timed run proceeds.

### Validation completed without another physical alarm run

- Swift core suite: **222 tests in 3 suites passed**.
- Production iOS generic build: **BUILD SUCCEEDED**.
- Physical Acceptance generic iOS build: **BUILD SUCCEEDED**.
- Watch generic build: **BUILD SUCCEEDED**.
- The bundled silent alert is a 0.1 s PCM WAV whose 4,410 samples are all zero.
- On the booted iPhone 16 simulator, the dedicated scheduled probe transitioned from `.pending` to `.active` without a Stop intent or foreground `Activity.request` at activation time. The diagnostic timeline recorded pending from 16:38:40 through 16:38:51 and active at 16:38:52 for an Activity scheduled at 16:38:48. Simulator timing is not a physical-device PASS, but it proves the new scheduled-start code path executes as designed.

No further full two-alarm physical run should be requested until this architecture is committed and the final targeted physical proof is ready.

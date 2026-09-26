# Commander — AlarmKit / Live Activity / Dynamic Island handoff

Date: 2026-09-26
Branch: `lc/alarm-liveactivity-unification-v1`
Base: `35ad9a4 Finalize Commander dashboard live-state UX`

## Verified baseline before this block

- Dashboard / Today / Week / Settings work is checkpointed at `/Users/petrbohanes/commander-design-checkpoints/2026-09-26-dashboard-week-settings-final`.
- Base commit `35ad9a4` is pushed to `origin/lc/schedule-acceptance-audit-v1`.
- Core suite passed with 218 tests after the final live `Volno do večeře` update.
- Physical iPhone build succeeded and installed.
- Current physical destinations visible to Xcode/devicectl:
  - `Petr -iPhone 16` (`00008140-0019586A3607001C`)
  - `Petr – Apple Watch` (`00008310-001C09693CE0E01E`)
- `NSSupportsLiveActivities` is enabled for the iPhone app and Live Activity extension.
- `NSAlarmKitUsageDescription` is present.

## Current ownership model — preserve unless intentionally redesigned

### AlarmKit owns departure

`AlarmKitAdapter` schedules the real system alarm at canonical `leaveAt`.

- AlarmKit countdown window is capped at 30 minutes.
- If the previous same-day event ends closer than 30 minutes before departure, the countdown window shrinks to that gap.
- The actual alert deadline always remains canonical `leaveAt`.
- AlarmKit presentation carries Commander metadata, including event identity, start/end/leave times, icon and the next event snapshot.

### Stop intent hands off to Commander

`CommanderAlarmStopIntent` is the only production creator of `CommanderProcedureLiveActivityAttributes`.

- It first retires the stopped AlarmKit Activity.
- It then updates the existing Commander Live Activity or creates exactly one Commander activity.
- Events are merged into one ordered queue.
- Duplicates are ended.
- This ordering is deliberate because requesting a second Activity while AlarmKit still owns the active surface can fail with ActivityKit visibility restrictions.

### Foreground coordinator only reconciles

`CommanderProcedureLiveActivityCoordinator` updates an already existing Commander Live Activity and removes duplicates, but deliberately does not create one.

This is protected by regression tests and is an important stability invariant.

## Current system-surface story

### Before departure

AlarmKit Live Activity:

- countdown mode: `Odchod za` + timer
- alert mode: `Vyrazit teď`
- Dynamic Island compact/minimal shows Commander brand + countdown
- expanded Island shows status plus event title/location
- Lock Screen shows large departure countdown / alert state

### After Stop handoff

Commander procedure Live Activity:

- before event starts: `Začíná za`
- during event: `Právě probíhá` (meal variant: `Právě jídlo`)
- after event: `Procedura skončila` / `Jídlo skončilo`
- active timing uses `Do konce`
- one activity can carry a short queue of following events and uses `Další:` / `Současně:`

## UX gap to solve in this block

The functional flow is stable, but wording and visual hierarchy are split across app and system surfaces.

The app now uses a clear story around:

`Následuje → Odchod → Právě probíhá → Do konce`

The system surfaces still use a mix of:

`Odchod za`, `Vyrazit teď`, `Začíná za`, `Právě probíhá`, `Do konce`.

The next work should unify the visual language without breaking AlarmKit ownership or the Stop handoff architecture.

## Recommended order of work

1. Lock Screen AlarmKit visual/copy pass.
2. Dynamic Island AlarmKit visual/copy pass (compact, minimal, expanded).
3. Commander procedure Live Activity visual/copy pass.
4. Verify handoff: AlarmKit countdown → alert → Stop → Commander upcoming/active.
5. Physical iPhone test.
6. Physical Watch / Smart Stack follow-up only after iPhone flow is stable.

## Must-not-break invariants

- canonical alarm deadline = `leaveAt`
- one Commander Live Activity maximum
- Stop intent remains the production creator of Commander activity
- foreground reconciliation must not race a second Activity request
- local lead-time overrides must move AlarmKit, app, Watch and Commander metadata together
- no loss of next-event queue / overlap handling
- ActivityKit static + dynamic payload remains below deliberate 3.6 KB target
- current physical-acceptance harness remains available for destructive/system testing

## Testing baseline

Relevant regression suites include:

- `AlarmCountdownPlanTests.swift`
- `AlarmCountdownRegressionTests.swift`
- `AlarmLiveActivityOwnershipRegressionTests.swift`
- `PhysicalAcceptanceTests.swift`

The physical acceptance app already contains a short Dynamic Island + Watch visual probe and diagnostic timeline support.

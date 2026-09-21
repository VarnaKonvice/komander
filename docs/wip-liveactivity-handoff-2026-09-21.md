# WIP Live Activity handoff — 2026-09-21

Branch: `lc/liveactivity-rebuild-v1`

This is a checkpoint before moving work from Mac Studio to MacBook Air. It intentionally preserves unfinished diagnostic code.

## Physically verified today

- AlarmKit countdown and alarm fire on iPhone.
- AlarmKit alarm reaches Apple Watch.
- Commander Live Activity renders on iPhone Lock Screen.
- Commander Live Activity renders in Apple Watch Smart Stack and detail.
- The pre-start Commander state now shows `Začíná za` correctly after fixing TimelineView evaluation that could resolve using a future explicit timeline date.
- Dynamic Island stayed blank during the physical checks so far.

## Stop handoff status

`CommanderAlarmStopIntent` was changed so the stopped AlarmKit Live Activity is retired before attempting to create/update Commander, to avoid the observed `Target is not foreground` race.

This fix compiles and regression tests pass, but first-creation-after-Stop is NOT yet physically proven. The 14:58/15:05 physical run updated an already existing Commander visual-probe activity, so it cannot prove fresh creation.

## Dynamic Island diagnostic

A special diagnostic presentation for stable ID `physicalAcceptance.visualProbe` was added:
- compact leading: `LC`
- compact trailing: `OK`
- expanded: simple yellow test text/symbols

This diagnostic build was installed, but the automatic launch was denied because the iPhone was locked. It still needs one clean physical rerun. If even this simple content does not appear in Dynamic Island while Lock Screen/Watch do, the issue is not the normal visual layout.

The Live Activity extension Info.plist now explicitly includes `NSSupportsLiveActivities = true`.

## Code verification at checkpoint

- `swift test --package-path native/LazenskyCommander`: 193 tests passed.
- `LazenskyCommanderPhysicalAcceptance` generic iOS build: succeeded.
- `LazenskyCommanderApp` generic iOS build after the latest changes: succeeded.
- `git diff --check`: clean before the checkpoint commit.

## Next physical steps

1. Rerun only the short `--visual-probe` with iPhone unlocked.
2. Check compact/expanded Dynamic Island for the literal diagnostic `LC / OK`.
3. Do not run another long full alarm test until the Dynamic Island result is understood.
4. Then run a fresh Stop handoff with no pre-existing Commander activity to prove first creation.
5. Only after those two points pass, run the complete two-alarm end-to-end sequence.

Do not treat this checkpoint as a finished release.

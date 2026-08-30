# Native alarm contract v1

`LazenskySchedule.nativeAlarmPayload(schedule, overrides)` is the versioned, platform-neutral alarm input derived from the canonical schedule. It is used by the native iOS AlarmKit app and does not create another schedule source.

## Payload schema

```json
{
  "contractVersion": 1,
  "scheduleVersion": 42,
  "alarms": [
    {
      "stableId": "procedure-massage-2026-08-20",
      "kind": "procedure",
      "title": "Massage",
      "location": "Pavilion A",
      "startAt": "2026-08-20T10:00:00",
      "endAt": "2026-08-20T10:30:00",
      "effectiveLeadTimeMinutes": 30,
      "leaveAt": "2026-08-20T09:30:00"
    }
  ]
}
```

`contractVersion` changes only when this native contract changes incompatibly. `scheduleVersion` is the version of the canonical schedule from which the payload was derived. It is useful for freshness and observability, but it is not itself an alarm update trigger.

Every alarm entry is derived through `LazenskySchedule.alarmContract(schedule, overrides)`. `effectiveLeadTimeMinutes` and `leaveAt` therefore use the single existing effective-lead-time calculation. Without `overrides`, the payload uses only canonical values from `data/schedule.json`. It never reads browser storage or another platform store.

`overrides` is an optional plain JSON object with `defaultLeadTimeMinutes`, `procedureTypeOverrides`, `mealOverrides`, and `eventOverrides`. It has the same priority as the existing local effective-lead-time settings. Device-local preferences do not belong in `data/schedule.json`; the platform that owns them passes them explicitly to `nativeAlarmPayload`, `alarmContract`, or `computeLiveState`. Equal schedule and equal overrides produce equal payload output. Datetimes use the same local ISO representation as the schedule contract, and the payload has no generated timestamp or other volatile value.

`stableId` is the canonical identity of one scheduled event. It must remain stable when the event is corrected, such as when its time, title, location, or lead time changes. It is not an iOS, AlarmKit, or platform UUID.

## Reconciliation

`LazenskySchedule.reconcileNativeAlarms(currentAlarms, nextPayload)` produces:

```json
{
  "create": [{ "stableId": "...", "nextAlarm": {} }],
  "update": [{ "stableId": "...", "currentAlarm": {}, "nextAlarm": {} }],
  "cancel": [{ "stableId": "...", "currentAlarm": {} }],
  "unchanged": [{ "stableId": "...", "currentAlarm": {}, "nextAlarm": {} }]
}
```

`currentAlarms` may be an alarm array or a previous payload with an `alarms` array. Identity is always `stableId`.

- A `stableId` present only in `nextPayload.alarms` is `create`.
- A `stableId` present only in `currentAlarms` is `cancel`.
- A shared `stableId` is `unchanged` when `kind`, `title`, `location`, `startAt`, `endAt`, `effectiveLeadTimeMinutes`, and `leaveAt` are all equal.
- A shared `stableId` is `update` when any of those alarm-relevant fields differs.
- A higher `scheduleVersion` alone never produces `update`.

The native client owns its local mapping from `stableId` to `AlarmKit.Alarm.ID` (or another platform identifier). Neither `data/schedule.json` nor this payload contains a platform UUID. The mapping is local implementation state and can be recreated from the canonical payload and reconciliation plan.

## Implementovaná iPhone adaptace

`LazenskyCommanderApp` načte a validuje schedule jednou. Stejný `Schedule` používá `AlarmSyncService`, Commander Live Card a `WatchScheduleSnapshot`. AlarmKit reconciliation ukládá lokální mapování `stableId -> AlarmKit Alarm.ID`; změněné alarmově relevantní pole vede k update, odstraněná událost k cancel a samotné zvýšení `scheduleVersion` update nevytváří.

Canonical native payload nadále obsahuje všechny události. `AlarmSyncService` z něj pro konkrétní synchronizaci vytvoří pouze AlarmKit desired set s `leaveAt > now`; `leaveAt == now` se již neplánuje. Minulý managed alarm, který v AlarmKitu stále existuje, se cancelne, zatímco chybějící platformní alarm se pouze odstraní z lokálního mapování. Uložený `ManagedAlarmState` po úspěšném syncu obsahuje jen spravované budoucí AlarmKit alarmy. Tento filtr nemění `Schedule`, Live Card ani celý `WatchScheduleSnapshot`.

Cílový čas zazvonění je canonical `leaveAt`. `AlarmCountdown` zachovává okno od konce předchozí události, nejvýše 30 minut; při nulovém okně používá přímý alarm bez countdownu. `AlarmAttributes<CommanderAlarmMetadata>` předává `stableId`, `scheduleVersion`, `iconKey`, `title`, `location`, `kind`, `startAt` a `leaveAt` skutečné Live Activity extension. Lock Screen i Dynamic Island vykreslují stejný systémový `AlarmPresentationState.Mode.Countdown.fireDate`, nikoli vlastní odpočet.

### AlarmKit countdown scheduling and read-back

Physical E2E on 2026-08-30 demonstrated that `.fixed(10:20)` with `preAlert = 300` starts the countdown at 10:20 and alerts at 10:25. The adapter must therefore distinguish countdown start from the canonical alert deadline:

- Before the countdown window: `schedule = .fixed(leaveAt - countdownWindow)`, `preAlert = countdownWindow`.
- At or inside the window: `schedule = nil`, `preAlert = leaveAt - now`, starting the remaining countdown immediately.
- Zero window: `.alarm(schedule: .fixed(leaveAt), ...)`, without a pre-alert duration.

`scheduledAlertAt` remains the canonical target, not the fixed schedule argument for a countdown. The native payload and lead-time priorities do not change.

Read-back verifies the effective endpoint against canonical `leaveAt` (existing one-second tolerance): observed AlarmKit activity `fireDate` keyed by platform `alarmID`, or fixed countdown start plus stored `preAlert` when no active countdown is exposed. An immediate timer with no fixed schedule requires the observed `fireDate`; desired metadata is never evidence of the actual endpoint. If this read-back is not available yet, verification reports a recoverable error, preserves the managed IDs, and the existing retry reads them again without cancelling/recreating them. Timing inspection is limited to managed future alarms so expired alarms and orphans can still be removed by existing ID reconciliation.

This repairs the regression introduced by `260730f` / `c574e86` and the raw-fixed-date verification in `7d6acf4`; it does not roll back production/E2E isolation, ownership, self-recovery, or canonical synchronization. A signed physical confirmation remains necessary; generic builds and simulated runtime tests alone cannot prove an audible alarm deadline.

Before reconciliation writes, only retained unchanged alarms require old timing read-back. Explicit updates and cancellations must not depend on an obsolete timer's activity being available; all replacements still undergo strict post-write verification.

### Local physical acceptance

The [physical acceptance app](physical-alarm-acceptance.md) uses this same contract and adapter with a locally generated two-event Schedule, explicit empty device overrides, fresh in-memory state and a unique run namespace. Its bundle and ownership ledger are separate from production and remote E2E. `resolvedLeadTime` exposes provenance from the existing priority resolver without changing payload shape or priority. Production ActivityKit behavior is enabled in this isolated mode; Watch delivery and network schedule fetching are absent. READY requires actual platform read-back, and never implies a physically confirmed PASS.

## Implementovaná Watch adaptace

iPhone předává celý `WatchScheduleSnapshot` přes `WCSession.updateApplicationContext`. Watch envelope i schedule se znovu validují a vyšší verze se atomicky uloží do App Group `group.com.varnakonvice.lazenskycommander.watch`. Watch app a WidgetKit extension čtou pouze tuto cache; přímý Watch internet fetch není implementovaný ani potřebný.

Widget timeline a RelevanceKit intervaly se odvozují z celého cached pobytu a společného live-state/alarm contractu. Cache je platná do poslední události plus 24 hodin. Neobsahuje GPS, location relevance ani cellular podmínky.

Volitelný persistentní režim **Samostatné alarmy Watch** používá `UNUserNotificationCenter` přímo na watchOS. Požadavky jsou standardní active lokální notifikace se systémovým zvukem a respektují systémová nastavení notifikací a režimů soustředění na Watch. Budoucí notifikace se odvozují ze stejného native payloadu a mají deterministický identifikátor `lazensky.commander.watch.leave.<stableId>`, titul `Čas vyrazit` a tělo `<procedura> · <místo>`. Reconciliation spravuje pouze tento namespace, podporuje create/update/cancel/unchanged a plánuje nejbližších nejvýše 60 pending požadavků. Rolling limit neomezuje data uložená v cache. Vypnutí režimu odstraní pouze tyto Watch leave notifikace; cizí požadavky zůstávají nedotčené.

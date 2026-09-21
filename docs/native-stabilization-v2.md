# Stabilizační průchod nativní aplikace – září 2026

Pracovní větev: `lc/liveactivity-rebuild-v1`. Základní HEAD rekonstrukce je `b8cd52a`; současné změny jsou před fyzickým acceptance záměrně necommitnuté. `main` se tímto průchodem nemění.

Tento dokument je aktuální registr architektury, invariantů a mezí důkazů. Historické incidenty a starší handoff pokusy zůstávají v samostatných incident dokumentech, ale nejsou současným runtime kontraktem.

## Vlastnictví lifecycle

| Oblast | Vlastník | Aktuální kontrakt |
| --- | --- | --- |
| Canonical rozpis | `CommanderScheduleSyncCoordinator` + validovaný `ScheduleSnapshotStoring` | Lokální preference nikdy nepřepisují canonical feed |
| Odchod / countdown / zvonění / Stop | AlarmKit přes `AlarmSyncService` + `AlarmKitAdapter` | AlarmKit je jediný vlastník celé odchodové fáze |
| Procedura / jídlo Live Activity | `CommanderProcedureLiveActivityCoordinator` | Nejvýše dvě nejbližší neskončené události; start kontextu přes `leaveAt`, časové fáze `Začíná za` → `Právě…` → další/skončeno; žádná mutace ze Stop intentu |
| Alarm presentation context | `AlarmPresentationContext` | Jen countdown window a typ aktuální události; žádný další-event/Stop handoff stav |
| Dynamic Island / Lock Screen | `LazenskyCommanderLiveActivity` | AlarmKit a Commander mají oddělené ActivityConfiguration; compact timer má explicitně omezenou šířku |
| Watch schedule | `WatchScheduleSnapshot` → `WCSession.updateApplicationContext` → validovaná App Group cache | Watch app/widget čtou poslední validní lokální snapshot |
| Watch Live Activity | systémová replikace iPhone Live Activity + `.supplementalActivityFamilies([.small])` | Není totožná s datovou cestou samostatné Watch app |
| Provisioning reminder | samostatný renewal coordinator | Due delivered reminder se nesmaže pouhým foregroundem |
| Fyzický acceptance | izolovaný `Commander Test` bundle | READY ověřuje přípravu; nikdy automaticky neznamená fyzický PASS |

## Finální lifecycle v2

1. AlarmKit připraví odchodový countdown tak, aby jeho endpoint byl přesně canonical `leaveAt`.
2. V `leaveAt` AlarmKit zobrazí alert a zazvoní.
3. **Stop pouze zastaví AlarmKit.** Nevolá `Activity.request`, `update` ani `end` pro Commander proceduru/jídlo.
4. Commander kontext je naplánovaný už od canonical `leaveAt`, takže po Stop nemá vzniknout hluchá mezera. Do `startAt` zobrazuje `Začíná za` a název/lokalitu následující události. Starý červený bridge zůstává odstraněný.
5. V canonical `startAt` se tatáž Commander prezentace lokálně přepne na `Právě jídlo` / `Právě probíhá` a odpočet do `endAt`; přepnutí používá `TimelineView` s explicitními hranicemi a nevyžaduje foreground aplikace.
6. Budoucí lokální scheduled start používá ActivityKit `start: candidate.leaveAt`. Platforma pro něj vyžaduje `AlertConfiguration`; bundled `CommanderSilentAlert.wav` odstraní druhý slyšitelný alarm, ne však možnost systémového vizuálního start alertu.
7. `staleDate = endAt` pouze označuje zastarání. Není to obecný přesný lokální scheduler ukončení; při dalším reconciliation coordinator explicitně ukončuje prošlé/neplatné aktivity.

## AlarmKit countdown

`AlarmCountdown` vždy zachovává canonical `leaveAt` jako skutečný čas alarmu. Okno začíná po konci poslední předchozí události stejného dne, maximálně 30 minut před `leaveAt`.

- Jsme-li před oknem: `schedule = .fixed(leaveAt - countdownWindow)` + `preAlert = countdownWindow`.
- Jsme-li již uvnitř okna: `schedule = nil` + `preAlert = leaveAt - now`; countdown začne okamžitě.
- Nulové okno: přímý alarm na `leaveAt` bez countdownu.

`AlarmPresentationContext` persistuje jen `countdownWindow`, `procedureType` a `mealType`. Změna následující události již neobnovuje nesouvisející předchozí alarm. Změna předchozího konce alarm obnoví pouze tehdy, když se tím změní countdown window.

## Visual QA

Před fyzickým telefonem byl použit izolovaný `LazenskyCommanderAlarmFreeVisualTest` na iOS simulátoru bez sítě a bez AlarmKitu. Ověřen byl dashboard a skutečný ActivityKit host na iPhone 17 Pro simulátoru.

Visual QA odhalil konkrétní chybu compact Dynamic Islandu: SwiftUI `Text(date, style: .timer)` v Live Activity rezervoval nadměrnou horizontální šířku a v kombinaci s `.fixedSize(horizontal: true)` vytlačil compact trailing obsah. Oprava přidala explicitní šířku compact timeru (`54 pt`) pro Commander procedure timer i AlarmKit countdown. Následný runtime snímek ukázal normální compact Island, logo + ikonu vlevo a viditelný odpočet vpravo.

Tento simulátorový důkaz potvrzuje layout/runtime host, nikoli slyšitelný alarm, fyzický Lock Screen, Always-On, Watch synchronizaci ani systémové chování konkrétního iPhonu.

## Automatické invarianty

| Invariant | Ochrana |
| --- | --- |
| AlarmKit vždy vlastní departure countdown; Commander kontext startuje v `leaveAt` a do `startAt` nelže o probíhající proceduře | `alarmKitOwnsDepartureAndCommanderContextStartsAtLeaveAt`, `commanderContextHasNoPostStopGapAndStaleFallsForwardToNextEvent` |
| Stop intent nesmí Commander aktivitu vytvořit ani měnit | `stopIntentNeverCreatesOrMutatesCommanderProcedureActivity` |
| AlarmKit, Watch a Commander musí pro jeden projekční průchod sdílet stejné override-adjusted `leaveAt` | `commanderUsesOverrideAdjustedLeaveAtLikeAlarmKitAndWatch` |
| Commander reconciliation se nesmí prokládat přes `await` a nesmí ponechat duplicitní stejné `stableId` | `commanderReconciliationIsSerializedAndDeduplicatesStableIDs` |
| Compact timery nesmí znovu roztáhnout Dynamic Island | strukturální guardy v `alarmKitOwnsDepartureAndCommanderContextStartsAtLeaveAt` + runtime Visual QA |
| Změna následující události nesmí zbytečně regenerovat předchozí alarm | `alarmPresentationContextIgnoresFollowingEventChanges`, `followingEventChangeDoesNotRefreshUnrelatedAlarm` |
| Změna předchozího konce musí změnit countdown window | `alarmPresentationContextTracksPreviousEventCountdownWindow` |
| Physical acceptance připraví dvě AlarmKit countdown cesty i dvě Commander aktivity | `physicalPreflightAcceptsAlarmKitCountdownForBothEventsEvenWhenCommanderActivitiesArePrepared` |
| Selhání cancel nesmí vytvořit duplicitní AlarmKit ID | `failedCancellationBeforeRepairKeepsManagedIDAndNeverCreatesDuplicate`, `failedCancellationDuringPostWriteRepairKeepsNewIDForSafeRetry` |
| Foreground nesmí umlčet platně zvonící canonical alarm | `foregroundReconciliationDoesNotSilenceRingingCanonicalAlarmOrRecreateStoppedAlarm` |
| Starší/conflicting snapshot nesmí rollbacknout canonical stav | snapshot acceptance testy |
| Watch operace zůstávají serializované a cache validovaná | Watch cache/notification/ack testy |
| Due provisioning reminder přežije foreground | provisioning reminder testy |

## Fyzický acceptance v2

Izolovaný test vytváří dvě události: jídlo T+6 až T+8 s leaveAt T+4 a magnetoterapii T+13 až T+15 s leaveAt T+11.

- První AlarmKit countdown začíná okamžitě, protože při spuštění už jsme uvnitř jeho okna.
- Druhý countdown začíná v T+8 a běží do T+11; předchozí Commander karta nevlastní „volno“.
- Dvě Commander aktivity jsou předem připravené se scheduled starty v jejich `leaveAt` (T+4 a T+11).
- Po každém Stop musí být bez dalšího uživatelského zásahu dostupný Commander kontext `Začíná za …`; **hluchá mezera i červený Commander handoff jsou FAIL UX/architektury**.
- PASS vyžaduje skutečné zazvonění obou alarmů v canonical `leaveAt`, Commander kontext bez hluché mezery po Stop, lokální přepnutí na `Právě…` v `startAt` a na další událost / `Skončilo` v `endAt`. Okamžité odstranění systémové karty není součástí lokální Personal Team garance.

Podrobný postup je v [physical-alarm-acceptance.md](physical-alarm-acceptance.md).

### Fyzický běh 2026-09-18 – neplatný jako finální PASS, ale s užitečnými fyzickými důkazy

Run `8733CA09-F01A-42DD-B4CC-70FB6F4ED879` začal v 08:16:44. AlarmKit read-back i screenshoty doložily první canonical leaveAt 08:21:00 a druhý canonical leaveAt 08:28:00. První odchodový countdown byl viditelný už v 08:16:53, první skutečný AlarmKit alert byl na iPhonu v 08:21:02 a na Watch v 08:21:05. Druhý countdown byl na iPhonu v 08:25:33 a druhý alert v 08:28:10; na Watch v 08:28:13. Druhý Stop intent se fyzicky provedl pro ID `FF8171F3-F7A5-41EF-BF84-63537A5EB930`.

Commander Live Activity pro jídlo se zobrazila na iPhonu v 08:23:23 a na Watch v 08:23:37, tedy u plánovaného startu 08:23. V 08:25 přešla do stale UI `Jídlo skončilo`. Stará stale karta zůstala viditelná i později, což odpovídá známému lokálnímu omezení: `staleDate` není přesný future end/dismiss scheduler. Magnetoterapie se na Watch zobrazila v 08:30:34, tedy u plánovaného startu 08:30; tvrzení o opožděném startu proto fyzické screenshoty nepotvrdily.

Běh přesto **není platný finální PASS**, protože při prvním Commander startu v 08:23:23 vyskočil systémový dialog `Povolit živé aktivity z aplikace Commander Test?`. Preflight tedy chybně dovolil časovaný běh dřív, než bylo prvotní Live Activity oprávnění skutečně fyzicky vyřešené. Acceptance aplikace proto nově používá samostatný Live Activity primer před vytvořením `PhysicalAcceptanceRun`; teprve po jeho potvrzení smí vzniknout ostré časy.

Physical report navíc nově odděluje historické `2/2 při READY` od aktuálního počtu po skončení, ukládá časovou osu READY, AlarmKit snapshotů, ActivityKit stavů a všech Stop intentů a průběžně čistí ownership ledger o systémově již neexistující AlarmKit ID.

### Večerní běh 2026-09-18 – produktový FAIL staršího buildu

Run `EBA6DBDF-47C0-43EF-A281-5CD49710938C` měl platné READY 2/2 pro AlarmKit i 2/2 připravené Commander aktivity. První Stop byl zaznamenán v 20:17:06, jídlo přešlo active přibližně v 20:19:10 a stale v 20:21:00, druhý Stop v 20:24:15. Fyzicky ale po Stop vznikla na iPhonu hluchá mezera a Watch později stále ukazovaly staré `TEST – Jídlo` jako skončené; z pohledu cílového UX je tento běh **FAIL**.

Testovaný podepsaný binární build byl sestaven v 20:03. Opravy scheduled startu z `startAt` na `leaveAt`, embedded `nextEvent` a následné časové fáze `Začíná za` → `Právě…` vznikly až po tomto buildu. Večerní běh proto není fyzickým důkazem proti současnému kódu, ale přesně definuje regresi, kterou musí další jediný acceptance běh vyvrátit. Současná oprava je zatím krytá pouze automatickými testy/buildy a nesmí být označena jako fyzicky PASS.

## Co automatika stále negarantuje

- APNs není v Personal Team variantě použit; lokální scheduled ActivityKit start je závislý na systémovém contractu a může zobrazit start alert.
- `maximumPreparedActivities = 2` je pouze malý lokální rolling window, nikoli celodenní fronta. Scheduled i active Live Activities spotřebovávají systémovou kapacitu a její přesný limit není veřejný/stabilní. Pokud aplikace zůstane suspendovaná, lokální kód nemá garantovaný okamžik pro doplnění třetí a dalších událostí. Při každém foregroundu se ale Commander activity window reconciliuje ještě před throttlem síťové/AlarmKit synchronizace, takže se nejbližší dvojice doplní okamžitě z posledního validního rozpisu. Dvouudálostní physical acceptance tuto produkční mezeru záměrně nesmí vydávat za full-day důkaz.
- Přesné future `update`/`end` libovolné ActivityKit aktivity bez execution time nemá obecnou lokální garanci. `staleDate` určuje okamžik, kdy systém obsah považuje za stale, ale negarantuje skutečný end/dismissal ani přesnou fyzickou obnovu každé plochy; vlastní fázové UI proto používá explicitní `TimelineView` hranice a skutečný cleanup proběhne při dalším execution time.
- Generic unsigned build neověřuje fyzický signing/provisioning, zvuk AlarmKitu ani doručení na Watch.
- Watch app data přes WatchConnectivity a systémová Live Activity replikace na Watch jsou dvě různé acceptance oblasti.
- Vzdálená změna canonical feedu při dlouhodobě suspendované app nemá vlastní push/background wake garanci.
- VoiceOver, největší Dynamic Type, Always-On/reduced luminance a finální Lock Screen render vyžadují fyzický/UI acceptance.

## Gate před telefonem

Před jediným závěrečným fyzickým během musí být zelené:

1. celý Swift test suite,
2. build `LazenskyCommanderApp`,
3. build `LazenskyCommanderLiveActivity`,
4. build `LazenskyCommanderPhysicalAcceptance`,
5. build `LazenskyCommanderWatchApp`,
6. `git diff --check`,
7. read-only audit, že ve Swift runtime nezůstal starý handoff/bridge mechanismus a dokumentace odpovídá implementaci.

Žádný commit, push, merge, tag, release ani Vercel deployment není součástí tohoto gate.

**Finální bezplatný kontrakt:** projekt zůstává na Personal Teamu. APNs/backend ani placené Apple Developer členství se neimplementují. AlarmKit je celodenní garantovaná odchodová vrstva; Commander Live Activity používá dvouslotový lokální rolling window a další aktivity se doplní při příštím foreground/reconciliation. Tento limit je přijatý produktový kompromis a nesmí se později maskovat jako full-day Live Activity garance.

# Lázeňský Commander – native stabilization v3

Větev: `lc/alarm-liveactivity-unification-v1`.

Tento soubor popisuje současnou podporovanou architekturu po sjednocení denního Live Activity příběhu 26. 9. 2026. Historické handoff varianty a neúspěšné background create pokusy jsou v `docs/archive/liveactivity-stabilization-history-2026-09.md`.

## Podporovaný lifecycle

1. Canonical rozpis určuje `startAt` a `endAt`; efektivní předstih určuje canonical `leaveAt`.
2. AlarmKit vlastní pouze skutečný alert, zvonění a Stop v canonical `leaveAt`. Předodchodový countdown zobrazuje výhradně Commander a widget extension obsahuje jediný `ActivityConfiguration` pro `CommanderProcedureLiveActivityAttributes`.
3. Foreground/bootstrap reconciliation rozdělí den do několika Commander Live Activity oken. Standardně okno začíná 60 minut před první událostí, nebo dříve v jejím `leaveAt`, pokud je předstih delší.
4. Jídlo i procedura mohou být kotvou okna.
5. Události s volnou mezerou do 2 hodin mohou zůstat v jednom okně. Delší volno blok ukončí a další blok se připraví jako nový scheduled start.
6. Jedno okno obsahuje nejvýše 6 událostí a nejvýše 7 h 50 min aktivního časového rozpočtu. Coordinator připravuje nejvýše 3 nejbližší okna.
7. Časový příběh jedné události je explicitně stavový:
   - před alarmem: **Vyrazit za** + systémový timer do `leaveAt`,
   - po uživatelském **Stop**: stejná Commander Live Activity přejde na **Konec za** + absolutní začátek události,
   - další AlarmKit Stop může fokus stejné aktivity posunout na další událost.
8. Karta ukazuje následující událost jako **Potom** nebo **Současně**. Lock Screen zobrazuje název, čas i místo.
9. Foreground reconciliation může fokus srovnat podle aktuálního času; bez APNs/push se negarantuje přesná automatická strukturální změna v `startAt` nebo `endAt`.
10. Schválená ikona a barva jsou odvozené od typu konkrétní události. Urgentní alert vrstvu vlastní AlarmKit.
11. Stop intent nikdy nezakládá Commander Live Activity z backgroundu; smí aktualizovat už existující aktivitu pomocí `Activity.update`.
12. Renderer Live Activity nepoužívá `TimelineView`; dynamický čas kreslí pouze systémový timer. Stejná ActivityKit instance se používá pro Lock Screen, Dynamic Island a systémovou replikaci na Apple Watch.

## AlarmKit a Commander

AlarmKit a Commander používají stejný canonical rozpis, ale nekreslí současně dvě průběžné odpočtové vrstvy. AlarmKit je bezpečnostní autorita pro samotné zazvonění v `leaveAt`; Commander je jediný předodchodový vizuální countdown, kontext a navigace kolem něj.

Jediným produkčním místem, které smí volat `Activity<CommanderProcedureLiveActivityAttributes>.request`, je `CommanderProcedureLiveActivityCoordinator`. Budoucí okna používají scheduled start a tichý `CommanderSilentAlert.wav`, takže Commander nepřidává druhý zvuk vedle AlarmKitu.

`CommanderAlarmStopIntent` nesmí obsahovat `Activity.request`. Smí najít již aktivní Commander Live Activity a aktualizovat její `focusStableId` + `presentationMode` přes `Activity.update`. Selhání Commander Live Activity nesmí změnit správně naplánované AlarmKit alarmy.

## Plánování oken

`CommanderLiveActivityPlan.makeWindows` je čistá testovatelná vrstva.

Výchozí politika:
- kontext před událostí: 60 minut,
- maximální volná mezera uvnitř bloku: 2 hodiny,
- maximálně 3 předem připravená okna,
- maximálně 6 událostí na okno,
- maximálně 7 h 50 min aktivního rozpočtu jednoho okna.

Příklad: snídaně 6:45 a procedura 7:45 mohou být v jednom ranním okně. Pokud po poslední proceduře následuje 2 h 50 min volno před večeří, ranní/odpolední karta skončí a večeře dostane vlastní blok, typicky 60 minut před začátkem.

## Reconciliation

`CommanderProcedureLiveActivityCoordinator`:
- serializuje reconciliation průchody,
- drží nejvýše jednu **aktivní** Commander aktivitu v plánovaném čase,
- může současně držet pending následníky, které musí být naplánované předem,
- ověřuje renderer revision, scheduleVersion, projectionRevision, activationStart, leaveAt, startAt, endAt a frontu událostí,
- pending snapshot při změně nahrazuje místo nespolehlivého pokusu o update,
- aktivní keeper aktualizuje,
- odstraňuje historické duplicity a již nežádoucí instance při foreground reconciliation.

## Barvy a ikony

Live Activity používá stejný schválený vizuální kontrakt jako aplikace:
- Jídlo zelená,
- Vodoléčba azurová,
- Rehabilitace tyrkysová,
- Masáže korálová,
- Zábaly/teplo žlutá,
- Elektroléčba světle fialová,
- Terapie/fallback růžová,
- skončený stav neutrální.

Commander používá schválenou barvu konkrétní události v obou režimech `departureCountdown` i `eventContext`. Urgentní systémovou alert prezentaci vlastní AlarmKit.

## Fyzický acceptance

Dosavadní fyzické testy už prokázaly samostatně:
- AlarmKit reálné zvonění,
- Lock Screen a Dynamic Island,
- historický přechod `Právě probíhá → 0:00 → Skončilo` patří ke staré TimelineView variantě; build 7 ji už nepoužívá,
- systémovou replikaci Live Activity do Apple Watch Smart Stack/detail.

Další fyzický test nejdřív ověří krátký tok `Vyrazit za → AlarmKit alert → Stop → stabilní eventContext` na iPhonu a Watch. `eventContext` po Stop ukazuje systémově živé `Start za …`, po `startAt` automaticky `Start před …`, absolutní konec a odpočet do `endAt`; bez dalšího triggeru se nesnaží předstírat strukturální přechod `Právě probíhá`. Celý zrychlený lázeňský den se spustí až po PASS tohoto základu.

## Systémové limity

- AlarmKit zůstává celodenní garantovanou upozorňovací vrstvou.
- Jedna Live Activity nemá být používána jako nekonečná celodenní instance; Commander proto dělí den na okna.
- `staleDate` není přesný future-dismiss scheduler. Bez foreground/background execution není garantováno, že stará skončená karta zmizí přesně při startu následníka.
- Systém může omezit počet současně pending/active Live Activities. Pokud vzdálenější pending okno odmítne, AlarmKit zůstává nedotčený a další foreground reconciliation se může pokusit okno doplnit.
- Bez push/background wake není garantováno, že vzdálená změna canonical feedu probudí dlouhodobě suspendovanou aplikaci.

## Gate před zítřejším E2E

Před fyzickým během musí projít:
1. celý Swift test suite,
2. produkční iOS build,
3. Physical Acceptance build,
4. Watch build,
5. `git diff --check`,
6. statická kontrola, že Stop intent neobsahuje `Activity.request`,
7. kontrola, že produkční Commander create cesta existuje jen v serializovaném coordinatoru.

Dnešní programovací práce nevyžaduje žádný další fyzický alarmový běh.

# Physical Alarm Acceptance

## Účel

`LazenskyCommanderPhysicalAcceptance` je izolovaná servisní aplikace. Produkční Commander, canonical storage ani produkční alarm ownership nemění.

Dnešní acceptance už neověřuje starý Stop → vytvořit Live Activity handoff. Ověřuje zrychlený „lázeňský den“: AlarmKit jako zvukovou bezpečnostní vrstvu a několik předem připravených Commander Live Activity oken jako souvislý kontext.

## Oddělení od produkce

- App: `com.varnakonvice.lazenskycommander.physicalacceptance`.
- Embedded extension: `com.varnakonvice.lazenskycommander.physicalacceptance.liveactivity`.
- Target sdílí produkční `AlarmKitAdapter`, `CommanderProcedureLiveActivityCoordinator`, metadata a Live Activity renderer.
- Produkční schedule/prefs/managed alarms se nečtou ani nepřepisují.
- WatchConnectivity je vypnuté; Live Activity se na párované Watch replikuje systémově přes ActivityKit.

## Zrychlená časová osa

Rozpis vzniká relativně k nejbližší celé minutě po startu testu:

| Událost | Začátek | Konec | Lead time | leaveAt |
| --- | ---: | ---: | ---: | ---: |
| TEST – Snídaně | T+5 | T+10 | 1 min | T+4 |
| TEST – Magnetoterapie | T+9 | T+12 | 3 min | T+6 |
| TEST – Rehabilitace | T+14 | T+16 | 2 min | T+12 |
| TEST – Večeře | T+21 | T+24 | 2 min | T+19 |

Testovací coordinator používá pouze pro tento izolovaný target zrychlené plánovací hodnoty:

- Live Activity context lead: 3 minuty,
- maximální volná mezera uvnitř jednoho okna: 3 minuty,
- maximálně 3 naplánovaná okna,
- maximální životnost testovacího okna: 30 minut.

Produkční defaults zůstávají 60 minut context lead, 2 hodiny maximum idle gap, nejvýše 3 okna a 7 h 50 min lifetime budget.

První okno tedy obsahuje Snídani → Magnetoterapii → Rehabilitaci. Večeře je samostatný následný blok po delší testovací mezeře.

## Co musí scénář prokázat

1. **Před snídaní:** Commander se objeví před prvním odchodem a ukazuje Snídani, odchod a následující Magnetoterapii.
2. **T+4:** zazvoní AlarmKit pro Snídani.
3. **T+5:** karta přejde na `Právě probíhá – Snídaně`.
4. **T+6 během snídaně:** zazvoní AlarmKit pro Magnetoterapii a Commander musí dát prioritu stavu `Čas vyrazit – Magnetoterapie`, i když Snídaně ještě formálně běží.
5. **T+9:** Magnetoterapie přejde na `Právě probíhá`; jako další je vidět Rehabilitace.
6. **T+12:** zazvoní AlarmKit pro Rehabilitaci.
7. **T+14 až T+16:** probíhá Rehabilitace.
8. **Po T+16:** první Commander blok skončí. Následuje zrychlené „dlouhé volno“.
9. **T+18:** má vzniknout samostatný pending/active blok pro Večeři (3 min před jejím začátkem, 1 min před leaveAt).
10. **T+19:** zazvoní AlarmKit pro Večeři.
11. **T+21 až T+24:** karta ukazuje probíhající Večeři a následně `Skončilo`.

Současně se průběžně ověřují Lock Screen, Dynamic Island a Apple Watch Smart Stack/detail.

## AlarmKit kontrakt

Všechny testovací i produkční AlarmKit alarmy jsou **alert-only fixed** přímo v canonical `leaveAt`.

- `countdownDuration` je vždy nil,
- `preAlert` i `postAlert` jsou nil,
- fixed schedule je přesně `leaveAt`,
- předodchodový odpočet zobrazuje pouze Commander Live Activity.

Důvodem je fyzický E2E z 27. 9. 2026: AlarmKit countdown Live Activities obsazovaly Lock Screen, Dynamic Island i Apple Watch a přebíjely současně aktivní Commander Live Activity.

## READY podmínky

Před stavem READY musí být současně ověřeno:

- **4/4** skutečné AlarmKit záznamy se správným canonical fire time,
- AlarmKit ownership/read-back odpovídá testovacímu run ID,
- Live Activities jsou povolené,
- alespoň jedno odpovídající Commander okno je už `pending` nebo `active`,
- event queue, `scheduleVersion` a `projectionRevision` odpovídají lokálnímu testovacímu rozpisu,
- do prvního alarmu zbývá alespoň minuta.

READY je důkaz přípravy, nikoli fyzický PASS.

## PASS / FAIL

**PASS:** všechny čtyři alarmy zazvoní v canonical `leaveAt`; první Live Activity projde Snídaně → Magnetoterapie → Rehabilitace včetně priority odchodu na Magnetoterapii během Snídaně; po delší mezeře vznikne samostatný blok Večeře; stavy, barvy, ikony, další událost, Dynamic Island a Watch odpovídají stejnému příběhu.

**FAIL:** některý alarm má jiný fire time, další odchod nepřevezme prioritu, vzniknou překrývající se vlastní Commander karty, následný blok se neaktivuje, Watch nedostanou Live Activity, nebo se objeví background `Activity.request` cesta ze Stop intentu.

## Gate před fyzickým během

1. celý Swift test suite,
2. CoreCheck,
3. produkční iOS build,
4. Physical Acceptance build,
5. Watch build,
6. `git diff --check`,
7. Stop intent bez `Activity.request`,
8. přesný git SHA a build identity nainstalované testovací aplikace,
9. read-back čtyř AlarmKit záznamů před zamknutím telefonu.

Po PASS/FAIL se všechny testovací alarmy a Live Activities uklidí.

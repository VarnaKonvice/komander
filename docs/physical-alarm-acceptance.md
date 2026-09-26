# Lokální fyzický self-test AlarmKitu a scheduled Commander Live Activity

## Účel

`LazenskyCommanderPhysicalAcceptance` je izolovaná servisní aplikace. Produkční Commander, jeho canonical storage ani produkční alarm ownership nemění.

Tento test už **neověřuje starý Stop → vytvořit Live Activity handoff**. Tato cesta byla fyzicky opakovaně prokázána jako nespolehlivá (`Target is not foreground`) a není součástí aktuální architektury.

Aktuální kontrakt je:

1. AlarmKit je jediná garantovaná zvuková vrstva a vlastní departure countdown + alarm.
2. Commander Live Activity se připraví z foreground execution time předem.
3. Pro první relevantní povinnou proceduru použije ActivityKit scheduled start přesně v canonical `leaveAt`.
4. Scheduled start používá tichý `CommanderSilentAlert.wav`, aby nevznikl druhý zvuk vedle AlarmKitu.
5. Stop intent Commander aktivitu nevytváří ani nerequestuje z backgroundu.
6. Po scheduled startu jedna Commander aktivita nese omezenou frontu událostí a přechází `Následuje → Právě probíhá → Potom / Skončilo` přes `TimelineView`.

## Oddělení od produkce

- App: `com.varnakonvice.lazenskycommander.physicalacceptance`.
- Embedded extension: `com.varnakonvice.lazenskycommander.physicalacceptance.liveactivity`.
- Target sdílí produkční `AlarmKitAdapter`, `CommanderProcedureLiveActivityCoordinator`, metadata a Live Activity renderer.
- Watch delivery je v testovacím targetu vypnuté; systémová replikace Live Activity na párované Watch je ale vlastnost ActivityKitu, nikoli WatchConnectivity.
- Produkční schedule/prefs/managed alarms se nečtou ani nepřepisují.

## Testovací časová osa

Po zachycení `now` vznikne lokální canonical rozpis:

| Událost | Začátek | Konec | Lead time | leaveAt |
| --- | --- | --- | --- | --- |
| TEST – Jídlo | T+6 min | T+8 min | 2 min | T+4 min |
| TEST – Magnetoterapie | T+13 min | T+15 min | 2 min | T+11 min |

První jídlo slouží dál hlavně jako nezávislá kontrola AlarmKitu. Commander scheduled Live Activity se kotví k povinné proceduře `TEST – Magnetoterapie`, takže její scheduled start je T+11.

## READY podmínky

Před stavem READY musí být současně ověřeno:

- 2/2 skutečné AlarmKit záznamy se správným canonical fire time,
- AlarmKit ownership/read-back odpovídá testovacímu run ID,
- Live Activities jsou v systému povolené,
- existuje právě jedna odpovídající Commander Activity ve stavu `pending` nebo `active`,
- její `scheduleVersion`, `projectionRevision` a event queue odpovídají testovacímu rozpisu,
- do prvního AlarmKit alarmu zbývá bezpečná rezerva.

READY je pouze důkaz přípravy. Není to fyzický PASS.

## Co později ověřit jedním jediným fyzickým během

Fyzický běh má smysl až poté, co projdou automatické testy, produkční build, Physical Acceptance build, Watch build a samostatný simulator scheduled-start probe.

| Čas | Očekávání |
| --- | --- |
| T+4 | TEST – Jídlo: AlarmKit zazvoní. Commander karta se kvůli samotnému jídlu neočekává. |
| T+11 | TEST – Magnetoterapie: AlarmKit zazvoní a systém aktivuje již předem naplánovanou Commander Live Activity. |
| Po Stop | Commander karta musí zůstat; Stop nesmí spouštět žádný nový `Activity.request`. |
| T+11 až T+13 | Commander ukazuje `Následuje` a čas začátku magnetoterapie. |
| T+13 až T+15 | Tatáž karta ukazuje `Právě probíhá` a `Do konce`. |
| Po T+15 | Tatáž karta přejde na další známou událost nebo `Skončilo`. |

Na Dynamic Islandu a Apple Watch se ověřuje tatáž ActivityKit instance; nevytváří se samostatná Commander aktivita pro hodinky.

## PASS / FAIL

**PASS:** správné AlarmKit časy, Commander Activity existuje už před Stopem jako pending/active, v T+11 se systémově aktivuje, po Stop nezmizí, v T+13 a T+15 se časově přepne bez nutnosti znovu otevřít aplikaci.

**FAIL:** Commander před T+11 není připravená, scheduled start nenastane, Stop ji odstraní, objeví se další Commander instance, nebo diagnostika obsahuje `Target is not foreground` spojené s Commander create cestou.

Staré testy varianty „první Stop vytváří Commander“ se už neopakují. Historické důkazy jsou v `docs/archive/liveactivity-stabilization-history-2026-09.md` a `docs/wip-liveactivity-handoff-2026-09-21.md`.

## Gate před fyzickým během

1. `swift test --package-path native/LazenskyCommander`
2. produkční `LazenskyCommanderApp` build
3. `LazenskyCommanderPhysicalAcceptance` build
4. `LazenskyCommanderWatchApp` build
5. `git diff --check`
6. kontrola, že `CommanderAlarmStopIntent` neobsahuje `Activity.request`
7. kontrola, že scheduled create cesta je pouze v `CommanderProcedureLiveActivityCoordinator`
8. simulator scheduled-start probe

Teprve potom má smysl jediný krátký fyzický důkaz. Opakované dlouhé běhy bez nové technické otázky nejsou součástí acceptance.

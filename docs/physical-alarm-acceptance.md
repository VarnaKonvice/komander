# Lokální fyzický self-test AlarmKitu

## Oddělení od produkce

Sdílené schéma `LazenskyCommanderPhysicalAcceptance` sestaví samostatnou aplikaci **Commander Test**:

- App: `com.varnakonvice.lazenskycommander.physicalacceptance`.
- Embedded extension: `com.varnakonvice.lazenskycommander.physicalacceptance.liveactivity`.
- Extension používá přesně stejné Swift soubory, metadata, ikony a systémový timer jako produkční `LazenskyCommanderLiveActivity`. Neexistuje testovací náhražka AlarmKitu ani ActivityKit UI.
- Testovací target nemá produkční `@main`, `CommanderViewModel`, WatchConnectivity ani Watch target. Nemá App Group entitlement.
- Produkční app zůstává nainstalovaná pod svým původním ID. Self-test její storage, preferences ani ownership neotevírá. Neobnovuje její provisioning.
- V režimu `physicalAcceptance` je zapnuté skutečné produkční chování procedure Live Activity. Remote E2E channel nadále svou procedure activity a Watch delivery vypíná; jeho konfigurace se nemění.
- Watch delivery je vypnuté a žádná Watch aplikace není podmínkou testu. Systémové předání zvuku na hodinky/sluchátka tím není nahrazeno vlastní Watch notifikací.

## Stav a namespaces

| Stav | Umístění |
| --- | --- |
| Run ID | Nové UUID při každém stisku tlačítka |
| stableId | `physicalAcceptance.<UUID>.meal` / `.procedure` |
| Canonical snapshot | Nový `InMemoryScheduleSnapshotStore` pro každý běh |
| Managed alarms | Nový `InMemoryAlarmStateStore` pro každý běh |
| Effective overrides | Nová prázdná `LeadTimeOverrides()`; žádná preferences storage |
| projectionRevision | `1` v rámci unikátního běhu |
| Persistent ownership | Suite `com.varnakonvice.lazenskycommander.physicalAcceptance.v1`, key `ownedPlatformAlarms.v1`: `AlarmKit ID -> run UUID` |
| Preflight/report | Paměť aktuálního běhu; export přes systémové Sdílet diagnostiku |

Production/e2e klíče `scheduleSnapshot.*.v1`, `leadTimePreferences.*.v1`, `managedAlarms.*.v1` a `lazensky.commander.alarmkitOwned.e2e.v1` se v self-testu nepoužívají. Není přidán žádný schedule/alarm JSON do repozitáře ani na GitHub.

Před dalším během se ruší pouze ID evidovaná v self-test ledgeru. Neevidované ID se **nikdy automaticky neruší** a zablokuje nový běh. Ownership rezervace se zapisuje před `AlarmManager.schedule`, aby pokryla i přerušené vytváření alarmu. Pokud OS ztratí zápis ledgeru, ochrana proti neevidovaným ID selže bezpečně do NOT READY, nikoli do plošného rušení. Nedokončený úklid brání novému plánování.

## Jedno tlačítko, lokální čas

Po potvrzení oprávnění a úklidu se zachytí `Date()` jako testovací `now`. Teprve tehdy vznikne lokální canonical Schedule. `T` je nejbližší celá minuta **nahoru** od `now`:

| Událost | Začátek | Konec | Lead time | leaveAt | Countdown |
| --- | --- | --- | --- | --- | --- |
| TEST – Jídlo | T+6 min | T+8 min | 2 min z event override | T+4 min | Okamžitý `schedule=nil`, zbývající čas do leaveAt |
| TEST – Magnetoterapie | T+13 min | T+15 min | 2 min z event override | T+11 min | `.fixed(T+8)` + `preAlert = 3 min`; AlarmKit vlastní celé volno od konce jídla do odchodu |

První alarm nastane přibližně za 4–5 minut, druhý za 11–12 minut. `CommanderProcedureLiveActivityCoordinator` předem připraví obě testovací Commander aktivity se scheduled starty v jejich `leaveAt` (T+4 a T+11). AlarmKit je jediný vlastník odchodového countdownu a alertu. Stisk **Stop** pouze ukončí AlarmKit alert a Commander aktivitu nemutuje; po Stop má už naplánovaný Commander kontext bez hluché mezery ukázat `Začíná za …` do skutečného startu T+6/T+13. V `startAt` se UI lokálně přepne na `Právě…` přes explicitní `TimelineView`. Budoucí ActivityKit start vyžaduje `AlertConfiguration`; test používá tichý zvuk `CommanderSilentAlert.wav`, ale iOS může systémový start alert vizuálně zobrazit. Generátor odmítne běh, jehož konec v T+15 by překročil půlnoc.

Všechny odchody a priority pocházejí z `NativeAlarmContract`. `resolvedLeadTime` vrací hodnotu a zdroj ve stejné prioritní cestě jako `effectiveLeadTime`; stejně velký local override tedy není zaměnitelný za hodnotu z rozpisu. Samotný self-test žádný lokální override nepřijímá.

## Preflight a hranice READY

Používá se existující canonical-first `CommanderScheduleSyncCoordinator`, `AlarmSyncService`, read-back, self-recovery, `projectionRevision` a fronta `CommanderSynchronizationRequestQueue`. Zdroj je lokální `ScheduleServing`, nikoli URLSession. Během úvodního preflightu jsou nejvýše tři sync pokusy a nejvýše dvacet sekund read-back čekání.

Před READY se nejdřív provede samostatný **Live Activity primer** mimo časovaný běh. Vytvoří krátkou okamžitou testovací aktivitu, aby případný první systémový dotaz `Povolit živé aktivity z aplikace Commander Test?` proběhl ještě před vytvořením časů ostrého testu. Teprve po vyřízení dialogu a následném potvrzení v Commander Testu smí vzniknout vlastní `PhysicalAcceptanceRun`.

Před READY jsou vyžadovány dvě unikátní, správně mapované skutečné AlarmKit ID, správná uložená délka countdownu, správné schedule/state a shoda výsledného fire time s canonical leaveAt v existující toleranci jedné sekundy. První alarm musí být okamžitý `.countdown` se `schedule=nil`; přesný endpoint se ověřuje z `fireDate`, případně z pozorovaného času konfigurace + `preAlert`, pokud iOS `fireDate` neposkytne. Druhý alarm musí být `.scheduled` s pevným začátkem countdownu T+8 a `preAlert = 3 min`, takže výsledný endpoint je canonical T+11. Raw `.fixed` datum se nikdy samostatně nepovažuje za leaveAt. Připravené musí být **obě** Commander aktivity pro události T+6 a T+13, se scheduled starty v T+4 a T+11, a ověřená reconciliation. Do prvního alarmu musí při READY zbývat alespoň minuta. Report po READY uchovává zvlášť historický počet Commander aktivit při READY a zvlášť aktuální počet; po skončení obou událostí je proto `aktuálně 0/2` očekávané a nesmí se zaměnit za neplatný původní preflight. Diagnostika ukládá časovou osu READY, AlarmKit snapshotů, ActivityKit stavů a všech zaznamenaných Stopů.

Obrazovka ukazuje run ID/now, stableId/title, hodnotu i zdroj předstihu, canonical leaveAt, očekávaný start a konec countdownu, platform ID, uložený preAlert/postAlert, fixed schedule, Alarm.state, dostupný systémový fireDate a expected/verified/actual počty.

Po READY už self-test alarmy neopravuje ani znovu neplánuje. Změny čte přes `alarmUpdates` a při návratu do foregroundu; žádný background síťový timer neběží. Preflight je označený časem svého ověření, aktuální read-back samostatně. iOS může aplikaci na zamčené obrazovce suspendovat, proto chybějící zachycený stav `alerting` není automatickým důkazem, že alarm nezazvonil.

NOT READY je **neplatná příprava testu**, ne automatický závěr o nefunkčnosti AlarmKitu. Alarmy po neúspěšném preflightu mohou existovat; další stisk tlačítka uklidí předchozí evidovaný běh před vytvořením nového.

## Jediný fyzický postup pro Petra

1. Nainstalovat podepsaný target `LazenskyCommanderPhysicalAcceptance` se zabalenou `LazenskyCommanderPhysicalLiveActivity`. Běžný produkční obnovovací launcher tento target neinstaluje. Podepisuje se obojí stejným Personal Teamem; Watch target se nebuildí ani neinstaluje.
2. Otevřít **Commander Test**. Nejprve stisknout **Připravit Live Activities**, vyřídit případný systémový dialog `Povolit / Nepovolovat` a potom stisknout **Potvrdit povolení a spustit test**. Případné povolení AlarmKitu se vyřídí ještě v úvodní přípravě. Teprve potom vyčkat na **READY / 2 ze 2** a přečíst zobrazené časy.
3. Zamknout iPhone a sledovat celý jediný běh (asi 15–16 minut). U obou odchodů zastavit skutečné zvonění systémovým ovládáním. Aplikaci během běhu není potřeba znovu otevírat ani synchronizovat.

| Čas | Co fyzicky pozorovat na Lock Screen / Dynamic Island |
| --- | --- |
| Do T+4 | AlarmKit odpočet do prvního odchodu |
| T+4 | Skutečný AlarmKit alarm a `VYRAZIT TEĎ` |
| Po Stop do T+6 | Alarm je zastaven; Commander musí bez hluché mezery ukázat `ZAČÍNÁ ZA` pro jídlo. **Nesmí vzniknout červený handoff.** |
| T+6 až T+8 | Tatáž Commander prezentace se přepne na `PRÁVĚ JÍDLO`, s odpočtem do konce |
| T+8 až T+11 | AlarmKit přebírá další odchodový countdown od T+8 do T+11; skončená Commander aktivita jídla nesmí vlastnit volno |
| T+11 | Druhý skutečný AlarmKit alarm a `VYRAZIT TEĎ` |
| Po Stop do T+13 | Alarm je zastaven; Commander musí bez hluché mezery ukázat `ZAČÍNÁ ZA` pro magnetoterapii. Žádný červený handoff. |
| T+13 až T+15 | Tatáž Commander prezentace se přepne na `PRÁVĚ PROBÍHÁ` pro magnetoterapii, s odpočtem do konce |
| Po T+15 | Commander aktivita musí přejít do systémového `stale` stavu a zobrazit `Skončilo`; nesmí dál odpočítávat jako probíhající. Okamžité odstranění karty není v lokální Personal Team variantě garantováno. |

Pokud předchozí Commander aktivita zůstává `.stale` ve chvíli další události, správnost nesmí stát jen na systémovém pořadí podle `relevanceScore`. Novější položka rolling window má vyšší score, ale stará karta současně nese embedded `nextEvent` a po `endAt` se musí sama přepnout na stejný relevantní následující program. Na Watch tedy stará stale karta nesmí jako jediný kontext dál ukazovat skončené jídlo.

**PASS:** platný READY preflight, oba skutečné systémové alarmy zazvoní ve zobrazených `leaveAt` časech, po Stop není hluchá mezera ani červený handoff, Commander ukazuje `Začíná za …`, v `startAt` se přepne na `Právě…` a v `endAt` na další událost / `Skončilo` místo dalšího odpočtu. Slyšitelný alarm ani reálnou viditelnost UI nelze potvrdit jen úspěšným SDK read-backem. Výsledek zaznamenat spolu s commit SHA, iOS verzí a modelem iPhonu; při problému sdílet diagnostiku. Jde o jediný závěrečný acceptance běh, nikoli požadavek opakovat dříve ověřené mezikroky.

Tato izolovaná aplikace neprokazuje doručení Watch notifikace, WatchConnectivity na párovaných zařízeních, Personal Team obnovu produkčního profilu ani přístupnost všech produkčních obrazovek. Tyto hranice se nesmějí skrýt za její PASS.

Stejně tak tento dvouudálostní acceptance **neprokazuje celodenní refill Commander Live Activities**. Produkční coordinator lokálně drží rolling window nejvýše dvou neskončených aktivit. Pokud aplikace po jejich přípravě zůstane suspendovaná, není lokálně garantováno, že se po uvolnění systémového slotu připraví třetí a další událost. Při příštím foregroundu se rolling window doplní z posledního validního rozpisu ještě před síťovým throttlem. PASS tohoto testu tedy potvrzuje pouze dvě předem připravené události, ne celý den s více než dvěma procedurami/jídly. Tento limit je vědomě přijatý pro bezplatný Personal Team provoz.

**FAIL:** po platném READY některý alarm nezazvoní, zazvoní posunutě nebo očekávaná Live Activity/Dynamic Island chybí či odpočítává jinam. Zaznamenat skutečný čas a sdílet diagnostiku. Aplikace sama nikdy nevydá automatický fyzický PASS.

## Build bez instalace

```sh
xcodebuild -project native/LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj \
  -scheme LazenskyCommanderPhysicalAcceptance -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/commander-physical-acceptance \
  CODE_SIGNING_ALLOWED=NO build
```

Unsigned generic build prokazuje kompilaci a embed extension, nikoli Personal Team provisioning ani fyzický výsledek. V tomto balíku se nic neinstaluje, nepublikuje a nemění se žádný testovací či produkční feed.

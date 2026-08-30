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
| TEST – Snídaně | T+3 min | T+4 min | 1 min ze schedule meal override | T+2 min | Okamžitý `schedule=nil`, zbývající čas do leaveAt |
| TEST – Magnetoterapie | T+6 min | T+7 min | 1 min z event override | T+5 min | `.fixed(T+4 min)` + `preAlert=60 s` |

První alarm nastane za 2–3 minuty, druhý za 5–6 minut. Skutečná procedure Live Activity je připravená na start procedury za 6–7 minut. Její případné oznámení „Procedura začíná“ **není** odchodový AlarmKit alarm. V sedmiminutovém okně před půlnocí generátor odmítne běh, aby neměnil canonical schéma na události přes půlnoc.

Všechny odchody a priority pocházejí z `NativeAlarmContract`. `resolvedLeadTime` vrací hodnotu a zdroj ve stejné prioritní cestě jako `effectiveLeadTime`; stejně velký local override tedy není zaměnitelný za hodnotu z rozpisu. Samotný self-test žádný lokální override nepřijímá.

## Preflight a hranice READY

Používá se existující canonical-first `CommanderScheduleSyncCoordinator`, `AlarmSyncService`, read-back, self-recovery, `projectionRevision` a fronta `CommanderSynchronizationRequestQueue`. Zdroj je lokální `ScheduleServing`, nikoli URLSession. Během úvodního preflightu jsou nejvýše tři sync pokusy a nejvýše dvacet sekund read-back čekání.

Před READY jsou vyžadovány dvě unikátní, správně mapované skutečné AlarmKit ID, správná uložená délka countdownu, správné schedule/state a shoda výsledného fire time s canonical leaveAt v existující toleranci jedné sekundy. Okamžitý alarm musí být `.countdown` a mít dostupný systémový `fireDate`; budoucí alarm musí být `.scheduled` s očekávaným fixed začátkem a 60s preAlert. Raw `.fixed` datum se nikdy samostatně nepovažuje za leaveAt. Připravená procedure Live Activity a ověřená reconciliation jsou také povinné. Do prvního alarmu musí při READY zbývat alespoň minuta.

Obrazovka ukazuje run ID/now, stableId/title, hodnotu i zdroj předstihu, canonical leaveAt, očekávaný start a konec countdownu, platform ID, uložený preAlert/postAlert, fixed schedule, Alarm.state, dostupný systémový fireDate a expected/verified/actual počty.

Po READY už self-test alarmy neopravuje ani znovu neplánuje. Změny čte přes `alarmUpdates` a při návratu do foregroundu; žádný background síťový timer neběží. Preflight je označený časem svého ověření, aktuální read-back samostatně. iOS může aplikaci na zamčené obrazovce suspendovat, proto chybějící zachycený stav `alerting` není automatickým důkazem, že alarm nezazvonil.

NOT READY je **neplatná příprava testu**, ne automatický závěr o nefunkčnosti AlarmKitu. Alarmy po neúspěšném preflightu mohou existovat; další stisk tlačítka uklidí předchozí evidovaný běh před vytvořením nového.

## Jediný fyzický postup pro Petra

1. Nainstalovat podepsaný target `LazenskyCommanderPhysicalAcceptance` se zabalenou `LazenskyCommanderPhysicalLiveActivity`. Běžný produkční obnovovací launcher tento target neinstaluje. Podepisuje se obojí stejným Personal Teamem; Watch target se nebuildí ani neinstaluje.
2. Otevřít **Commander Test**, stisknout **Spustit fyzický test**. Při prvním spuštění potvrdit systémové povolení AlarmKitu; Živé aktivity musí být povolené pro tuto novou aplikaci. Vyčkat na **READY / 2 ze 2** a přečíst zobrazené časy.
3. Zamknout iPhone. Pozorovat Lock Screen a Dynamic Island, první alarm zastavit systémovým ovládáním a vyčkat na druhý. Žádný GitHub publish, ruční přepínání feedu ani další synchronizace nejsou potřeba.

**PASS:** platný READY preflight, oba skutečné systémové alarmy „Čas vyrazit: TEST …“ zazvoní ve zobrazených leaveAt časech, oba countdowny na Lock Screen/Dynamic Island končí zároveň s příslušným alarmem; procedure Live Activity se při začátku procedury také zobrazí. Slyšitelný alarm ani reálnou viditelnost UI nelze potvrdit jen úspěšným SDK read-backem.

**FAIL:** po platném READY některý alarm nezazvoní, zazvoní posunutě nebo očekávaná Live Activity/Dynamic Island chybí či odpočítává jinam. Zaznamenat skutečný čas a sdílet diagnostiku. Aplikace sama nikdy nevydá automatický fyzický PASS.

## Build bez instalace

```sh
xcodebuild -project native/LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj \
  -scheme LazenskyCommanderPhysicalAcceptance -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/commander-physical-acceptance \
  CODE_SIGNING_ALLOWED=NO build
```

Unsigned generic build prokazuje kompilaci a embed extension, nikoli Personal Team provisioning ani fyzický výsledek. V tomto balíku se nic neinstaluje, nepublikuje a nemění se žádný testovací či produkční feed.

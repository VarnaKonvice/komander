# Nativní stabilizace – aktuální kontrakt

Větev: `lc/alarm-liveactivity-unification-v1`.

Tento soubor popisuje pouze současnou podporovanou architekturu. Historie fyzických běhů, neúspěšných handoff variant a důvody jednotlivých změn jsou archivované v docs/archive/liveactivity-stabilization-history-2026-09.md.

## Jediný podporovaný lifecycle

1. Canonical rozpis určuje leaveAt, startAt a endAt.
2. AlarmKit vlastní odchodový countdown, zvonění a tlačítko Stop.
3. Foreground/bootstrap reconciliation připraví nejvýše jednu Commander Live Activity ještě před Stopem. Pokud je první relevantní povinná procedura v budoucnu, používá ActivityKit scheduled start v jejím canonical leaveAt.
4. Stop intent nikdy nezakládá Commander Live Activity z backgroundu; pouze zastavuje systémový AlarmKit alarm.
5. ContentState drží omezenou chronologickou frontu neskončených událostí uvnitř jednoho maximálně 7 h 50 min okna.
6. Tatáž Commander karta se podle času lokálně přepíná:
   - před startAt: Následuje,
   - od startAt do endAt: Právě probíhá,
   - po endAt: přechod na další položku nebo Skončilo.
7. Stavové zvýraznění se mění uvnitř téže karty. Upcoming používá jantarové zvýraznění, aktivní stav barvu daného typu události a skončený stav neutrální zvýraznění.
8. Při překryvu zůstává hlavní dříve zahájená stále probíhající událost. Druhá se zobrazí jako Současně; po konci první převezme hlavní pozici.
9. Foreground reconciliation aktualizuje existujícího keepera, odstraní historické duplicity a pokud žádná aktivita neexistuje, smí naplánovat právě jednu novou instanci.
10. V produkci je invariant: **nejvýše jedna vlastní Commander Live Activity současně**.

## AlarmKit a Commander

AlarmKit a Commander jsou technicky dvě různé ActivityKit prezentace. AlarmKit je systémový vlastník countdownu a alertu; Commander je vlastní dlouho žijící karta aplikace. Vizuálně mají navazovat bez hluché mezery, ale nesmí se modelovat jako série několika Commander ActivityKit instancí.

Jediným produkčním místem, které smí zavolat `Activity<CommanderProcedureLiveActivityAttributes>.request`, je `CommanderProcedureLiveActivityCoordinator` během foreground/bootstrap reconciliation. Budoucí aktivace používá scheduled start a tichý `CommanderSilentAlert.wav`, aby nevznikl druhý zvuk vedle AlarmKitu. `CommanderAlarmStopIntent` nesmí obsahovat `Activity.request` ani vytvářet Commander aktivitu z backgroundu. Physical acceptance target má vlastní izolovaný primer pro ověření systémového povolení Live Activities.

## Fronta událostí

CommanderProcedureLiveActivityAttributes.ContentState nese:
- scheduleVersion,
- projectionRevision,
- omezenou frontu events.

Fronta má hard cap šest položek a před zápisem se zkracuje podle skutečné JSON velikosti tak, aby statická a dynamická data měla rezervu pod limitem ActivityKit payloadu.

Časové hranice všech položek se předávají do explicitního TimelineView, takže přechody Začíná za → Právě… → další nejsou závislé na spuštění aplikace přesně v danou sekundu.

## Překryvy

Pokud událost B začne dřív, než skončí událost A:
- A zůstává hlavní, dokud skutečně neskončí;
- B se zobrazuje jako Současně;
- v endAt A se stejná Live Activity přepne na B;
- žádná další Commander Live Activity kvůli překryvu nevzniká.

## Reconciliation a cleanup

CommanderProcedureLiveActivityCoordinator:
- je serializovaný přes vlastní reconciliation queue,
- drží maximumConcurrentActivities = 1,
- aktualizuje jediného keepera,
- případné další historické Commander aktivity ukončí,
- pokud žádná Commander aktivita neexistuje a existuje ještě relevantní povinná procedura, naplánuje jedinou novou instanci v canonical `leaveAt` této procedury,
- používá čistý `CommanderLiveActivityPlan`, který vybírá kotevní proceduru a frontu v rámci 7 h 50 min životnostního rozpočtu.

Tím je jediným bodem vzniku Commander aktivity serializovaný foreground/scheduled coordinator a nevzniká konkurenční background create cesta ze Stop intentu.

## Co bylo odstraněno

Z produkčního app targetu byly odstraněny alternativní DEBUG cesty, které samy vytvářely Commander Live Activities:
- AlarmFreeVisualActivityReconciler,
- overlap visual harness,
- CommanderRuntime.alarmFreeVisualTest,
- příslušné launch argumenty a samostatný visual-test scheme.

Pro fyzickou validaci zůstává jen oddělený Commander Test / Physical Acceptance target. Ten není součástí produkčního runtime.

## Fyzický acceptance

Physical Acceptance ověřuje dvě AlarmKit události a před READY navíc vyžaduje skutečně pending/active naplánovanou Commander Live Activity. Stop už není handoff create bod. READY není fyzický PASS. PASS vyžaduje skutečné chování na zařízení.

Podrobnosti jsou v docs/physical-alarm-acceptance.md.

## Systémové limity

- AlarmKit zůstává celodenní garantovanou upozorňovací vrstvou.
- Jedna konkrétní Live Activity má systémově omezenou životnost; Commander proto používá maximálně 7 h 50 min plánovací okno od canonical `leaveAt` kotevní procedury. Pozdější Stop náhradní instanci nezakládá.
- staleDate není přesný future end scheduler; fázové UI proto používá časové hranice v TimelineView.
- Bez push/background wake není garantováno, že vzdálená změna canonical feedu probudí dlouhodobě suspendovanou aplikaci.

## Gate před dalším fyzickým během

Před dalším fyzickým acceptance musí projít:
1. celý Swift test suite,
2. produkční iOS build,
3. Live Activity extension build,
4. Physical Acceptance build,
5. Watch build,
6. git diff --check,
7. statická kontrola, že produkční Commander create cesta existuje jen v serializovaném coordinatoru a Stop intent neobsahuje `Activity.request`.

Žádný fyzický test není nutný pro samotné uklizení architektury.

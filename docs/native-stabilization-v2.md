# Stabilizační průchod nativní aplikace – září 2026

Pracovní větev: `lc/native-stabilization-v2`. Výchozí schválený stav je `d64fcac3dfffb0efb83698af4cde2e98976a63a9` (`guard verified red alarm handoff`). Průchod začal commity `516eecf` a `eea8a33`; navazující běh nejprve přečetl jejich diff a opravil chybějící platformní kontrakt. `main` a `lc/native-design-v1` se nemění.

Tento dokument je registr rozhodnutí a mezí důkazů. Automatické testy nejsou fyzický PASS. Historický designový checkpoint `05d83b6` na `lc/native-design-v1-lockscreen-approved` ani schválení uživatele se tímto průchodem nenahrazují. Produkční zdroj `LazenskyCommanderLiveActivity.swift`, jeho geometrie, ikony a barvy nebyly redesignovány.

## Platformní kontrakt a původní build blocker

Package používá Swift tools 6.2; iPhone a Watch zůstávají na `.iOS(.v26)` a `.watchOS(.v26)`. `.macOS(.v13)` explicitně vyjadřuje vývojový runtime pro Swift Testing a `LazenskyCommanderCoreCheck`, nikoli novou distribuovanou macOS aplikaci. Xcode app má vlastní deployment nastavení. Linux prostředí tohoto Work běhu nemá Swift ani Xcode, proto se skutečné testy a Apple buildy provádějí na macOS runneru GitHub Actions.

Původní deklarace pouze iOS/watchOS nezakazovala macOS build; ponechávala implicitní staré minimum. Proto nové použití `Task` selhalo. Zvýšit jen dostupnost konkrétní FIFO fronty na 10.15 by nevyjádřilo kontrakt celého balíčku, který obsahuje také async URLSession a současný testovací runtime. Reference: [SwiftPM SupportedPlatform](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html), [Swift platform support](https://swift.org/platform-support/), [URLSession async API](https://developer.apple.com/documentation/foundation/urlsession/data%28for%3Adelegate%3A%29).

Integrační build následně odhalil dvě nepřístupná API: konstruktor `WatchNotificationPlan()` a továrnu `NativeAlarmContract.alarm`. Jsou nyní public. `PublicIntegrationContractTests.swift` je záměrně bez `@testable import`; behaviorální fixture testy stále používají interní memberwise inicializátory. Jde o kontrolu veřejného API, nikoli náhražku integračního buildu.

## Vlastnictví dat a vedlejších účinků

| Oblast | Vlastník a zdroj pravdy | Důležité omezení |
| --- | --- | --- |
| Canonical rozpis | `CommanderScheduleSyncCoordinator` → validovaný `ScheduleSnapshotStoring`; produkční feed `data/schedule.json` | Lokální předstihy nikdy nepřepisují canonical feed |
| Čerstvost | scheduleVersion + shoda obsahu; samostatná projectionRevision pro lokální předstihy | Stejná verze s jiným canonical obsahem není aktualizace |
| Persistence iPhonu | Actor `UserDefaultsScheduleSnapshotStore`, samostatné namespace pro kanály; alarm mapping zvlášť | Neplatná cache se nesmí tvářit jako platný nový rozpis |
| Odvozené časy | `NativeAlarmContract` a `AlarmCountdown` | Fixed začátek countdownu není čas zazvonění |
| AlarmKit zápisy | `AlarmSyncService` a jeden `AlarmKitAdapter`, volané přes app request queue | Actor sám nebrání prokládání přes await; nepřidávat druhého souběžného volajícího |
| Alarm metadata | Persistovaný `AlarmPresentationContext` | Závisí také na sousední události a vlastníkovi volna, nikoli jen vlastním leaveAt |
| Červený Stop handoff | `CommanderAlarmStopIntent`, sdílené rozhodnutí `CommanderLiveActivityHandoff` | První událost může ponechat AlarmKit kartu; další využije existující kartu volna |
| Zelená / volno | Jeden společný tvůrce `CommanderRollingLiveActivity.scheduleRunning` na MainActor, ActivityKit start/staleDate | O výsledném zobrazení na zamčeném telefonu rozhoduje OS |
| Dnes a Týden | Stejný Schedule + overrides + core presentation; TimelineView | Týden má nyní pravidelnou minutovou aktualizaci fází |
| Watch data | WCSession → validovaný atomický soubor v App Group | ACK potvrzuje snapshot identitu, nikoli zvuk nebo zobrazení notifikace |
| Watch notifikace | `WatchCommanderModel` → `WatchLocalNotificationService` → FIFO celé async operace | Cache callback pouze invaliduje widget; žádný skrytý paralelní zápis |
| Watch UI / widget | Stejný core live-state a `WatchScheduleExpiryPolicy` | Expirace po poslední události + 24 h, cache se kvůli zobrazení nemaže |
| Provisioning reminder | Samostatný renewal coordinator + skutečný embedded profil | Otevření aplikace není obnova podpisu; due reminder zůstává doručený |
| iPhone záložní notifikace | Existující recovery řízená výsledkem AlarmKit verification | Watch chyby ani Live Activity chyby samy nezapínají zálohu |
| Fyzický acceptance | Izolovaný bundle, lokální Schedule, vlastní run ledger, reálný adapter a extension | READY je preflight; nikdy automatický fyzický PASS |

## Skutečné příčiny křehkosti a opravy

1. **Duplicitní časové rozhodování a tvorba aktivit.** Stop intent, reconciliation a acceptance měly různé výpočty handoffu. Sdílená core policy chrání přesné hranice; obě cesty tvorby zelené aktivity používají jedinou implementaci. Ověřené ActivityKit end/dismissal volání zůstává zachované.
2. **Cleanup považoval viditelnou ukončenou kartu za nepotřebnou.** `.end(.after(startAt))` může být stále červeně viditelná. Reconciliation zachová odpovídající canonical bridge do startu a ukončí neplatný. Staré volno nesmí potlačit zelený stav po začátku další události.
3. **Alarm se porovnával bez závislostí prezentace.** Posunutí následující procedury nemusí změnit předchozí NativeAlarm, přesto zneplatní jeho Stop intent. Persistovaný presentation context vyvolá správnou obnovu. Starý záznam migruje právě jednou; zvýšení samotné scheduleVersion nezpůsobuje churn.
4. **Potlačená chyba cancel ztrácela vlastnictví.** Před i po zápisu nyní selhání rušení ponechá mapování a zabrání vytvoření náhrady. Retry se opře o skutečný read-back.
5. **Future-only cleanup mohl při foregroundu zastavit právě zvonící alarm.** Skutečně alerting, nezměněná a dosud neskončená canonical událost je chráněna. Odstraněná/změněná/ukončená událost chráněna není; zastavený minulý alarm se znovu netvoří.
6. **Acceptance snapshotu obsahovala async mezeru mezi load a save.** Oba produkčně používané snapshot store actory implementují compare/accept/save bez await. Watch cache validuje i local projection a odmítá změněný canonical obsah při stejné verzi.
7. **Watch actor umožňoval překryv celých notifikačních operací.** FIFO serializuje i jejich await. Druhý vlastník v cache callbacku byl odstraněn. Read-back ověřuje skutečný čas triggeru, text a zvuk; metadata sama nejsou důkaz. Opětovné přijetí stejného snapshotu také opakuje neúspěšný zápis a publikuje chybu.
8. **Recovery čekala na síť a používala starý čas.** Foreground/bootstrap nejprve obnoví lokální projekce z validní cache. Síťová synchronizace zachytí čas až po přijetí rozpisu. Adapter nepřijme nové plánování po deadline; Watch fronta zachytí výchozí čas při provádění operace.
9. **Chyba ActivityKit request byla tichá.** Chyba přípravy se nyní vrací do diagnostiky aplikace; Stop intent ji zapisuje do systémového logu a fyzického test reportu. Nezaměňuje se za selhání AlarmKitu a nezapíná další notifikační větev.
10. **Dokumentovaný fyzický postup byl zastaralý.** Popisoval sedm minut a druhý preAlert, zatímco schválená implementace používá patnáctiminutový tok a jednoho vlastníka volna. Acceptance návod nyní odpovídá skutečnému generátoru a explicitně kontroluje červenou po obou Stop.

## Registr schválených invariantů a důkazů

„Behaviorální“ níže znamená provedení produkčního core kódu s deterministickými časy či testovacím systémovým adaptérem. Neznamená simulaci skutečného iOS rendereru. Původní strukturální testy nejsou vydávány za behaviorální důkaz.

| Invariant | Automatická ochrana | Co automatika neprokazuje |
| --- | --- | --- |
| Před odchodem odpočet / volno; na leaveAt červená; na start zelená | `entireAlarmFlowAgreesAcrossDashboardWatchAndCanonicalBoundaries`, `AlarmCountdownPlanTests`, dashboard testy | Reálný zvuk a systémové překreslení v suspendované aplikaci |
| Stop zachová červenou přesně do startu | `stopDecisionPreservesRedUntilExactStartWithAndWithoutExistingCard`, `foregroundCleanupRetainsEndedRedCardOnlyForCurrentCanonicalDeparture` | ActivityKit viditelnost po `.end(.after)` |
| Volno nesmí potlačit zelenou ani přeskočit mezilehlou událost | `freeTimeOwnerCannotSuppressGreenActivityAtNextStart`, `sharedHandoffSelectionRejectsSkippedAndCrossDaySources` | Pořadí systémových UI aktualizací |
| Schválené konkrétní SDK handoff a vzhled zůstávají | Ponechaný `AlarmRedHandoffRegressionTests`, diff nezměněné Live Activity view, embedded extension build | Textový guard nekontroluje pixely; fyzický design PASS je oddělený |
| Nezměněné alarmy se nevytvářejí znovu, sousední změna invaliduje závislosti | `neighbourChangeRefreshesStopIntentWithoutChangingOwnAlarmDeadline`, `legacyAlarmPersistenceMigratesContextOnceWithoutChangingCanonicalPayload` | AlarmKit implementaci Stop intentu na zařízení |
| Selhání cancel nesmí vytvořit druhý AlarmKit alarm | `failedCancellationBeforeRepairKeepsManagedIDAndNeverCreatesDuplicate`, `failedCancellationDuringPostWriteRepairKeepsNewIDForSafeRetry` | OS výpadek během trvalého zápisu nebo externí zásah |
| Foreground není Stop; zastavený minulý alarm se netvoří znovu | `foregroundReconciliationDoesNotSilenceRingingCanonicalAlarmOrRecreateStoppedAlarm`, `ringingProtectionDoesNotKeepRemovedOrFinishedCanonicalEvents` | Přesný okamžik změny `.alerting` v OS |
| Pomalá síť nesmí plánovat právě prošlý odchod | `slowFetchUsesAcceptanceTimeAndCannotRecreateAnAlarmWhoseDepartureJustPassed` | Latenci uvnitř samotného SDK schedule volání |
| Starší/neplatný snapshot nesmí přepsat nový platný | `concurrentCanonicalAcceptanceNeverRollsBackNewestVersion`, `persistedCanonicalAcceptanceSurvivesRestartAndRejectsConflictingVersion`, `StabilityPassTests` | Tvrdý pád OS při flush UserDefaults |
| Watch projectionRevision nemění canonical obsah | `sameVersionWatchRevisionCannotSmuggleCanonicalChanges`, `watchDiskCacheRejectsInvalidLocalProjectionAndKeepsLastValidBytes`, `WatchAcknowledgementTests` | Doručení WCSession na reálném páru |
| Watch notifikační operace se nepřekrývají a chyba nezablokuje další | `asynchronousNotificationOperationsNeverOverlapAndFailureDoesNotBlockNext` + Watch build | Test fronty není integrační test UNUserNotificationCenter |
| Watch read-back ověřuje skutečný požadavek, stejný payload umí opravu | `watchReadbackChecksActualTriggerAndContentInsteadOfTrustingMetadata`, `sameWatchPayloadRepairsInvalidRequestAndRetryStopsOnlyAfterReadbackMatches` | Fyzickou haptiku, Focus a systémové routování zvuku |
| Watch app a widget mají stejnou expiraci | `watchAppAndWidgetUseSameExpiryBoundaryWithoutDiscardingPersistedSchedule`, původní Watch timeline testy | WidgetKit rozpočet aktualizací na zařízení |
| Due provisioning reminder přežije otevření aplikace | `dueProfileKeepsAlreadyDeliveredProvisioningReminder`, `expiredDueAndUnavailableProfilesDoNotRepeatedlyArmPastReminders` | Platný podpis distribuované aplikace |
| Reminder se smí přesunout až podle skutečného profilu; cizí notifikace zůstávají | `sameProfileNeverMovesDeadlineToTodayPlusSixOrDuplicatesReminder`, renewal/readback/DST/overlap testy | CMS test skutečného profilu vyžaduje `LC_TEST_EMBEDDED_PROFILE`; běžné CI jej neposkytuje |
| Selhání AlarmKit/Watch nesmí rollbackovat canonical rozpis | `StabilityPassTests`, `StabilityClosureTests`, Watch ACK testy | Nepřetržitou konektivitu |
| Lokální změna předstihu nevyžaduje síť a invaliduje všechny projekce | `LeadTimeTypeSettingsTests`, cached projection testy v `StabilityClosureTests` | Rychlost doručení Watch projection |
| Acceptance je izolovaná, používá reálný kontrakt a nevydává falešné READY | `PhysicalAcceptanceTests`: cleanup, matching records, wrong fixed/preAlert, missing fireDate, slow preparation, shared target sources | Fyzický PASS ani produkční provisioning |
| Dnes / Týden / Nastavení používají společnou prioritu a stav | `CommanderDashboardPresentationTests`, `CommanderSchedulePresentationTests`, `CommanderDaySummaryTests`, lead-time tests | VoiceOver, největší Dynamic Type, malý displej |

## Dokončené posouzení a omezení

Prostudovány byly oba původní stabilizační commity a související historie červeného handoffu/countdownu; core schedule, alarm sync, persistence, ActivityKit adapter a extension, app recovery/fronta, Watch cache/transport/widget/notifikace, provisioning coordinator a jeho testy, fyzický acceptance a hlavní obrazovky. Existující funkční cesty nebyly přepisovány jen kvůli stylu.

UI změny jsou omezené: živé fáze v Týdnu, stejná expirace Watch app/widget, přesnější počet připravovaných aktivit v acceptance a zobrazení skutečné ActivityKit chyby v diagnostice. Čitelnost, hierarchie a sdílené barevné/ikonové podklady byly posouzeny ve zdrojích. Nový vizuální render ani zařízení nejsou v tomto běhu dostupné; vizuální přístupnost se neoznačuje za ověřenou.

Zbývající hranice a rizika:

- Žádný nový fyzický iPhone ani Watch test v tomto Work běhu neproběhl. Jediný závěrečný [acceptance postup](physical-alarm-acceptance.md) chrání oba způsoby červeného Stop handoffu v celé časové posloupnosti.
- Generic unsigned build neověří podpis, App Group entitlement při instalaci ani doručení na hodinky. Skutečný profil a reálné Watch doručení jsou samostatné fyzické důkazy; izolovaný iPhone acceptance je nenahrazuje.
- Aktualizace vzdáleného rozpisu při trvale suspendované aplikaci nemá BGTask/APNs fetch garanci. Již naplánované systémové alarmy a aktivity běží v OS; nový canonical rozpis se zpracuje při existujícím foreground/manual recovery. Nebyla přidána falešná background garance.
- Recovery zachovává existující iPhone záložní notifikace při neověřeném AlarmKitu. Při nejistém stavu platformy mohou souběžně existovat s neověřeným systémovým alarmem. Oprava cancel zabraňuje druhému **AlarmKit** ID; netvrdí obecnou exactly-once garanci zvuku přes všechny systémové kanály.
- Race mezi načtením systémového stavu a jeho pozdější změnou nelze odstranit samotným mock testem. Obzvlášť `.alerting`, Stop intent v jiném procesu a ActivityKit limity závisejí na iOS. Chyby přípravy jsou nyní pozorovatelné a další foreground znovu reconciliuje.
- Atomické snapshot acceptance je zaručeno uvnitř jednoho používaného store actoru. Výchozí protokolová implementace load/await/save pro externí vlastní store sama takovou záruku nemá; nová produkční implementace musí dodat vlastní atomický accept. Totéž platí pro nepřidávání druhého koordinátora systémových zápisů mimo současnou request queue.
- VoiceOver, největší Dynamic Type, malé displeje a případné truncation vyžadují zařízení nebo UI test runner. Nebyl proveden samoúčelný redesign ani prohlášení o úplném accessibility auditu.

## Ověřovací gate a pokračování

Konečný kód musí projít workflow **Native stability tests**: `swift test --package-path native/LazenskyCommander`, generic iPhone build včetně embedded extensions, `LazenskyCommanderPhysicalAcceptance`, `LazenskyCommanderWatchApp`. **Public schedule tests** chrání také schedule/assets/calendar/auth/launcher mimo native část. Historické červené běhy zůstávají v Actions jako důkaz odhalených chyb; nenahrazují zelený běh konečného kódu.

Přesný konečný SHA, počty skutečně úspěšných testů, odkazy na dokončené Actions a stav pracovního stromu patří do závěrečného předávacího reportu v chatu. Tento registr sám neoznačuje dosud běžící build za úspěšný.

Po zeleném finálním CI je větev kandidátem pro jediný závěrečný fyzický acceptance. Do té doby nezaměňovat připravenost ke code review za uzavřený fyzický PASS. Po zaznamenaném PASS lze začlenit do `lc/native-design-v1`; žádný merge ani přesun této větve tento průchod neprovádí.

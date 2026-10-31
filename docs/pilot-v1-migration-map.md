# Pilot v1 – migrační mapa současného iOS Commanderu

Tento dokument neříká „smazat starý kód“. Říká, kam patří odpovědnost při vzniku pilotní aplikace.

## A. Zachovat jako doménové jádro

| Současný soubor | Budoucí odpovědnost | Akce |
|---|---|---|
| Models.swift | Domain/Models | rozdělit po typech |
| AlarmContract.swift | Domain/Projection/AlertPlan | zachovat jeden výpočet leaveAt |
| CommanderScheduleProjection.swift | Domain/Projection | zachovat |
| LiveState.swift | Domain/Projection/TodayState | zachovat a přejmenovat bez vazby na Live Activity |
| ScheduleSnapshotStore.swift | Data/LocalStore | zachovat kontrakt |
| ScheduleService.swift | Data/RemoteDataSource | oddělit od konkrétní URL |
| CommanderScheduleSourceRevision.swift | Domain/Validation/Audit | zachovat |
| CommanderScheduleSourceLedger.swift | Support/Audit | zachovat |
| LeadTimePreferences.swift | Domain/UserPreferences | zjednodušit pilotní UI |

## B. Zachovat logiku, oddělit platformu

| Současný soubor | Budoucí modul | Poznámka |
|---|---|---|
| AlarmSyncService.swift | CommanderAlerts | nesmí importovat AlarmKit |
| AlarmAdapter.swift | CommanderAlerts | obecný scheduler interface |
| AlarmPersistence.swift | CommanderAlerts/Persistence | auditovatelná ownership data |
| Reconciliation.swift | CommanderAlerts | čistá doména |
| SynchronizationRequestQueue.swift | CommanderData/AppSync | orchestrace mimo UI |
| ScheduleSyncCoordinator.swift | CommanderData/AppSync | odstranit Watch delivery z pilotního toku |
| CommanderNotifications.swift | CommanderAlerts | oddělit fallback notification scheduler |

## C. iOS 26+ adaptér

Tyto věci jsou platformní a nesmí protéct do obecného jádra:
- AlarmKitAdapter.swift
- CommanderAlarmMetadata.swift

Cíl:
```
AlertScheduler
  |- AlarmKitAlertScheduler       // iOS 26+
  |- LocalNotificationScheduler   // kompatibilní režim
```

Výběr scheduleru provádí composition root podle verze systému a oprávnění.

## D. Nezapojovat do pilotního targetu

Kód a testy zůstávají v repozitáři.

### Watch
- IPhoneWatchConnectivityCoordinator.swift
- WatchContracts.swift
- WatchScheduleTransport.swift
- WatchScheduleCache.swift
- WatchLocalNotifications.swift
- WatchAcceptanceProbe.swift
- LazenskyCommanderWatchApp/*
- LazenskyCommanderWatchWidget/*

### Live Activity / widgety
- CommanderProcedureLiveActivityCoordinator.swift
- CommanderLiveActivityPlan.swift
- CommanderLiveActivityTimeline.swift
- CommanderActivityPresentation.swift
- LazenskyCommanderLiveActivity/*
- CommanderPhoneWidgetTimeline.swift

### Personal-Team provoz
- CommanderProvisioningRenewal.swift
- ProvisioningProfile.swift
- ProvisioningReminder.swift

### Fyzické testovací utility
- PhysicalAcceptance/*
- CommanderAcceptanceSchedule.swift
- CommanderVisualReviewSchedule.swift
- CommanderWidgetDemoSchedule.swift

Tyto skupiny mají zůstat jako volitelné/legacy capability, nikoli být importované pilotním AppCompositionRoot.

## E. Rozseknutí dnešního CommanderViewModel

Současný CommanderViewModel dnes obsahuje současně:
- schedule cache,
- remote fetch,
- alarm permission,
- alarm sync,
- Watch transport,
- widget publication,
- ActivityKit,
- recovery,
- lead-time preferences,
- schedule audit,
- acceptance diagnostics,
- navigation side effects.

Pilotní návrh:

### AppSyncCoordinator
Vstupy:
- ScheduleRepository
- AlertService
- DiagnosticsRecorder
- clock

Výstup:
- AppSyncState

Neobsahuje žádný SwiftUI.

### TodayViewModel
Vstup:
- CurrentScheduleProvider
- TodayStateCalculator
- clock

Publikuje pouze data potřebná pro Dnes.

### StayViewModel
Vstup:
- CurrentScheduleProvider

Publikuje dny a události.

### SettingsViewModel
Vstup:
- AlertPermissionService
- UserAlertPreferences
- SyncStatusProvider

Nezná schedule fetching detaily.

### ActivationViewModel
Vstup:
- ActivationRepository

Řeší pouze první spuštění / nový pobyt.

## F. Pilotní obrazovky

### Root
Stavy:
1. bez aktivace -> ActivationView
2. aktivováno, bez rozpisu -> Loading/RecoveryView
3. aktivní pobyt -> MainTabView
4. pobyt skončil -> StayFinishedView

### MainTabView
- TodayView
- WeekView
- StayView
- InfoView
- SettingsView

## G. Odstranění implicitních Darkov pravidel

Současné:
`CommanderProcedureCategory.classify(_:)` obsahuje slovní heuristiky.

Pilot:
- produkční klasifikace pochází ze SpaProfile,
- heuristika smí být jen importní pomocník/admin nástroj,
- heuristika nesmí být autoritativní v pacientské aplikaci.

Postup migrace:
1. přidat SpaProfile model,
2. přidat resolver aliasů,
3. při normalizaci serveru přidělit canonical procedureType/category,
4. mobil dostává již normalizovanou událost,
5. starou classify heuristiku nechat pro legacy data a testy, dokud nejsou převedeny.

## H. UI pravidla pro programátora

1. Žádná karta nesmí mít pevnou výšku pro textový obsah.
2. Název procedury minimálně 2 řádky, ideálně bez omezení v hlavní kartě.
3. Čas je vizuálně dominantní.
4. Místo je vždy text, ne jen ikona.
5. Barva doplňuje význam, nenese ho sama.
6. `minimumScaleFactor` nepoužívat jako primární řešení dlouhého textu.
7. Tlačítka hlavních akcí mají textový label.
8. Pokročilé akce nejsou na hlavní obrazovce.
9. Diagnostické build ID se nezobrazuje běžně pacientovi.
10. Error message má pacientovi říct co udělat, ne interní exception.

## I. Pilotní feature flags

Feature flags nejsou náhrada modulární architektury. Použít pouze pro rollout.

Doporučené:
- `advancedEventAlertControls`
- `compatibilityNotificationMode`
- `supportDiagnosticsExport`

Nedoporučené v pilotním targetu:
- `watchApp`
- `liveActivity`
- `homeWidgets`

Tyto capability se případně přidají jako samostatné targety později.

## J. Testy – migrační pravidlo

Při přesunu produkčního souboru:
1. nejdřív přesunout/rozšířit test,
2. potom přesunout implementaci,
3. spustit focused test,
4. spustit celý Core suite,
5. spustit iOS build,
6. až potom pokračovat dalším modulem.

Nikdy neslučovat více velkých architektonických přesunů do jednoho neověřeného kroku.

## K. První bezpečné refaktory

Pořadí, které minimalizuje riziko:

1. Přidat SpaProfile model a testy bez změny runtime.
2. Vyčlenit DiagnosticsRecorder z CommanderViewModel.
3. Vyčlenit widget publication do samostatné služby.
4. Vyčlenit Watch delivery do capability služby.
5. Vyčlenit AppSyncCoordinator.
6. Teprve potom vytvořit nový PilotApp target používající jen potřebné služby.
7. Snížit deployment target pilotního targetu a řešit compile availability.
8. Přidat fallback notification scheduler.
9. Přidat ActivationRepository a backend contract.

## L. Co znamená „čitelný pro nového programátora“

Nový programátor musí do 30 minut najít odpověď na:
- Kde je canonical Schedule model?
- Kde se validuje?
- Kde se počítá leaveAt?
- Kde se plánuje platformní alarm?
- Kde se ukládá poslední rozpis?
- Kde se stahuje nový rozpis?
- Jak se určí SpaProfile?
- Kde je Today presentation?
- Kde se loguje incident?

Pokud odpověď vyžaduje prohledat 1000řádkový ViewModel, refaktor ještě není hotový.

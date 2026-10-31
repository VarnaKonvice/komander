# Lázeňský Commander – Pilot v1

## 1. Cíl

Pilot v1 je samostatně pochopitelná mobilní aplikace pro reálný provoz v lázeňském domě.
Musí být jednoduchá pro pacienta a současně technicky čitelná pro dalšího programátora.

Primární uživatel není technický nadšenec. Je to pacient, který umí telefon odemknout,
přečíst velký text a zastavit upozornění.

## 2. Produktová věta

> Oficiální lázeňský rozpis v telefonu. Commander řekne, co následuje, kam jít a kdy vyrazit.

## 3. Pilotní rozsah – povinné

1. Aktivace pobytu jedním QR / aktivačním kódem.
2. Stažení a validace oficiálního rozpisu.
3. Offline použití posledního ověřeného rozpisu.
4. Obrazovka Dnes s velkým textem a velkými kartami.
5. Přehled celého pobytu / dnů.
6. Upozornění na odchod.
7. Zřetelný název procedury, čas a místo v upozornění.
8. Automatické přijetí novější verze rozpisu.
9. Zobrazení stavu synchronizace srozumitelně pacientovi.
10. Technická diagnostika pro podporu.
11. Nastavení velikosti/přístupnosti bez rozbití layoutu.
12. Auditovatelná identita rozpisu a jeho verzí.

## 4. Výslovně mimo kritickou cestu pilotu

Tyto části se z repozitáře nemažou a jejich testy zůstávají zachované, ale pilot v1 na nich
nesmí záviset:

- samostatná Apple Watch aplikace,
- Watch widgety,
- Live Activity,
- Dynamic Island,
- lock-screen widget,
- povinná Google Calendar integrace,
- provisioning diagnostika Personal Team,
- fyzické E2E utility,
- design preview fixture,
- vývojové acceptance obrazovky.

Standardní systémové zrcadlení notifikací na párované hodinky je dovoleno, ale není součástí
garantovaného kontraktu pilotu.

## 5. UX pilotu

### Hlavní navigace

Pilot má pět hlavních záložek:

- **Dnes**
- **Týden**
- **Pobyt**
- **Info**
- **Nastavení**

Jednoduchost nevzniká omezením počtu obrazovek, ale tím, že každá má jednu jasnou odpovědnost a žádná nevyžaduje technické znalosti.

### Dnes

Po otevření musí být během jedné sekundy zřejmé:

- co je další událost,
- v kolik začíná,
- kdy je vhodné vyrazit,
- kde probíhá.

Karta se smí zvětšit na výšku. Text se nesmí zmenšovat tak, že přestane být pohodlně čitelný.
Název procedury může být na více řádcích.

Doporučené pořadí:
1. stav / další událost,
2. název,
3. čas,
4. odchod,
5. místo,
6. následující události dne.

### Týden

Rychlý přehled několika dnů dopředu. Uživatel musí být schopný v kavárně nebo při plánování dne zjistit, co ho čeká zítra a pozítří, bez papírového léčebného průkazu.

### Pobyt

Přehled celého pobytu a jeho průběhu. Může obsahovat souhrny, ale nesmí duplikovat detail Týdne.

### Info

Stálé praktické údaje k pobytu: lázeňský dům, pokoj, lékař, jídelní směna, termín pobytu a další lokální informace poskytnuté konkrétními lázněmi.

### Nastavení

Výchozí obrazovka obsahuje pouze:
- stav upozornění,
- předstih,
- velikost / výraznost,
- synchronizaci rozpisu,
- nápovědu.

Sekce **Pokročilé** je sbalená a není potřeba pro běžné používání.

## 6. Pokročilé ovládání

Oficiální proceduru pacient nikdy neupravuje.

Případné budoucí lokální akce mohou měnit pouze chování zařízení:
- „Už absolvováno – nevydávat toto upozornění“
- „Nevyzvánět tuto událost“
- „Obnovit upozornění“

Každý takový detail musí obsahovat text:
> Oficiální rozpis lázní se nemění.

Pilot může tuto funkci první iteraci úplně vynechat. Nesmí blokovat ostrý pilot.

## 7. Architektonická pravidla

1. Canonical schedule je jediný zdroj pravdy.
2. Spa profile vysvětluje data, ale nesmí přepisovat canonical čas.
3. Platformní upozornění je projekce canonical schedule.
4. UI nikdy nepočítá vlastní časy odchodu.
5. Všechny časy odchodu vznikají v jednom doménovém use-case.
6. Každá platformní integrace je za protokolem/rozhraním.
7. View nesmí provádět síť, persistence ani plánování alarmů.
8. Jeden soubor má mít jednu hlavní odpovědnost.
9. Produkční kód nesmí obsahovat Darkov-specific if/else pravidla.
10. Testy se při refaktoru nemažou; přesouvají se spolu s modulem.

## 8. Cílové moduly

```
CommanderDomain/
  Models/
    Schedule.swift
    ScheduleEvent.swift
    SpaProfile.swift
    StayActivation.swift
  Validation/
    ScheduleValidator.swift
    SpaProfileValidator.swift
  Projection/
    ScheduleProjection.swift
    DeparturePolicy.swift
    TodayState.swift

CommanderData/
  ScheduleRepository.swift
  ScheduleRemoteDataSource.swift
  ScheduleLocalStore.swift
  ActivationRepository.swift
  SpaProfileRepository.swift

CommanderAlerts/
  AlertPlan.swift
  AlertScheduler.swift
  AlertReconciler.swift
  AlertDiagnostics.swift

CommanderIOS/
  AlarmKitAlertScheduler.swift        // iOS 26+
  LocalNotificationAlertScheduler.swift // kompatibilní režim
  IOSNotificationPermission.swift
  KeychainActivationStore.swift

CommanderFeatures/
  Activation/
  Today/
  Stay/
  Settings/
  Advanced/

CommanderSupport/
  Diagnostics/
  Logging/
  BuildIdentity/

CommanderApp/
  AppCompositionRoot.swift
  RootView.swift
```

Názvy jsou pracovní. Důležitá je hranice odpovědností, ne konkrétní adresář.

## 9. Spa Profile

Každý lázeňský dům má vlastní konfigurační profil.

Spa profile obsahuje:
- identitu domu,
- katalog procedur,
- aliasy/zkratky,
- kategorii procedury,
- očekávanou délku,
- standardní předstih,
- pracoviště / orientační metadata,
- jídelní směny,
- místní pravidla,
- validační tolerance.

Spa profile nesmí měnit explicitní canonical start/end pacienta.

Příklad:
```
canonical: Motomed 08:15–08:35
profile:   Motomed = rehabilitace, obvykle 20 min, FYZ48
výsledek:  ACCEPT

canonical: Motomed 08:15–11:35
profile:   obvykle 20 min
výsledek:  REVIEW, nikdy automaticky nepřepsat
```

## 10. Aktivace pobytu

Produkční pilot nesmí být závislý na veřejném GitHub raw URL.

Doporučený tok:
1. lázně vytvoří pobyt,
2. backend vydá náhodný jednorázový / omezený aktivační token,
3. QR obsahuje pouze aktivační URL/token,
4. telefon token vymění za identitu pobytu,
5. telefon stáhne canonical schedule + spa profile,
6. token/credential se uloží bezpečně v Keychain,
7. další refresh používá přidělenou identitu pobytu.

QR nesmí obsahovat celý zdravotní rozpis ani předvídatelné heslo.

## 11. Upozornění

Doména vytvoří jediný `AlertPlan`.

```
Schedule + SpaProfile + UserAlertPreferences
                     |
                     v
                  AlertPlan
                     |
       +-------------+-------------+
       |                           |
       v                           v
AlarmKit scheduler         Local notification scheduler
iOS 26+                    kompatibilní iOS
```

Aplikace si nesmí myslet, že oba režimy mají stejné systémové garance.
UI musí umět zobrazit aktuální úroveň služby.

Android později implementuje stejné `AlertPlan` chování vlastním schedulerem.

## 12. iOS kompatibilita

Současný osobní Commander má deployment target iOS 26.1.
Pilot nesmí jen zdědit tuto hranici bez rozhodnutí.

Cílová architektura musí umožnit:
- plný alarmový režim na iOS 26+,
- kompatibilní notification režim na starších podporovaných iOS.

Pracovní minimum pro pilot: iOS 16+.
Definitivní minimum se uzavře až po kompilaci pilotního targetu a testu reálných zařízení.

## 13. Přístupnost

Povinné acceptance podmínky:
- systémové Dynamic Type,
- velké accessibility velikosti textu,
- VoiceOver labely hlavních akcí,
- žádná kritická informace jen barvou,
- touch target minimálně systémový standard,
- karty rostou na výšku místo agresivního `minimumScaleFactor`,
- dlouhé názvy procedur jsou víceřádkové,
- kontrast je ověřený na světlém i tmavém podkladu, pokud budou oba režimy.

Volitelné onboarding doporučení:
- výraznější upozornění,
- systémové blikání při upozornění,
- haptika podle možností zařízení.

## 14. Stav aplikace

Běžný uživatel smí vidět jen jednoduché stavy:
- Rozpis je připraven
- Aktualizuji rozpis
- Upozornění nejsou povolena
- Rozpis se nepodařilo aktualizovat – používám poslední uloženou verzi
- Je potřeba pomoc personálu / podpory

Interní diagnostika si smí uchovávat technické detaily:
- scheduleVersion,
- source revision,
- alert IDs,
- platform readback,
- build identity,
- sync timestamp,
- chyby transportu.

## 15. Co z dnešního kódu znovu použít

Bez přepisování zachovat a postupně vyčistit:
- `Schedule`, `ScheduleEvent`,
- `NativeAlarmContract` / jednotný výpočet leaveAt,
- `CommanderScheduleProjection`,
- versioned snapshot store,
- reconciliation logiku alarmů,
- source revision / source ledger,
- validační testy,
- fyzické acceptance testy.

Přes rozhraní oddělit:
- AlarmKit,
- UserNotifications,
- síťový fetch,
- persistence,
- tenant/spa profil.

Z pilotního composition root odstranit:
- WatchConnectivity,
- ActivityKit coordinator,
- WidgetKit publication,
- provisioning Personal Team workflow.

## 16. Refaktor současného CommanderViewModel

Současný `CommanderViewModel` nesmí být vzorem pro pilot. Je orchestrace příliš mnoha subsystémů.

Rozdělit minimálně na:
- `ActivationViewModel`
- `TodayViewModel`
- `StayViewModel`
- `SettingsViewModel`
- `AppSyncCoordinator` (bez UI)
- `DiagnosticsRecorder` (bez UI)

ViewModel nesmí znát Watch, Widget nebo provisioning, pokud daný pilotní feature target tuto funkci nemá.

## 17. Testovací strategie

Žádný současný regresní test se nemaže jen proto, že funkce není v pilotu.

Testy rozdělit:
- Domain unit tests
- Schedule contract tests
- Alert plan tests
- Repository tests
- iOS adapter tests
- UI snapshot/accessibility tests
- Physical device acceptance

Staré Watch/LiveActivity/Widget testy mohou být ve vlastní legacy/optional suite.

Pilotní CI musí mít vlastní jasný gate:
1. domain,
2. schedule,
3. alerts,
4. persistence,
5. pilot UI build,
6. physical smoke před vydáním.

## 18. Definition of Done – iOS pilot

iOS pilot je hotový, když:
- nový programátor najde tok rozpisu bez čtení tisíciřádkového ViewModelu,
- základní aplikace funguje bez Watch/Widget/LiveActivity,
- QR aktivace funguje,
- rozpis se aktualizuje a offline přežije,
- alarm/notifikace jsou reconciliované a auditované,
- hlavní obrazovka projde velkým Dynamic Type,
- pacient nemusí nastavovat pokročilé funkce,
- minimální podporovaný iOS je skutečně ověřen fyzicky,
- 50–100 pilotních instalací lze provozovat bez ručního zásahu do každého telefonu.

## 19. Pořadí implementace

### Fáze A – zmrazení osobního Commanderu
- uložit současný funkční stav,
- dokončit otevřené regresní chyby,
- žádné nové funkce mimo chyby.

### Fáze B – doménové jádro
- rozdělit modely,
- přidat SpaProfile,
- vytvořit čistý AlertPlan,
- odstranit Darkov-specific klasifikaci z obecné domény.

### Fáze C – nový iOS pilot target
- tři záložky,
- velké UI,
- nový composition root,
- ScheduleRepository,
- iOS alert adapter,
- bez Watch/Widget/ActivityKit.

### Fáze D – aktivace/backend contract
- QR token,
- tenant/stay identity,
- bezpečný refresh,
- audit/versioning.

### Fáze E – kompatibilita
- iOS 26 AlarmKit,
- starší iOS notification fallback,
- fyzická zařízení.

### Fáze F – pilotní provoz
- integrační checklist lázní,
- 50–100 pacientů,
- metriky aktivace,
- počet support zásahů,
- alarm incident rate,
- administrativní čas personálu.

### Fáze G – Android
- stejný backend contract,
- stejný SpaProfile,
- stejný AlertPlan semantics,
- Android-specific scheduler a UI.

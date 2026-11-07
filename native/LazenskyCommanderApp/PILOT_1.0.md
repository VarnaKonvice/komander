# iPhone Pilot 1.0

Připraveno 4. 11. 2026 na větvi `lc/iphone-pilot-1.0` od `main @ aacec354cdfe9d42804379153664ead7c28f2e26`.
Verze iPhone aplikace a jejího rozšíření: **1.0 (12)**. Pracovní stav PILOT 1 byl 6. 11. 2026 uložen v commitu `6dd7599` a zveřejněn na stejnojmenné větvi.

## Schválený produktový směr před převodem do C#/.NET

PILOT 1 zůstává technickým základem pro další implementaci. Schválený zákaznický tok B2B/B2C, billingový okamžik, párování pobytu, QR fallback a pravidla ochrany dat jsou popsány v:

- `docs/bohanes-technologies/product/LAZENSKY-COMMANDER-ZAKAZNICKY-TOK-V1.md`
- `docs/bohanes-technologies/product/LAZENSKY-COMMANDER-UZIVATELSKY-NAVOD.md`
- `docs/bohanes-technologies/product/LAZENSKY-COMMANDER-PODMINKY-SLUZBY-DRAFT.md`
- `docs/bohanes-technologies/product/LAZENSKY-COMMANDER-APP-STORE-RELEASE.md`

Tyto dokumenty jsou pro Filipův převod požadavkem na cílové chování. B2B/B2C backend, SMS, QR ověření, fotografie/PDF, billing a platby zatím nejsou vydávány za hotové funkce PILOT 1.

## Rozsah

- Schválený vzhled obrazovek zůstává zachovaný.
- iPhone target už nebuildí ani nevkládá Watch app a její widget. Nelinkuje WatchConnectivity a nekompiluje `IPhoneWatchConnectivityCoordinator.swift`.
- Inicializace, foreground synchronizace i acceptance ověření už neaktivují WCSession, neposílají Watch snapshot a nečekají na Watch ACK.
- Watch targety, jejich samostatné schéma, zdroje, lokální alarmy a historie zůstávají v repozitáři pro budoucí práci.
- Sdílené čisté typy se jmény `WatchScheduleSnapshot` a `FileWatchScheduleCache` zůstávají: používají je také iPhone widgety a projekce lokálních předstihů. Nevyžadují běžící hodinky ani WatchConnectivity. Jejich přejmenování a změna persistence nejsou součástí pilotu.
- Home Screen widgety sdílí aktuální modré barvy s aplikací; akcenty procedur a jídel se nemění. Starší paleta Watch a Live Activity se samostatně nemění.
- Dole v Nastavení je původní bílé firemní logo převedené z `docs/bohanes-technologies/web/site/bohanes-logo-white.svg`, název firmy, produktu a skutečná verze/build z Bundle.
- E-mail se nezobrazuje: firemní web ho výslovně uvádí jako dosud neověřený. Volitelný návrh adresy v dokumentaci HQ není potvrzený kontakt.

## Audit historie importu

Prověřené commity a změny:

| Commit | Zjištění |
| --- | --- |
| `5ec07b0` | Vizuální úprava webové obrazovky importu; pokročilý JSON v textarea a `JSON.parse`/`normalize`. |
| `dfe716f` | Layout stejné obrazovky a oprava počtu dnů, bez nového parseru formulářů. |
| `11bbbdd` | Vypnutí historického lokálního importu; kanonický feed je vstupem aplikace. |
| `9a09a3a` | Merge tohoto odstranění. |
| `4065af0`, `c2fb779` | Výběr `.json` souboru přes FileReader/readAsText. |
| `1c2b7c9` | Přepis webového UI; nedokládá parser PDF/fotografií. |

Prohledána také dostupná historie všech refs podle názvů souborů a změn obsahujících FileReader, file input, PDFKit, VNRecognizeText, Tesseract a application/pdf. Použitelný import skutečného procedurového formuláře/PDF/fotografie nebyl nalezen. Zdrojové revize procedurových listů v core jsou strukturované podklady pro porovnání s kanonickým rozpisem, nikoli čtečka fotografie nebo PDF.

Historický princip výběru JSON souboru je převeden do nativního file importeru. Starý formát `stay/items` se automaticky nepřekládá a nepřebírá se jeho volná normalizace bez stabilních identifikátorů.

## Kompatibilita iOS a první spuštění

- Aplikace má minimum iOS **16.1**; iPhone widgetové rozšíření minimum iOS **16.2**.
- Na iOS 26.1+ používá Commander AlarmKit. Na starším podporovaném iOS funguje celý rozpis bez AlarmKitu.
- Při prvním používání se Commander nesnaží vyžádat Kalendář ani běžná oznámení začátku. Základní onboarding řeší pouze systémové alarmy tam, kde je AlarmKit podporovaný.
- Kalendářové oprávnění se vyžádá až po ručním zapnutí v Nastavení.

## Import

`Nastavení → Pokročilé → Import a kalendář → Vybrat JSON soubor`.

- Podporuje současný kanonický JSON (`schemaVersion`, `scheduleVersion`, `updatedAt`, `stay`, `events`, `settings`), nejvýše 5 MiB.
- Po výběru a validaci zobrazí potvrzení nahrazení celého pobytu s verzí a počtem událostí. Zrušení nic nemění.
- `ScheduleFileImport.decode` a `NativeAlarmContract.validateCanonical` kontrolují soubor. Koordinátor před zápisem znovu kontroluje kontrakt, dataset a projekci se skutečnými lokálními předstihy.
- Vstup `.imported(Schedule)` běží stejnou serializovanou cestou `CommanderScheduleSyncCoordinator` jako síťový vstup: tentýž snapshot store, verze, AlarmSyncService a následné iPhone widgety/oznámení/ActivityKit reconciliation.
- Shodný soubor lze načíst opakovaně. Starší verze a rozdílný obsah se stejnou verzí se odmítnou bez změny uloženého rozpisu a alarmů. Verze se uměle nepřepisuje.
- Nevzniká druhý soubor rozpisu ani lokální importní režim. Po restartu se čte stejný offline snapshot. Běžná synchronizace dál přijímá novější kanonické verze a starší feed nemůže import přepsat.
- Lokální předstihy zůstávají uložené. Nepovolená volitelná oznámení začátku rozpis nezneplatní a Commander si jejich oprávnění při prvním spuštění sám nevyžádá. AlarmKit zůstává samostatnou primární alarmovou vrstvou.

## Kalendář

Kalendář je ve výchozím stavu vypnutý a při prvním spuštění nevyžaduje žádné oprávnění. V `Nastavení → Kalendář` lze zapnout `Přidávat pobyt do Apple Kalendáře`. Teprve při zapnutí si Commander vyžádá přístup a potom přidává nebo aktualizuje celý aktuální pobyt podle stabilních ID bez vytváření duplicit. Vypnutí další synchronizaci zastaví, ale již zapsané položky samo nemaže.

Ruční tlačítko `Exportovat pobyt (.ics)` zůstává v `Nastavení → Pokročilé → Import a kalendář`. `ScheduleCalendarExport` exportuje všechny události pobytu dohromady a používá stejnou `CommanderScheduleProjection` a lokální předstihy jako alarmy.

ICS obsahuje `Europe/Prague`, VTIMEZONE s CET/CEST, UTC DTSTAMP, stabilní UID odvozené ze stableId, CRLF, escapování a UTF-8 folding. Přímá synchronizace Apple Kalendáře ani .ics export nejsou podmínkou pro základní používání Commanderu.

## Ověření

- `swift test` v `native/LazenskyCommander`: **318 testů, vše prošlo**. Šest nových testů pokrývá canonical/legacy/poškozené soubory, velikost, verzové konflikty, zachování snapshotu, alarmy bez sítě/Watch, idempotenci, restart přes cache, předstihy, půlnoc, CET/CEST, všechny typy událostí, escapování, UTF-8 folding a stabilní UID.
- Debug build pro iOS Simulator: prošel; současně sestaveny všechny tři Home Screen widgety a Live Activity v jednom rozšíření.
- Release build pro fyzický iPhone (`generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO`): prošel, včetně rozšíření. Jde o kompilaci pro zařízení, ne podepsanou distribuci nebo instalaci.
- Build graph iPhone schématu obsahuje pouze aplikaci, její iPhone rozšíření a core. Kontrola balíčku: žádný `Watch/*.app`, pouze iPhone appex. Kontrola linkování: AlarmKit, ActivityKit a WidgetKit přítomné, WatchConnectivity nepřítomné.
- Aplikace se spustila v iPhone simulátoru v existujícím designovém náhledu; hlavní obrazovka vizuálně zkontrolována.
- `git diff --check`: bez chyb. Přetrvává dřívější warning nepoužité návratové hodnoty `withAnimation` v `CommanderWeekView.swift:80`.

### Omezení Live Activity

`CommanderMVPPolicy.createsLiveActivities = false` zůstává v platnosti. Běžný PILOT 1 používá no-op koordinátor a nevytváří samostatné procedurové Live Activity ani Dynamic Island. Historická ActivityKit implementace zůstává pouze pro oddělený physical-acceptance target; widgetové rozšíření se dál sestavuje kvůli Home Screen widgetům.

## Kontrola Filipem

1. Na fyzickém iPhonu: start, povolení pouze systémových alarmů, Dnes/Týden/Pobyt, návrat z pozadí a režim offline. První spuštění nesmí samo vyžádat Kalendář ani běžná oznámení.
2. Import validního kanonického souboru s novější verzí; před potvrzením ověřit termín a obsah pobytu. Zkontrolovat procedury i jídla, změny alarmů, widgety a zachované předstihy. Znovu otevřít aplikaci offline.
3. Zrušení pickeru/potvrzení, poškozený JSON, starší verze a rozdílný obsah se stejnou verzí musí zachovat poslední platný stav. PDF/fotografie nemají být nabízené jako podporovaný import.
4. V Nastavení zapnout Apple Kalendář, povolit jej až na vyžádání a ověřit vytvoření i následnou aktualizaci pobytu bez duplicit. Samostatně ověřit také ruční export .ics.
5. Přidat malé/střední widgety vedle ikony; porovnat modré pozadí a akcenty jídel/procedur. Prověřit obsah po importu a změně předstihů.
6. Nastavení: čitelnost nové obrazovky, dialog a ukládání souboru, patička s logem a 1.0/build 12, větší systémové písmo.
7. Instalace pilotu nesmí nabídnout instalaci Watch aplikace. iPhone nesmí čekat na spárované nebo dostupné hodinky.
8. Zvlášť posoudit výchozí MVP politiku samostatných Live Activity; jejich opětovné zapnutí vyžaduje fyzický test souběhu s AlarmKitem.

Fyzický telefon, produkční alarmy ani osobní kalendář nebyly při této přípravě měněny. Podepsaná instalace, skutečné zazvonění AlarmKitu a ruční průchod volitelnou synchronizací Apple Kalendáře zůstávají ke kontrole.

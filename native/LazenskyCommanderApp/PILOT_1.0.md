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

## Import

`Nastavení → Pokročilé → Import a kalendář → Vybrat JSON soubor`.

- Podporuje současný kanonický JSON (`schemaVersion`, `scheduleVersion`, `updatedAt`, `stay`, `events`, `settings`), nejvýše 5 MiB.
- Po výběru a validaci zobrazí potvrzení nahrazení celého pobytu s verzí a počtem událostí. Zrušení nic nemění.
- `ScheduleFileImport.decode` a `NativeAlarmContract.validateCanonical` kontrolují soubor. Koordinátor před zápisem znovu kontroluje kontrakt, dataset a projekci se skutečnými lokálními předstihy.
- Vstup `.imported(Schedule)` běží stejnou serializovanou cestou `CommanderScheduleSyncCoordinator` jako síťový vstup: tentýž snapshot store, verze, AlarmSyncService a následné iPhone widgety/oznámení/ActivityKit reconciliation.
- Shodný soubor lze načíst opakovaně. Starší verze a rozdílný obsah se stejnou verzí se odmítnou bez změny uloženého rozpisu a alarmů. Verze se uměle nepřepisuje.
- Nevzniká druhý soubor rozpisu ani lokální importní režim. Po restartu se čte stejný offline snapshot. Běžná synchronizace dál přijímá novější kanonické verze a starší feed nemůže import přepsat.
- Lokální předstihy zůstávají uložené. Pokud platforma odmítne alarmy/oznámení, platný rozpis zůstane přijatý a UI výslovně ohlásí potřebu kontroly; neoprávněně nehlásí ověřené alarmy.

## Kalendář

Na stejné obrazovce tlačítko `Exportovat pobyt (.ics)` otevře standardní ukládání do Souborů.

`ScheduleCalendarExport` vychází z historického webového `exportWeek`: názvy, místa, časy, kategorie a odchod v popisu. Exportuje všechny události aktuálního pobytu dohromady, včetně minulých. Používá současnou `CommanderScheduleProjection` a stejné lokální předstihy jako alarmy.

ICS obsahuje `Europe/Prague`, VTIMEZONE s CET/CEST, UTC DTSTAMP, stabilní UID odvozené ze stableId, CRLF, escapování a zalamování nejvýše po 75 UTF-8 bytech. Čas odchodu zahrnuje datum, takže je jednoznačný i při odchodu předchozí den. Kalendář je jednorázový export, ne živé předplatné a nemění synchronizaci Google Calendar.

## Ověření

- `swift test` v `native/LazenskyCommander`: **318 testů, vše prošlo**. Šest nových testů pokrývá canonical/legacy/poškozené soubory, velikost, verzové konflikty, zachování snapshotu, alarmy bez sítě/Watch, idempotenci, restart přes cache, předstihy, půlnoc, CET/CEST, všechny typy událostí, escapování, UTF-8 folding a stabilní UID.
- Debug build pro iOS Simulator: prošel; současně sestaveny všechny tři Home Screen widgety a Live Activity v jednom rozšíření.
- Release build pro fyzický iPhone (`generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO`): prošel, včetně rozšíření. Jde o kompilaci pro zařízení, ne podepsanou distribuci nebo instalaci.
- Build graph iPhone schématu obsahuje pouze aplikaci, její iPhone rozšíření a core. Kontrola balíčku: žádný `Watch/*.app`, pouze iPhone appex. Kontrola linkování: AlarmKit, ActivityKit a WidgetKit přítomné, WatchConnectivity nepřítomné.
- Aplikace se spustila v iPhone simulátoru v existujícím designovém náhledu; hlavní obrazovka vizuálně zkontrolována.
- `git diff --check`: bez chyb. Přetrvává dřívější warning nepoužité návratové hodnoty `withAnimation` v `CommanderWeekView.swift:80`.

### Omezení Live Activity

Již výchozí `aacec35` obsahuje `CommanderMVPPolicy.createsLiveActivities = false`. Pilot tuto politiku nemění. Existující renderer Live Activity/Dynamic Island, koordinátor, AlarmKit a rozšíření se dál kompilují. Samostatné procedurové Live Activity ale touto přípravou nejsou zapnuté. Build a jednotkové testy nejsou důkazem jejich živého průběhu na zamčeném fyzickém telefonu.

## Kontrola Filipem

1. Na fyzickém iPhonu: start, povolení alarmů/oznámení, Dnes/Týden/Pobyt, návrat z pozadí a režim offline.
2. Import validního kanonického souboru s novější verzí; před potvrzením ověřit termín a obsah pobytu. Zkontrolovat procedury i jídla, změny alarmů, widgety a zachované předstihy. Znovu otevřít aplikaci offline.
3. Zrušení pickeru/potvrzení, poškozený JSON, starší verze a rozdílný obsah se stejnou verzí musí zachovat poslední platný stav. PDF/fotografie nemají být nabízené jako podporovaný import.
4. Export celého pobytu otevřít v Apple Kalendáři. Porovnat počet událostí, začátky/konce, místa a odchody, včetně přechodu přes půlnoc a CET/CEST. Import do skutečné kalendářové aplikace zatím nebyl ručně ověřen.
5. Přidat malé/střední widgety vedle ikony; porovnat modré pozadí a akcenty jídel/procedur. Prověřit obsah po importu a změně předstihů.
6. Nastavení: čitelnost nové obrazovky, dialog a ukládání souboru, patička s logem a 1.0/build 12, větší systémové písmo.
7. Instalace pilotu nesmí nabídnout instalaci Watch aplikace. iPhone nesmí čekat na spárované nebo dostupné hodinky.
8. Zvlášť posoudit výchozí MVP politiku samostatných Live Activity; jejich opětovné zapnutí vyžaduje fyzický test souběhu s AlarmKitem.

Fyzický telefon, produkční alarmy a osobní kalendář nebyly při této přípravě měněny. Podepsaný distribuční build a ruční průchod novým file pickerem/exportérem zůstávají ke kontrole.

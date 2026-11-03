# Bohanes Technologies – firemní web

Lokální pracovní verze prezentace Lázeňského Commanderu. Zachovává `noindex,nofollow`.

## Úprava 3. 11. 2026

Nejdřív byl produkční web prohlédnut na desktopu i mobilu a porovnán s nativním projektem. Potom byly změněny pouze webové soubory. Nebyl proveden commit, push ani deployment.

### Změněné soubory

Všechny následující soubory již existovaly; nové soubory projektu nevznikly.

| Soubor vůči tomuto adresáři | Změna |
| --- | --- |
| `README.md` | Aktuální stav, původ podkladů, kontrola a zbývající omezení. |
| `site/index.html` | Čitelné písmo, responzivní navigace, rozvržení sekcí, zvětšování obrázků, přesnější popisy dostupnosti, skutečné ikony, označená místa pro QR, odstranění neověřených kontaktů a neodesílajícího formuláře. |
| `site/procedure-icons/rehab.png` | Export nativního rendereru: rehabilitation / figure.run. |
| `site/procedure-icons/electro.png` | Export nativního rendereru: electro / atom. |
| `site/procedure-icons/bath.png` | Export nativního rendereru: water / drop. |
| `site/procedure-icons/massage.png` | Export nativního rendereru: massage / leaf.fill. |
| `site/procedure-icons/wrap.png` | Export nativního rendereru: heatWrap / CommanderHeatWavesArtwork. |
| `site/procedure-icons/hydrojet.png` | Stejná rodina massage jako v nativním klasifikátoru. |
| `site/screens/commander-today.png` | Nový skutečný screenshot Dnes ze Simulatoru. |
| `site/screens/commander-week.png` | Nový skutečný screenshot Týden ze Simulatoru. |
| `site/screens/commander-stay.png` | Nový skutečný screenshot Pobyt ze Simulatoru. |
| `site/screens/commander-info.png` | Nový skutečný screenshot Info ze Simulatoru. |
| `site/screens/commander-settings.png` | Nový skutečný screenshot Nastavení ze Simulatoru. |

Firemní SVG loga ani nativní Swift soubory nebyly změněny. Barevná varianta `bohanes-logo-full.svg` je v záhlaví, bílá `bohanes-logo-white.svg` v tmavém zápatí bez barevného filtru.

## Zdroje pravdy

- `native/LazenskyCommanderApp/Shared/CommanderBrandAssets.swift`: kategorie, barvy a skutečná kresba `CommanderProcedureArtwork`.
- Ikony jsou PNG exporty tohoto SwiftUI rendereru přes macOS ImageRenderer, nikoliv ilustrace původního webu. Pro export byly přímo převzaty definice Colors, ProcedureFamily, CommanderProcedureArtwork a CommanderHeatWavesArtwork; závislost klasifikátoru byla při exportu nahrazena explicitním výběrem rodiny. Rozdíly SF Symbols mezi macOS a iOS nebyly porovnány na úrovni pixelů.
- `CommanderSettingsView.swift`, `ApprovedPresentationAssetsTests.swift`, `DarkovVisualClassificationTests.swift`: kategorie a klasifikace. Jodobromová koupel používá nativní vizuální rodinu heatWrap; nevznikla nová kategorie.
- Pět screenshotů pochází ze sestavení aktuálního projektu, schéma LazenskyCommanderApp, Debug, Simulator Commander Design iPhone 16 / iOS 26.5. Použit byl existující demonstrační režim `-CommanderDesignPreview -CommanderPreviewTab <tab>`. Žádné úpravy nativního UI ani osobních dat nebyly potřeba.
- `Shared/CommanderDesignPreviewSchedule.json`: ukázka časů, názvů a míst pro sekci Jak to funguje.
- Xcode projekt potvrzuje `IPHONEOS_DEPLOYMENT_TARGET = 26.1`.
- `AlarmKitAdapter.swift`, `AlarmAdapter.swift`: systémový alarm v čase leaveAt, titulek „Čas vyrazit: …“, alert-only režim; odpočty nejsou samostatný AlarmKit countdown.
- `CommanderNotifications.swift`: `createsLiveActivities = false`, `createsStandaloneWatchAlerts = false`. Existující kód Live Activity a Dynamic Island není vydáván za zapnutou funkci.
- `docs/google-calendar-sync.md`: synchronizace rozpisu do kalendářů Procedury a Jídlo; změny v Google Kalendáři nejsou zdrojem rozpisu.

## Ověření

- Xcode: sestavení aplikace pro iOS Simulator dokončeno s BUILD SUCCEEDED.
- Produkční i výsledný lokální web vyrenderován v Chromu při desktopové i mobilní šířce.
- Lokální web zkontrolován při 320, 360, 390, 768, 1024, 1199, 1200, 1440 a 1920 px.
- Bez horizontálního přetékání; všechny používané obrázky načteny, lokální kotvy existují, poměry obrázků zachovány.
- Zkontrolované běžné texty mají alespoň 14 px; obsah a popisky zpravidla 16–20 px.
- Mobilní menu se otevře a po volbě sekce zavře.
- Detail screenshotu se otevře, Escape jej zavře, originál lze otevřít samostatně.
- Bez zachycených JavaScript výjimek.
- Vizuálně zkontrolovány všechny sekce shora dolů na desktopu i mobilu.

## Zbývající omezení

- Finální e-mail, telefon ani distribuční a aktivační URL nebyly v projektu doloženy. Web je označuje jako neověřené/připravované. Vzory v instalační sekci jsou výslovně nefunkční místa pro QR.
- Nativní Android projekt ani jeho systémové minimum nebyly nalezeny. Android není prezentován se smyšlenou verzí systému nebo shodou funkcí.
- Systémový alarm nad otevřenou aplikací nebyl nově zachycen. Web ukazuje existující fotografii systémového alarmu na zamčeném telefonu a samostatný skutečný denní přehled; druhý obrázek není screenshot vyzvánějícího alarmu.
- Nové screenshoty Watch a Dynamic Island nebyly získány. Jejich stav vychází ze zdrojového kódu, nikoliv z ověření celé funkce na fyzických zařízeních.
- Fotografie widgetů a Live Activity z `site/real-ui` byly zachovány v původních poměrech. Jejich nízké rozlišení omezuje kvalitu zvětšení; neproběhlo nové pořízení widgetů.
- Položka Nastavení → Kalendář pobytu nebyla v aktuálním nativním nastavení nalezena; web ji označuje jako připravovanou.
- Úplný distribuční, platební a aktivační proces ani produkční přihlášení do Google Kalendáře nebyly testovány. Tato úprava neměnila jejich implementaci.
- Neproběhlo měření kontrastu všech kombinací ani testování v Safari a Firefoxu. Nativní screenshoty věrně obsahují i současné zkracování některých textů aplikace.

## Lokální otevření

Z adresáře `site` spusťte běžný statický HTTP server a otevřete jeho lokální adresu. Kořenové URL obrázků předpokládají HTTP root v tomto adresáři.

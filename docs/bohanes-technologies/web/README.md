# Bohanes Technologies – Lázeňský Commander

Lokální pracovní web. Poslední dolaďovací kolo dokončeno 4. 11. 2026.


## Oprava rozsahu centrování – 4. 11. 2026

Na základě vizuální kontroly vráceno původní levé zarovnání hlavních nadpisů a úvodních textů Užitečné obrazovky / Jak to funguje / Alarmy a upozornění. Centrované zůstávají pouze názvy a popisy uvnitř malých karet (Dnes, Týden, Pobyt, Info, Nastavení, pět kroků a tři alarmové karty). Předchozí popis širšího centrování níže je historický a již neplatí.

## Závěrečné centrování a synchronizace – 4. 11. 2026

- U sekcí Užitečné obrazovky, Jak to funguje a Alarmy a upozornění jsou nadpisy a jejich krátké doprovodné věty centrovány jako jeden celek.
- Krátké titulky a popisy karet Dnes / Týden / Pobyt / Info / Nastavení, kroků převodu a tří alarmových karet jsou centrovány. Delší texty v dalších sekcích ponechány vlevo kvůli čitelnosti.
- Změna provedena cíleným CSS blokem `final-copy-centering` na konci hlavičky `site/index.html`, bez úprav nativního iPhone projektu.
- Před synchronizací byly ověřeny HTML parserem cílové selektory a `git diff --check`.

## Aktuální doladění – 4. 11. 2026 (vizuální audit a interakce)

Pouze lokální pracovní soubory. V tomto kole upraveny přesně `site/index.html` a `README.md`; nové projektové soubory nevznikly. Bez commitu, push, deploymentu a zásahu do produkce.

### Provedené změny

- Navigace má pořadí Domů / O nás / Lázeňský Commander / Funkce / Instalace / Co chystáme / Pro lázně a samostatné CTA Kontaktujte nás. Zvětšené transparentní firemní logo i výška hlavičky zůstaly. Pro lázně je zvýrazněné pouze mírně silnějším písmem; spodní zelená linka byla odstraněna.
- Úvod Funkcí má všechny tři textové řádky přesně na levé ose vnější hrany hlavních dlaždic. Původní Commander wordmark je součástí levého úvodu; osamocený pravý symbol byl odstraněn.
- Jak to funguje používá pět samostatných karet propojených šipkami, se světlými přípravnými kroky a kontrastními kroky aplikace / upozornění. Obsah a nativní symboly jsou nezměněné. Od tabletových šířek směrem dolů jde tok svisle, aby se text nemačkal.
- Alarmy: tři původní snímky a struktura zůstaly. Všechny tři značky mají jednotný rámeček; skutečné SF symboly hodin a alarmu jsou správně vystředěné a zobrazené větší, se započtením transparentních okrajů původních PNG. Žádný nový snímek alarmu nevznikl.
- Kalendář a widgety: původní rozložení tří widgetů, obrázky i jejich proporce zůstaly. Widgety mají světlejší modrý obvod a zřetelnou hranu vůči pozadí. Kalendáře používají stejné cyan hover/focus orámování jako ostatní zvětšitelné prvky. Kliknutí na kartu, náhled i lupu otevře správný HTML detail s pravdivým stavem funkce.
- Instalace má o stupeň hlubší, stále světlé nativní modré tóny. QR kresba, obvod, stíny a přesná cena jsou nezměněné. Světlý symbol aktivace dostal kontrastní modrý podklad.

### Přímý nativní zdroj palety

Pouze aktuální iPhone projekt `native/LazenskyCommanderApp`. Přečteny `LazenskyCommanderApp/CommanderDashboardStyle.swift` a `Shared/CommanderBrandAssets.swift`. Použité tokeny jsou skutečné Colors.background `#1542BA`, backgroundDeep `#102884`, panel `#1743A5`, locationBlue `#65E5FF`, textSecondary `#F2F6FF` a nativní panelový odstín `#1E447E`. Světlé plochy vznikají výslovným CSS smícháním těchto barev s nativní světlou textovou barvou; nejsou vydávány za screenshot aplikace. Starý macOS Komandér nebyl otevřen ani použit. Nativní soubory ani assety nebyly upravovány.

### Dodatečné opravy z auditu

- Aktivní navigace se nově počítá podle skutečné pozice sekcí, nikoli podle pořadí odkazů. Přesunutí Instalace v menu tak nerozbíjí aktivní stav. V Kontakt zůstává aktivní pouze kontaktní CTA, nikoli Instalace. Přidáno odpovídající `aria-current`.
- Domů a firemní logo používají explicitní okamžitý návrat na pozici 0; předchozí dočasné přepínání CSS scroll-behavior někdy ponechávalo plynulý posun nedokončený. Stejný návrat používá již existující reset při reloadu.
- Zvětšený kalendář má správně zarovnanou ikonu, nadpis a text; nepřebírá automatické centrování obrázků a odstavců z obrazového lightboxu. Klonovaný náhled v otevřeném detailu už nepředstírá další tlačítko pro zvětšení.
- Písmo procedur při menších desktopových šířkách bylo sjednoceno na nejméně 14 px.

### Závěrečné ověření

Skutečný Chrome render při 1920, 1440, 1180, 1200, 1220 a 390 px; snímky celých jednotlivých sekcí při 1920, 1440, 1200 a 390 px. Dále kontrola 17 šířek 320–1920 px bez horizontálního přetečení, rozbitých obrázků, chybných kotev, deformací poměrů, textu menšího než 14 px a zachycených JS výjimek. Ověřena jednořádková desktopová navigace, oba pětiprvkové desktopové řádky, společná levá osa úvodu Funkcí a dlaždic, žádné překrytí textů kroků, pořadí sekcí, menu na mobilu, obrazový lightbox a Escape, neodesílající formulář, kalendáře přes kartu / náhled / lupu a modal bez horizontálního přetečení. Reload, logo i Domů po předchozím posunu končí na scrollY 0 a aktivním Domů. Aktivní stavy Funkce / Co chystáme / Pro lázně / Instalace / Kontakt jsou správné i přes odlišné pořadí položek menu.

Kontrola SHA-256 potvrzuje, že všechny obrazové a ostatní podklady webu jsou nezměněné. HTML sekcí Hero, O nás, Užitečné obrazovky, Jak to funguje, Kalendář a widgety, Co chystáme, Pro lázně, Instalace a Kontakt je shodné se začátkem tohoto kola. Zachováno transparentní Bohanes logo, nativní screenshoty, QR SVG kresba, pořadí sekcí a firemní kontakt / footer.

Omezení: autentický foreground alarm není dostupný a nebyl nahrazen napodobeninou. QR jsou stále označené jako nefunkční návrhy. Kontaktní e-mail a telefon zůstávají neověřené; formulář výslovně neodesílá. K této úpravě nebylo potřeba měnit Watch / Live Activity / Dynamic Island assety ani testovat jejich skutečný běh.

Následují historické záznamy předchozích kol.

## Předchozí doladění – 4. 11. 2026 (architektura a firemní identita)

V tomto kole byly změněny přesně `site/index.html` a tento `README.md`. Stávající pracovní verze byla zachována. Žádný commit, push, deployment ani zásah do produkce.

- Hlavní navigace: Domů / O nás / Lázeňský Commander / Funkce / Pro lázně / Co chystáme / Instalace, samostatné CTA Kontaktujte nás. Funkce je obyčejný anchor `#funkce`, bez dropdownu. Logo má větší prostor, samostatnou pevnou šířku a větší mezery od navigace. Na desktopu je plná navigace v jednom řádku; Menu je jen pro menší šířky.
- Nová mateřská oblast „Funkce Lázeňského Commanderu“ obsahuje stávající části Jak to funguje, Alarmy a upozornění a Kalendář a widgety. Všechny jsou stále viditelné při běžném scrollování. Žádné tabs, accordion ani skrytý obsah. Staré kotvy na jednotlivé části nadále fungují. Aktivní položka navigace zůstává Funkce i uvnitř vnořených částí.
- Jak to funguje je jeden propojený tok se společnou linkou, šipkami a světlejší modrou plochou; odstraněn vzhled pěti izolovaných vizuálních boxů. Původní obsah, nativní symboly a miniatura telefonu zůstaly zachovány. Na mobilu tok pokračuje svisle. Ověřeno, že nadpisy kroků nepřekrývají popisy.
- Pět screenshotů Dnes / Týden / Pobyt / Info / Nastavení i pět kategorií pod nimi mají při 1440 a 1920 px shodnou horní hranu a jediný řádek. Grid kategorií je explicitně zajištěn od 1280 px.
- Kontakt má firemní světlou paletu Bohanes, původní barevné logo nahoře, název firmy, Petr Bohanes / Zakladatel a teprve potom E-mail / Telefon. Kontakty zůstávají pravdivě neověřené. Formulář má všech pět původních polí a výslovně neodesílající stav; backend nebyl přidáván.
- Zápatí má stejnou firemní barevnost a původní barevné logo. Claim a kompaktní sloupce zůstávají. Výška při 1440 i 1920 px je 273 px (272 px před tímto kolem + nová 1px horní linka), při 390 px 446 px (předtím 474 px).
- Co chystáme: sjednoceno horní zarovnání úvodního textu a nadpisu, zachovány stejné výšky vizuálů a zarovnané nadpisy karet. Obrázky, obsah i pravdivé stavy jsou nezměněné.
- Hero včetně obou kalendářových dlaždic zůstalo beze změny. Kalendář a widgety si zachovává již vyvážené rozměry a nativní poměry. Pro lázně je beze změny. Instalační podtóny, QR kresba a přesná cena „299 Kč včetně DPH za aktivaci jednoho lázeňského pobytu.“ zůstaly zachovány.

### Ověření tohoto kola

- Cíleně znovu přečten pouze současný iPhone/Xcode projekt `native/LazenskyCommanderApp`: AlarmKitAdapter, PhysicalAcceptance scénáře, zpracování foreground v hlavní aplikaci a Live Activity preview. Foreground handler spravuje obnovu stavu; nalezená systémová preview jsou Lock Screen Live Activity. Ověřen běžící Simulator „Commander Design iPhone 16“. Autentický foreground alarm nebyl dostupný. Nový screenshot alarmu ani jeho napodobenina nevznikly. Starý macOS Komandér nebyl otevřen ani použit.
- HTML produktových sekcí Hero, O nás, Užitečné obrazovky, Jak to funguje, Alarmy, Kalendář a widgety, Pro lázně, Co chystáme a Instalace je shodné s výchozí verzí tohoto kola; změnilo se vložení společného rodiče Funkce a cílené styly. SHA-256 všech ostatních souborů webu zůstává shodné. Všechny screenshoty, nativní PNG, SVG loga a QR kresba jsou nezměněné. Nativní projekt nebyl upravován.
- Vizuální kontrola 1440, 1920 a 390 px; automatická kontrola 17 šířek 320–1920 px bez vodorovného přetečení, rozbitých obrázků, chybných kotev, deformace poměrů, textu menšího než 14 px nebo zachycených JS výjimek. Na desktopu je jediný řádek navigace a skryté Menu. Ověřeny oba pětiprvkové řádky, viditelnost všech tří funkčních částí, zarovnání alarmových bloků a nadpisů roadmapy, mobilní menu, detail obrázku a neodesílající formulář.

Následující záznamy popisují předchozí kola a původ již existujících podkladů.

## Předchozí doladění – 4. 11. 2026 (rozestupy a proporce)

V tomto kole byly upraveny pouze `site/index.html` a tento `README.md`. Pokračuje se ve stávající lokální pracovní verzi. Žádný commit, push ani nasazení; produkce nebyla použita.

- Hlavička využívá až 1840 px šířky, má vzdušnější rozestupy a mírnější váhu textu. Všech devět odkazů i CTA zůstávají v jednom řádku při desktopových šířkách. Menu se používá pouze pod 1100 px.
- Hero má dvě samostatné kompaktní dlaždice Apple Kalendář / Google Kalendář s pravdivými stavy. Pravý produktový vizuál a shodné zaoblení iPhone/Android zůstaly zachovány.
- Při šířkách od 1280 px je všech pět původních screenshotů v jediném řádku: Dnes, Týden, Pobyt, Info, Nastavení. Pod nimi je samostatný plnošířkový pás Procedury s pěti současnými nativními kategoriemi. Původní obrazové soubory nebyly upraveny.
- Tok Jak to funguje má světlejší navy/modré pozadí a panely. První krok je „Procedurový rozpis“. Nadpis „Z procedurového rozpisu až k upozornění.“ i původní tok zůstávají.
- Kalendář a widgety mají pouze zmenšené a vyvážené vizuály při zachování nativních poměrů. HTML sekcí O nás, Alarmy, Kalendář a widgety, Pro lázně a Co chystáme je proti začátku tohoto kola shodné. Assety Watch / Live Activity / Dynamic Island se neměnily.
- Instalační karty ponechávají jemné plné modrošedé, zelené a tyrkysové podtóny. QR SVG kresba je nezměněná. Cena zůstává přesně „299 Kč včetně DPH za aktivaci jednoho lázeňského pobytu.“
- Vedle formuláře přibyl identifikační blok Bohanes Technologies / Petr Bohanes / Zakladatel bez adresy a bez vymyšleného e-mailu či telefonu. Pět polí a jasně neodesílající stav formuláře zůstávají zachovány.
- Zápatí má nad navigací claim „Technologie pro skutečný pobyt“ a podtitul „Digitální nástroje pro přehlednější pobyt, jednodušší orientaci a včasné informace.“ Čtyřsloupcová navigace zůstává kompaktní. Výška zápatí je 272 px na desktopu a 474 px při 390 px; proti výchozí verzi tohoto kola se nezvětšilo.

### Ověření současného iPhone/Xcode projektu

Jediný nativní zdroj tohoto kola: `/Users/petrbohanes/Documents/Bohanes Technologies/web-site-sync/native/LazenskyCommanderApp`. Starý samostatný macOS Komandér nebyl otevřen ani použit jako zdroj.

- V aktuálním `project.pbxproj` ověřeny reference na sdílený branding / asset catalog, Home Widget, WatchCommanderView a Live Activity target.
- `site/native-ui/commander-mark.png` je po bajtech shodný s aktuálním `Shared/BrandAssets.xcassets/BrandCircularMark.imageset/BrandCircularMark-384.png`.
- V současném `Shared/CommanderBrandAssets.swift` ověřeny kategorie rehabilitace, elektroléčba, vodoléčba, masáže a teplo/zábaly, jejich symboly a barvy. Ověřeny současné Small/Medium/Day Overview widget komponenty, WatchCommanderStateView a komponenty Live Activity / Dynamic Island.
- Cíleně prohledány současné AlarmKit, preview a lokální možnosti Simulatoru. Autentický foreground alarm nebyl dostupný. Žádný náhradní screenshot nebyl vytvořen.
- Nové nativní exporty ani snímky Simulatoru v tomto kole nevznikly. SHA-256 všech ostatních souborů webu je shodné se začátkem tohoto kola. QR SVG kresba a pravý hero vizuál zůstaly beze změny.

### Kontrola lokálního webu

Vizuálně zkontrolovány rendery při 1440, 1920 a 390 px. Automatická kontrola 17 šířek 320–1920 px prošla bez vodorovného přetečení, rozbitých obrázků, chybných kotev, deformovaných poměrů a zachycených JS výjimek. Desktopová navigace má jediný řádek a skryté Menu. Pět screenshotových karet má při 1440 i 1920 px stejné rozměry a společnou horní hranu. Alarmové bloky zůstávají zarovnané. Ověřeno mobilní menu, detail obrázku a neodesílající formulář.

Neověřeno v tomto kole: skutečný alarm při otevřené aplikaci, běh na fyzických Apple Watch / skutečném Dynamic Island a funkční backend formuláře. Kontaktní e-mail a telefon zůstávají neověřené. Původní nativní podklady a jejich omezení jsou popsány níže; následující soupis předchozího kola je historický.

## Předchozí doladění – 3. 11. 2026

V tomto kole byly změněny pouze `site/index.html` a `README.md`. Nové soubory projektu nevznikly. Následující katalog nových PNG a exportéru patří k předchozímu kolu a zůstává zachován.

- Plná navigace od 1100 px, bez desktopového tlačítka Menu. Ve středních desktopových šířkách je zmenšený gap, logo, CTA a vodorovné paddingy; text odkazů zůstává 14 px. Menší tablet/mobil používá funkční Menu.
- Hero zachovává původní pravý produktový vizuál. Pod platformními kartami přibyl kompaktní odkaz s pravdivým stavem kalendářových propojení. Obě platformní karty mají stejný radius 18 px.
- Horní zarovnání hero, brandingu, O nás a dotčených sekčních hlaviček. Příběh O nás zůstává o orientaci v procedurovém rozpisu.
- Galerie při 1440 px je přesná 3 × 2 mřížka: Dnes / Týden / Pobyt; Info / Nastavení / Procedury. Všech šest karet má shodné rozměry 410 × 575 px. Pět původních screenshotů se nezměnilo; šestá karta používá existující nativní ikony kategorií.
- Nadpis toku: „Z procedurového rozpisu až k upozornění.“ Ikony, nadpisy i popisy kroků jsou zarovnané, původní design toku zůstává.
- Alarmy tvoří tři stejnoměrné bloky: Nastavení předstihu → Systém iOS / alarm → Commander. Používá se existující skutečný screenshot Nastavení, referenční systémový alarm a skutečný přehled Dnes. Jejich horní hrany a popisy při desktopové šířce leží na společných osách.
- Znovu cíleně prohledány AlarmKitAdapter, PhysicalAcceptance scénáře, Xcode preview a možnosti aktuálního Simulatoru. Dohledaná preview jsou Live Activity, nikoliv autentický foreground systémový alarm. Grafická Simulator.app stále není dostupná a simctl privacy nenabízí AlarmKit oprávnění. Nový autentický foreground snímek nebyl nalezen; žádná napodobenina nebyla vytvořena. Omezení předchozího běhu s blokující systémovou žádostí zůstává platné.
- HTML sekcí Kalendář a widgety, Pro lázně a Co chystáme je shodné s výchozím stavem tohoto kola. U Co chystáme je pouze sjednocena výška prostoru vizuálu pro horní zarovnání karet. Všechny assety, screenshoty, QR SVG vzory a pravý hero vizuál jsou kontrolou SHA-256 / přímým porovnáním potvrzeny jako nezměněné.
- Instalační karty mají pouze jemný plný modrošedý, zelený a tyrkysový nádech. QR kresba, 1px obvod a absence horních pruhů / stínů zůstaly zachovány.
- Přesný text ceny: „299 Kč včetně DPH za aktivaci jednoho lázeňského pobytu.“
- Formulář má všech pět požadovaných polí ve správném pořadí, s propojenými labely a autocomplete. Odesílání zůstává jasně označené jako připravované a disabled.
- Čtyřsloupcové zápatí má malé firemní logo a krátký claim vlevo, dva sloupce odkazů, kontaktní sloupec a copyright pod tenkou čárou. Výška na desktopu je 47 % předchozí výšky.
- Vizuální kontrola proběhla při 1440 a 390 px. Automatická kontrola 17 šířek prošla bez přetékání, rozbitých obrázků, neplatných kotev, deformace poměrů a zachycených JS výjimek. Zkontrolováno také otevření/zavření menu, detail obrázku a pravdivý neodesílající stav formuláře.
- Žádný commit, push ani deployment. Produkce nebyla použita ani změněna.

## Rozsah změn

Změny zůstávají v pracovním stromu. Nebyl proveden commit, push ani deployment a nebyla měněna produkce. Zůstává `noindex,nofollow`.

Povinná první fáze proběhla před úpravou HTML: byly dohledány a přečteny skutečné nativní brand assety, logotyp, Widget Extension, Watch UI, Live Activity/Dynamic Island a AlarmKit testovací scénáře.

### Změněné existující soubory

- `site/index.html`: jednotný design vycházející z nativních panelů Commanderu; kompaktní jednořádková desktopová navigace; původní produktová identita; čistý widget v hero; příběh papírového rozpisu v O nás; původní screenshoty galerie; jeden vizuální tok Jak to funguje; jasné rozlišení alarmu a aplikace; čisté nativní widgety; vizuální kalendářové karty s pravdivým stavem; pilot; Watch/Live Activity/Island náhledy; sjednocené instalační karty bez horních pruhů; označené QR návrhy; kontaktní formulář s vypnutým odesíláním; kompaktní čtyřsloupcové zápatí.
- `README.md`: tento soupis, zdroje podkladů, ověření a omezení.

### Nový zdrojový soubor

- `native-preview-export.py`: opakovatelný lokální export skutečných SwiftUI komponent do PNG. Kompiluje core knihovnu a exportní host v dočasném adresáři. Nativní zdrojové soubory neupravuje. Standardně ukládá do `site/native-ui`; první volitelný argument určuje jiný výstupní adresář. Vyžaduje nainstalovaný Swift/Xcode toolchain.

### Nové obrazové soubory v `site/native-ui/`

| Soubor | Původ |
| --- | --- |
| `commander-mark.png` | Původní BrandCircularMark-384.png z nativního asset catalogu, beze změny. |
| `commander-wordmark.png` | Export původního CommanderGlassHeader včetně loga a gradientového logotypu. |
| `widget-medium.png` | CommanderMediumHomeWidget z Widget Extension; 338 × 158 pt, raster 3×. |
| `widget-small.png` | CommanderSmallHomeWidget z Widget Extension; 158 × 158 pt, raster 3×. |
| `widget-day.png` | CommanderDayOverviewWidgetView z Widget Extension; 158 × 158 pt, raster 3×. |
| `watch.png` | Export skutečného WatchCommanderStateView; obsah aplikace pro Watch. |
| `live-activity.png` | Export CommanderProcedureLockScreenView s nativním prezentačním modelem. |
| `dynamic-island.png` | Rozbalený produktový náhled ze skutečných nativních Island komponent. |
| `dynamic-island-compact.png` | Kompaktní produktový náhled z nativního loga a Island timing komponenty. |
| `symbol-document.png` | Nativní SF Symbol doc.text. |
| `symbol-convert.png` | Nativní SF Symbol arrow.triangle.2.circlepath. |
| `symbol-check.png` | Nativní SF Symbol checkmark.shield. |
| `symbol-bell.png` | Nativní SF Symbol bell.badge.fill. |
| `symbol-calendar.png` | Nativní SF Symbol calendar. |
| `symbol-clock.png` | Nativní SF Symbol clock.fill. |
| `google-calendar.png` | Oficiální produktová ikona Google Kalendáře z gstatic.com. |

Původních pět screenshotů v `site/screens`, soubory kategorií v `site/procedure-icons`, firemní SVG loga a celý nativní projekt v tomto kole nebyly změněny. Staré fotografie widgetů a Live Activity zůstávají v adresáři, ale HTML je nikde nepoužívá. Jediný zachovaný referenční snímek z `real-ui` je skutečný systémový alarm zamčeného iPhonu.

## Přímé zdroje v nativním projektu

- `native/LazenskyCommanderApp/Shared/BrandAssets.xcassets/BrandCircularMark.imageset/BrandCircularMark-384.png`
- `native/LazenskyCommanderApp/Shared/CommanderBrandAssets.swift`
- `native/LazenskyCommanderApp/LazenskyCommanderApp/CommanderDashboardStyle.swift`: CommanderGlassHeader, typografie, barvy a povrchy.
- `native/LazenskyCommanderApp/LazenskyCommanderLiveActivity/LazenskyCommanderHomeWidget.swift`: skutečné malé a podlouhlé widgety.
- `native/LazenskyCommanderApp/LazenskyCommanderWatchApp/WatchCommanderView.swift` a `WatchVisualAssets.swift`.
- `native/LazenskyCommanderApp/LazenskyCommanderLiveActivity/LazenskyCommanderLiveActivity.swift`: Lock Screen, kompaktní a rozbalené Island komponenty.
- `native/LazenskyCommander/Sources/LazenskyCommanderCore/CommanderActivityPresentation.swift`: skutečný prezentační model.
- `native/LazenskyCommanderApp/LazenskyCommanderApp/AlarmKitAdapter.swift` a `PhysicalAcceptance/PhysicalAcceptanceApp.swift`: alarm v čase leaveAt, systémový alert-only režim a izolované testovací scénáře.
- `native/LazenskyCommander/Sources/LazenskyCommanderCore/CommanderNotifications.swift`: Live Activity a samostatné Watch alarmy jsou v aktuálním MVP vypnuté.
- `native/LazenskyCommanderApp/Shared/CommanderDesignPreviewSchedule.json`: časy a místa v ukázce rozpisu v sekci O nás.
- `docs/google-calendar-sync.md`: implementovaná synchronizace rozpisu do kalendářů Procedury a Jídlo.

## Jak byly náhledy získány

Export používá původní SwiftUI kód a skutečný core model. Kvůli samostatnému exportnímu hostu proběhly pouze tyto adaptace v dočasné kopii zdroje:

1. Původní PNG a JSON mapy se načítají přímo ze zdrojových cest místo z aplikačního bundlu.
2. WidgetKit container background se v exportním hostu vykreslí stejným gradientem na rozměru widgetu. Obsah, fonty, barvy a rozložení zůstávají z původního rendereru.
3. Watch ScrollView je pro statický raster nahrazen nescrollujícím kontejnerem se stejným obsahem. Úmyslně se neexportuje prázdná macOS scrollovací plocha.
4. Live Activity dostává přímo nativní CommanderActivityPresentation místo systémově vytvářeného ActivityViewContext.
5. Dynamic Island je produktový náhled ze skutečných leading/center/trailing/bottom a timing komponent. Není označován za screenshot skutečného systémového Islandu. Vnější black capsule je exportní prezentace.
6. Obsah náhledů používá pouze demonstrační data a platné minutové časy, žádné osobní rozpisy.

Exportní host používá macOS SwiftUI/SF Symbols. Pixelová shoda se systémovým iOS/watchOS hostem nebyla ověřena; nejde o nově navržené widgety ani obrazovky.

Rozměry widgetů pro třídu displeje iPhonu 16 (393 × 852 pt): malé 158 × 158 pt, podlouhlý 338 × 158 pt. Ověřeno proti tabulce [Apple HIG — Widgets](https://developer.apple.com/design/human-interface-guidelines/widgets). Exporty jsou v trojnásobném rozlišení a web zachovává jejich poměr stran.

Oficiální Google Calendar asset: https://www.gstatic.com/images/branding/product/2x/calendar_2020q4_48dp.png

## Lokální ověření

- Původní native core a exportní SwiftUI host byly úspěšně zkompilovány.
- Finální uložený `native-preview-export.py` byl spuštěn z projektové cesty s odděleným dočasným výstupem: úspěšně reprodukoval exporty.
- Všechny nativní zdroje použité při exportu zůstaly beze změny; ověřeny SHA-256 otisky.
- Po obou větších změnách byl lokální web vyrenderován při 1440 a 390 px a vizuálně prohlédnut.
- Finální kontrola při 320, 360, 390, 760, 768, 1024, 1099, 1100, 1152, 1200, 1280, 1339, 1340, 1366, 1440, 1600 a 1920 px: bez horizontálního přetékání, rozbitých obrázků a chybějících lokálních kotev.
- Od 1100 px je všech devět položek navigace v jednom řádku. Na menších šířkách je menu; hlavička se nezalamuje.
- Obrázky zachovávají poměry stran. U kontrolovaných kategorií, kalendářových položek, nadpisů toku a galerie nebylo zjištěno ořezávání webového textu.
- iPhone a Android platformní karty mají stejný radius 18 px.
- Tři instalační karty mají stejný 1px obvod a žádný box shadow; horní ozdobné pruhy byly odstraněny.
- Zápatí má čtyři kompaktní sloupce, malé logo vlevo a samostatnou tenkou copyright řádku. Jeho výška při 1440 px klesla z 584 na 276 px.
- Mobilní menu funguje. Zvětšení obrázků funguje a Escape jej zavře.
- Formulář má pole jméno / organizace či lázeňské zařízení / e-mail / telefon / zpráva. CTA odesílání je disabled; handler navíc zabraňuje submitu a nepředstírá úspěšné odeslání.
- Žádná fotografie widgetů, Live Activity ani oříznutý commander-glyph není použita v HTML.
- Bez zachycených JavaScript výjimek. Běžné kontrolované webové texty nejsou pod 14 px.

## Co zůstává neověřené nebo nedostupné

- AlarmKit: byl prohlédnut adapter i izolovaný physical acceptance scénář a spuštěn test `--single-renderer-probe` v iOS Simulatoru. Běh zablokovala skutečná systémová žádost o oprávnění. V připojeném prostředí není dostupná grafická Simulator.app ani její ovladatelné okno a simctl privacy nemá AlarmKit mezi podporovanými službami. Skutečné vyzvánění nad otevřenou aplikací proto nebylo nově zachyceno. Není tvrzeno, že to obecně na iOS nejde. Test byl uklizen a Simulator znovu spuštěn. Web nepoužívá falešnou náhradu screenshotu.
- Watch, Live Activity a Dynamic Island jsou čisté náhledy původních komponent, nikoli nový fyzický end-to-end test na hodinkách/iPhonu.
- Kalendářové miniatury jsou jasně označené ilustrace. Apple přímý vstup zůstává připravovaný; Google je implementovaný, ale produkční přihlášení a synchronizace nebyly v tomto kole spuštěny.
- QR vzory jsou dekorativní návrhy bez zakódovaného cíle, s textem „Připravujeme / nelze skenovat“. Nejsou distribučními ani aktivačními kódy.
- Finální e-mail, telefon a distribuční URL zůstávají neověřené. Odesílání formuláře vyžaduje implementaci backendu a jeho ověření.
- Safari, Firefox a fyzická zařízení nebyly testovány. Nativní zkracování názvů (ellipsis) je chování původního kódu, nikoli deformace obrázků webem.

## Lokální otevření

Web servírujte běžným statickým HTTP serverem s rootem v `site`. Pracovní náhled v této relaci: http://127.0.0.1:8876/

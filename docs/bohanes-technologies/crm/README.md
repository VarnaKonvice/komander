# Bohanes Technologies CRM

## Produkční web
https://bohanes-technologies-crm-petbohanes-8088.vercel.app/

## Účel
Hlavní obchodní CRM Bohanes Technologies.

Obsahuje zejména:
- lázeňská místa,
- firmy a kontakty,
- obchodní případy,
- aktivity,
- dokumenty,
- mapu,
- přehled klientů / obchodního potenciálu.

## Aktuální finální stav
Snapshot uložený v tomto repozitáři odpovídá produkční verzi po doplnění pilotního cíle:

- Teplice nad Bečvou zůstávají jedním lázeňským místem v mapě,
- pilotní cíl je **Lázeňský dům Moravan**,
- Moravan je viditelný v seznamu, mini kartě, tooltipu mapy a horním podtitulu detailu,
- při otevření velkého detailu se mini karta automaticky zavře.

## Mobilní iPhone rozhraní — 6. 11. 2026

CRM má samostatné mobilní rozložení pro iPhone: spodní navigaci, kompaktní hlavičku a vyhledávání, plnošířkovou mapu a seznam, detail lázní jako celou mobilní obrazovku, jednokolonové kontakty a formuláře. Přidána je podpora iOS safe-area přes `viewport-fit=cover` a `env(safe-area-inset-*)`, takže rozhraní respektuje oblast Dynamic Islandu a spodní home indikátor při otevření v Safari i po přidání na plochu. Desktopové rozložení zůstává samostatné.

## Doplňkový audit kontaktů — 5. 11. 2026

Veřejný katalog byl znovu porovnán s aktuálními oficiálními kontaktními stránkami. Počet ověřených kontaktů vzrostl z 134 na 161. Doplněny byly hlavně obchodní, rezervační, přijímací a provozní kontakty; hlavní telefon Jáchymova byl aktualizován na +420 410 000 510. Verze veřejné migrace je 2026-11-05.5.

## UX úprava detailu a mapy — 5. 11. 2026

- mini karta na mapě používá reprezentativní fotografii lázní a odděluje osobu od kontaktu obchodního oddělení,
- běžné otevření detailu vždy začíná na záložce **Přehled**; z modulu Kontakty se otevírá cíleně záložka **Kontakty**,
- adresy jsou v detailu zobrazované strukturovaně po blocích a nejsou současně duplikované v rychlém přehledu,
- hlavní telefon a e-mail jsou v jedné kartě **Kontaktní údaje**, editace je sbalená,
- pole **Co aktuálně řešíme** je oddělené soukromé obchodní pole businessNote; veřejný audit zůstává zachovaný a je sbalený pod **Ověření veřejných dat**,
- kontaktní karty zobrazují primárně jméno, funkci, telefon a e-mail; dlouhé zdrojové poznámky jsou sbalené pod **Ověření dat**,
- verified-records.json, generovaná veřejná data a fotografie nebyly touto UX úpravou změněny.

## Uložené soubory
- `docs/bohanes-technologies/crm/app/index.html` – kompletní aplikace,
- `docs/bohanes-technologies/crm/data/regions.json` – regionální mapová data,
- `docs/bohanes-technologies/crm/data/border.json` – hranice mapy,
- `docs/bohanes-technologies/crm/assets/symbol.svg` – schválený hlavní symbol,
- `docs/bohanes-technologies/crm/assets/symbol-navy.svg` – tmavá varianta symbolu,
- `docs/bohanes-technologies/crm/assets/favicon-final.svg` – finální favicon.

## Karlovy Vary — více provozovatelů
Záznam Karlovy Vary vědomě reprezentuje více nezávislých lázeňských provozovatelů. Hlavní rychlý telefon a e-mail v CRM patří Alžbětiným lázním (Lázně V., a.s.), protože jejich web a fotografie jsou použité jako primární reprezentativní položka. Pole IČO zůstává bez jediné hodnoty, protože pro celé město neexistuje jedno společné IČO; ověřená IČO jednotlivých provozovatelů jsou uvedena v poznámce a kontaktech.

## Další fáze
Další práce má navazovat doplňováním obsahu do stávající struktury CRM:
- kontaktní osoby,
- telefony a e-maily,
- firmy / provozovatelé,
- obchodní poznámky,
- stav obchodního případu.

Struktura a vizuální základ CRM se mají zachovat, pokud nebude výslovně rozhodnuto jinak.

## Důležité
Stabilní produkční adresa CRM je:
https://bohanes-technologies-crm-petbohanes-8088.vercel.app/

Při úpravách CRM se nemá vytvářet nový odkaz pro běžné používání; změny se mají nasazovat na stejnou stabilní adresu.

## Přenos mezi Macem a Mac Studiem — aktualizace 5. 11. 2026

Na obou počítačích otevři stejnou produkční adresu výše. Instalace ani kopírování aplikace není potřeba.

### Společné veřejné údaje

- Jediný ručně udržovaný datový soubor: [data/verified-records.json](data/verified-records.json).
- Obsahuje veřejně ověřené společnosti, adresy, kontakty, zdroje, země a schválené fotografické URL.
- Změnu tohoto souboru připraví pro nasazení příkaz `python3 build-data.py`; kontrola `node test-data.cjs`.
- Aplikace načítá soubor `site/crm-data.js` ze svého nasazení. Samotná změna JSON na GitHubu bez generování a nového nasazení aplikaci nezmění.
- Při dalším datovém vydání zvyš `VERIFIED_DATA_VERSION` v obou kopiích `crm-data-tools.js`. Migrace doplní prázdná pole nebo nahradí poslední známé veřejné hodnoty. Vlastní úpravy zachová.
- Podrobný výsledek a zbývající nejistoty: [DATA-AUDIT-2026-11-05.md](DATA-AUDIT-2026-11-05.md).

### Vlastní poznámky, kontakty a obchodní stav

Tyto změny se ukládají do prohlížeče daného počítače, ne na GitHub.

1. Na původním počítači otevři nabídku profilu **Profil (ikona osoby)** a vyber **Exportovat zálohu CRM**.
2. Soubor přenes na Mac Studio, například přes AirDrop nebo soukromý iCloud Drive.
3. Na Mac Studiu otevři CRM, nabídku **Profil (ikona osoby)** → **Importovat zálohu CRM** a vyber soubor.
4. Import nahrazuje obchodní údaje obsažených záznamů; po kontrole výzvu potvrď. Poslední import lze vrátit přes **Vrátit poslední import**.

Při střídavých úpravách na dvou počítačích nejprve přenes poslední zálohu. Import neumí slučovat souběžné změny.

### GitHub a skutečná synchronizace

Repozitář `VarnaKonvice/komander` je veřejný. Patří sem společný veřejný katalog a kód. Zálohy obsahující interní obchodní poznámky sem neukládej. Token GitHubu nikdy nevkládej do HTML/JavaScriptu.

Pro automatické sdílení všech změn je další vhodný krok soukromá databáze za serverovým API a přihlášením. Alternativou je soukromý datový repozitář za serverovou službou; samotný GitHub soubor neřeší bezpečné zápisy a konflikty. Takový backend zatím není vytvořen.

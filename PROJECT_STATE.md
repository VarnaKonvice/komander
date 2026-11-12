# Bohanes Technologies — stav projektu

Aktualizováno: 12. 11. 2026

Tento soubor je první zdroj pro orientaci v projektu. Před větší změnou zkontrolovat zde uvedené zdroje pravdy, větve, checkpointy a otevřené brány.

## 1. Zdroje pravdy

### Lázeňský Commander — iPhone / Swift PILOT 1
- Repo: `VarnaKonvice/komander`
- Větev: `lc/iphone-pilot-1.0`
- Commit: `91d2d71f1b2691375f5301dfecfec407053e68e4`
- Verze: `1.0 (12)`
- Tag: `checkpoint/iphone-pilot-1.0-build12`
- Stav: schválený technický zdroj pravdy pro PILOT 1.
- Starý macOS Commander se nepoužívá jako zdroj pravdy.
- Swift testy 12. 11. 2026: `318/318 PASS`.

### Bohanes Technologies — web
- Aktivní pracovní/produkční větev: `web/minimal-platform-split-20261111`
- Schválený checkpoint: `639c8021a866d180ebe04ceb384a7e36614b0312`
- Tag: `checkpoint/web-approved-2026-11-12`
- Stav: schválený vzhled webu, mobilní standalone shell, launcher Bohanes Technologies/CRM/HQ.
- Tato větev byla 12. 11. 2026 fast-forwardem začleněna do `main`.
- Instalovaný iPhone web clip zatím používá stabilní Vercel alias této větve; větev proto nemažeme.

### Hlavní větev `main`
- Obsahuje schválený web a CRM historii z předchozích auditních větví.
- HQ profilový commit `f33fc07` byl 12. 11. 2026 přenesen do `main` samostatně.
- `main` je integrační historie projektu; produktové pilotní větve zůstávají samostatné, dokud nejsou fyzicky a produktově uzavřené.

### CRM
- Veřejný katalog: `docs/bohanes-technologies/crm/data/verified-records.json`
- Generování: `python3 docs/bohanes-technologies/crm/build-data.py`
- Kontrola: `node docs/bohanes-technologies/crm/test-data.cjs`
- Stav 12. 11. 2026: 36 záznamů, 36 fotografií, 161 ověřených kontaktů, test PASS.
- Veřejná data patří do GitHubu.
- Soukromé obchodní poznámky, stavy a vlastní editace jsou dnes v `localStorage` konkrétního prohlížeče. Nepatří do veřejného repozitáře.
- Dokud nevznikne soukromý backend, používat export/import CRM zálohy a uchovávat ji mimo veřejný GitHub.

### Bohanes HQ
- Profil: `docs/bohanes-technologies/hq/PETR-BOHANES-PROFIL-PRO-HQ.md`
- HQ je zatím integrační/řídicí vrstva; není považováno za hotový backend.

## 2. .NET / MAUI implementace

Repo: `VarnaKonvice/lazensky-commander-dotnet` (private)

### iOS review
- Větev: `review/filip-ios-pilot-1`
- Commit: `041641d`
- Účel: iOS-only C#/.NET review proti Swift PILOT 1.
- Dřívější evidence: 108/108 C# testů, iOS Simulator build PASS.
- Stav: review build, nikoli náhrada instalované Swift aplikace.

### Android
- Větev: `feat/android-pilot-1`
- Commit: `22bad78`
- Obsahuje Android platformní adaptéry, kalendář, alarmy, notifikace, widget a acceptance nástroje.
- Stav: pokročilá větev; dokončit až po uzavření společného Core a iOS review.

### Swift reference uvnitř .NET
- `.tools/swift-reference`
- Aktuálně zaostává o jeden commit: `01da2f7` vs. správný zdroj `91d2d71`.
- Před další migrací aktualizovat read-only reference na `91d2d71` a znovu ověřit manifest/paritu.

### Toolchain
- Dokumentované úspěšné buildy používaly .NET 10 / MAUI.
- 12. 11. 2026 aktuální shell Mac Studia nenašel příkaz `dotnet`.
- Před další .NET implementací obnovit/připnout reprodukovatelný SDK + MAUI workload a sladit Xcode/workload.

## 3. Distribuce

### Web / CRM
- Vercel projekty `bohanes-technologies-web` a `bohanes-technologies-crm` jsou aktivní.
- Web i CRM mají produkční deploymenty ve stavu READY.
- iPhone web clips nejsou Xcode aplikace a nemají sedmidenní expiraci.

### Nativní iPhone Commander
- Současná lokální Xcode instalace používá vývojové podepisování.
- Personal Team profil má krátkou platnost; není vhodný pro stabilní pilot.
- Cíl: Apple Developer Program + TestFlight pro Petra/Filipa a později externí pilot.

## 4. Produktový kontrakt, který se nemá znovu vymýšlet

Zdroj:
- `docs/bohanes-technologies/product/LAZENSKY-COMMANDER-ZAKAZNICKY-TOK-V1.md`
- `LAZENSKY-COMMANDER-CENOVA-POLITIKA.md`
- `LAZENSKY-COMMANDER-UZIVATELSKY-NAVOD.md`
- `LAZENSKY-COMMANDER-PODMINKY-SLUZBY-DRAFT.md`
- `LAZENSKY-COMMANDER-APP-STORE-RELEASE.md`

Platné směry:
- B2C 1–15 dní: 129 Kč.
- B2C 16–35 dní: 299 Kč.
- Partnerská cena pro lázně: 249 Kč podle cenové politiky.
- B2B billing vzniká až při první úspěšné aktivaci pobytu.
- SMS je hlavní distribuční cesta pro partnerský pobyt.
- QR je fallback a sám nesmí převzít osobní rozpis bez ověření vlastnictví.
- Fotografie/PDF/OCR jsou budoucí vstupní adaptéry do stejného kanonického rozpisu.
- Backend, SMS/OTP, QR ověření, OCR/PDF, billing a platby nejsou vydávány za hotové funkce PILOT 1.

## 5. Historické / referenční větve

Nemažou se bez samostatné kontroly.

- `lc/reference-build11 @ aacec35` — historický referenční build před PILOT 1.
- `web/ia-v2-apple-android-20261111 @ b19f781` — alternativní IA pokus; není předkem schváleného webu.
- `crm/address-fields-20261105`, `crm-contacts-audit-20261105`, `crm-ux-cleanup-20261105` — jejich relevantní obsah je již v hlavní historii.
- starší cenové/designové webové větve z 6. 11. — zachovat jako historii, ne jako zdroj pravdy.
- `hq-petr-profile-20261105` — jediný užitečný unikátní commit byl přenesen do `main`.

## 6. Aktuální brány před dalším rozšiřováním

### Gate A — pořádek a data
- [x] vytvořit tento stavový dokument
- [x] označit iPhone a web checkpointy tagy
- [x] začlenit schválený web do `main`
- [x] přenést HQ profil do `main`
- [x] zařadit staré větve jako historické/referenční
- [x] vytvořit aktuální soukromou CRM zálohu z Chrome do iCloud Drive (`Documents/Bohanes Technologies/CRM Backups`); 36 záznamů, 163 lokálních kontaktů, SHA-256 evidován při exportu
- [x] Karlovy Vary znovu prověřeny: hlavní telefon/e-mail patří Alžbětiným lázním; jedno IČO záměrně není uvedeno, protože záznam reprezentuje více nezávislých provozovatelů; CRM test znovu PASS

### Gate B — uzavření iPhone PILOT 1
- [x] Swift 318/318 testů
- [ ] fyzický průchod Dnes / Týden / Pobyt / Info / Nastavení
- [ ] offline restart se zachováním snapshotu
- [ ] validní JSON import + zamítnutí neplatného/staršího importu
- [ ] skutečný AlarmKit ring/stop na podporovaném iOS
- [ ] widgety na fyzickém telefonu
- [ ] Apple Kalendář pouze po ručním zapnutí + kontrola bez duplicit
- [ ] `.ics` export do Files/Kalendáře
- [ ] zapsat výsledky fyzické akceptace proti konkrétní verzi telefonu/OS/build
- [ ] Apple Developer Program / TestFlight pro stabilní pilot

### Gate C — .NET review
- [ ] obnovit reprodukovatelný .NET 10 / MAUI toolchain
- [ ] aktualizovat `.tools/swift-reference` na `91d2d71`
- [ ] znovu spustit C# testy a iOS build
- [ ] Filipova technická review
- [ ] teprve potom integrační větev pro iOS review + Android

## 7. Pravidlo další práce

Nejdřív dokončit Gate A, potom Gate B, potom Gate C.
Nový backend/OCR/platby/Android rozšiřovat až po fyzicky uzavřeném iPhone pilotu a po stabilizaci sdíleného Core.

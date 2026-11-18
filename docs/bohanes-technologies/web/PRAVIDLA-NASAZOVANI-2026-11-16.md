# Bohanes Technologies – uložení a nasazování webu

Schválený stav (16. 11. 2026): pracovní web s kontakty a sjednoceným zápatím (platby jako dlaždice v pravé části, sociální sítě v jedné řadě dole na desktopu).

- **GitHub `main`**: průběžný zdroj pravdy pro web, bez potřeby vytvářet nové ZIP archivy.
- **Pracovní web na všech zařízeních**: https://bohanes-technologies-ukazka.pages.dev/ – samostatný Cloudflare Pages projekt `bohanes-technologies-ukazka`.
- **Publikování pracovní verze**: GitHub Actions `bohanes-web-preview.yml` se spouští při změnách souborů webu ve větvi `main`, ověřuje je a **po nastavení repozitářového tajemství `CLOUDFLARE_API_TOKEN`** publikuje výhradně do `bohanes-technologies-ukazka`. Toto tajemství zatím není na GitHubu nastavené: CI proto správně provede jen kontrolu, automatické nasazení přeskočí. Do té doby lze pracovní web bezpečně nasazovat lokálně z uloženého GitHub `main` pomocí autorizovaného Wrangleru na Mac Studiu. Neobsahuje produkční doménu.
- **Ostrý web**: https://bohanes-technologies.cz/ – musí zůstat na stránce „Připravujeme“ až do dalšího výslovného schválení.
- **Ostré vydání**: GitHub Actions `bohanes-web-cloudflare.yml` je omezen na výslovně schválený tag `web-release-*`. Běžný push do `main` ostrý web nenasazuje.
- **Záložní archiv poslední schválené verze**: Git branch `archive/bohanes-technologies-web-ukazka-2026-11-16`, tag `bohanes-web-ukazka-approved-2026-11-16`, commit `c0d2210fda5c5964d1cb15c09bd6adb301fa1718`.
- **CRM**: https://bohanes-technologies-crm.pages.dev/ – oddělené a chráněné přihlášením; nedotýká se nasazování firemního webu.

Tato pravidla nesmějí být měněna za účelem automatického nasazování na ostrou doménu bez výslovného schválení uživatele.

## Veřejné spuštění firemního webu – 18. 11. 2026

Uživatel schválil zahájení ostrého provozu firmy před dalšími lázněmi. Od tohoto data je `bohanes-technologies.cz` určena pro skutečnou veřejnou prezentaci (nikoli jen placeholder). Zůstávají pravdivá sdělení, že samotná aplikace Commander není veřejně ke stažení či placené aktivaci. Přístup do CRM vede přímo do samostatného zabezpečeného CRM; veřejný web neobsahuje fiktivní testovací přihlášení.

**Bezpečné zveřejnění:** Python skript `prepare-public-release.py` sestaví pouze veřejné stránky, potřebné fotografie, video V6, mapu webových cest a roboty. Vylučuje interní adresáře `site/hq`, `site/crm` a `site/koncept-8-2` a testovací přístup. Ostrý projekt je stále `bohanes-technologies` a lokální Wrangler umí nasadit schválený release přímo z GitHub `main`. Běžný push do `main` nadále nesmí spustit nasazení ostrého projektu; workflow `bohanes-web-cloudflare.yml` vyžaduje výslovně vydaný tag `web-release-*` a funkční GitHub API token, který k datu 18. 11. 2026 zatím chybí. Pro první spuštění se používá místní autorizované nasazení z přesně uloženého Git commitu; žádná automatická změna ostré domény.

## OPRAVA – ZÁKAZ OSTRÉHO SPUŠTĚNÍ (18. 11. 2026)

**Tento odstavec přebíjí jakoukoli starší formulaci v dokumentu, která označuje veřejné spuštění za schválené.** Uživatel jednoznačně upřesnil: záměrem je dokončení a teprve **poté**, orientačně před pobytem kolem 30. ledna 2027, ostré spuštění. Žádné povolení ke zveřejnění dne 18. 11. 2026 nedal. Předčasné nasazení bylo vráceno; produkční doména byla ověřena v původním režimu „Připravujeme“. Všechny dříve vystavené odkazy na produkt vracejí 404.

- Stav do odvolání: veřejná produkční stránka jen „Připravujeme“, **žádné ceny, funkce ani produktový prodej**.
- GitHub `main`: zdrojové kódy k budoucímu spuštění, **nikoliv** souhlas s publikováním.
- Testovací web: https://bohanes-technologies-ukazka.pages.dev/ (dostupný pro interní kontrolu).
- Produkční placeholder a blokátor ostatních cest: `docs/bohanes-technologies/web/production-hold/`.
- Produkční workflow bylo změněno na **výhradně ručně spouštěné s výslovným potvrzovacím vstupem**. Žádný push ani tag nesmí sám zveřejnit produkt.
- Neplánovat automatické spuštění na 30. 1. 2027 ani jindy bez nového výslovného příkazu uživatele.

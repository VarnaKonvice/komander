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

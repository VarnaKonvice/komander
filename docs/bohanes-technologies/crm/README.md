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

## Uložené soubory
- `docs/bohanes-technologies/crm/app/index.html` – kompletní aplikace,
- `docs/bohanes-technologies/crm/data/regions.json` – regionální mapová data,
- `docs/bohanes-technologies/crm/data/border.json` – hranice mapy,
- `docs/bohanes-technologies/crm/assets/symbol.svg` – schválený hlavní symbol,
- `docs/bohanes-technologies/crm/assets/symbol-navy.svg` – tmavá varianta symbolu,
- `docs/bohanes-technologies/crm/assets/favicon-final.svg` – finální favicon.

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

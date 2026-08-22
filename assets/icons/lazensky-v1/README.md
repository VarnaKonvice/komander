# Lázeňský Commander — Icon Pack v1

Schválený asset balík odvozený výhradně z obrázku **Icon Set v1 (Full)**.

- Žádné nové ikony nebyly vygenerovány.
- `icons/512`: iPhone / větší UI
- `icons/256`: PWA / běžné karty
- `icons/128`: Watch / Dynamic Island / malé plochy
- `icon-map.json`: kanonické mapování procedur včetně priority shod a neutrálního fallbacku bez falešné kategorie
- `colors.json`: jednotné barvy
- `reference/icon-set-v1-full-approved.png`: schválený zdrojový vizuál

Pravidlo: stejný artwork napříč PWA, iPhone, AlarmKit/Live Activity a Apple Watch; na menších plochách pouze zmenšená verze.

Klasifikace vybírá shodu s nejvyšší `priority`, při shodné prioritě nejdelší klíčové slovo. Neznámá procedura zachová zdrojový název a nepřiřadí žádný `key` ani obrázek.

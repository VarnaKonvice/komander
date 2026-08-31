# Lazensky Commander Brand Foundation v1

Schvaleny brand system oddeluje znacku aplikace od procedurnich ikon v
`assets/icons/lazensky-v1`.

## Kanonicke role

- `reference/approved-reference.png`: zavazna vizualni reference.
- `masters/launcher-full-1024.png`: plny launcher artwork pro PWA a iPhone.
- `masters/circular-mark-1024.png`: kruhova znacka pro Watch a kompaktni plochy.
- `masters/small-glyph-1024.png`: lotos, kapka a vlny bez hodin pro nejmensi plochy.
- `pwa/`: odvozene browserove exporty; neupravuji se rucne.

Launcher a Watch App Icon jsou nepruhledne PNG. Kruhova znacka a maly glyph
maji skutecne pruhledne okoli. Apple zaobleni ani masky nejsou soucasti artworku;
aplikuje je system.

Kanonicke barvy znacky jsou v `assets/icons/lazensky-v1/colors.json`. Procedurni
mapovani, akcenty a fallback zustavaji samostatnym kontraktem v
`assets/icons/lazensky-v1/icon-map.json`.

## Vygenerovani masteru

Tri master artworky byly vytvoreny vestavenym image generation nastrojem podle
schvalene reference. Zadani zachovalo lotos, modrou kapku, modre vlny, zlate
hodiny, tmavy navy zaklad, proporce a premiovy svetelny jazyk reference. Nasledne
byly pouze technicky pripraveny rozmery, alfa kanal a platformni exporty.

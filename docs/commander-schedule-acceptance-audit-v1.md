# Commander Schedule Acceptance Audit v1

## Cíl

Commander nesmí považovat rozpis za důvěryhodný jen proto, že je JSON syntakticky a interně platný. Bezpečný stav vzniká až po několika nezávislých vrstvách kontroly:

1. **Zdrojový papír / fotografie** – neměnný originál.
2. **Kanonický rozpis** – jediný aktivní zdroj dat pro Dnes, Týden, Pobyt, widgety, Watch, alarmy a Live Activities.
3. **Strukturální audit** – automatické kontroly dat.
4. **Zdrojová reconciliace** – každý řádek originálu musí mít právě jednu odpovídající kanonickou událost a naopak.
5. **Projekční audit** – efektivní předstih a `leaveAt` pro každou událost.
6. **Fyzický read-back** – ověřit, co je skutečně naplánováno v iOS/AlarmKit, ne pouze co aplikace chtěla naplánovat.

Žádná jednotlivá vrstva sama o sobě nesmí zobrazit finální stav „ověřeno“.

## Pobyt není fixně 28 dnů

Počet dnů se nikdy nehardcoduje. Vždy se odvozuje inkluzivně z `stay.dateFrom` a `stay.dateTo`.

- běžný pobyt: například 28 dnů,
- prodloužení: změna `dateTo`, např. na 35 dnů,
- audit po změně znovu přepočítá rozsah a pokrytí.

`28` je běžný případ, nikoli invariant systému.

## Změny během pobytu

Rozpis musí mít historii revizí. Nový papír se nikdy nemá „nasypat“ k předchozím datům bez pravidla. Každý nový zdrojový balíček má mít:

- vlastní `sourceRevision`,
- datum a čas převzetí,
- rozsah, který nahrazuje (`coverageFrom` / `coverageTo`),
- odkazy/hashy zdrojových fotografií,
- důvod změny, pokud je známý (nový rozpis, změna lékařem, změna na žádost pacienta, prodloužení pobytu),
- výsledek reconciliace.

### Pravidlo aplikace revize

Nový papír **nahrazuje** kanonické události pouze ve svém deklarovaném rozsahu. Události před tímto rozsahem zůstávají historicky beze změny. Nová revize nesmí vytvořit skryté duplicity.

Při prodloužení pobytu se nejdřív aktualizuje `stay.dateTo`, potom se aplikuje nový zdrojový balíček pro přidané dny a celý audit se spustí znovu.

## Stav auditu

Navržené stavy:

- `NEOVĚŘENO` – data existují, ale ještě nemají úplnou kontrolu proti originálu.
- `KONTROLA` – existuje varování nebo nevyřešený rozdíl.
- `ROZPIS OVĚŘEN` – 0 chybějících, 0 navíc, 0 rozdílů vůči zdroji.
- `ALARMY OVĚŘENY DO <čas>` – fyzický read-back potvrdil systémové alarmy do konkrétního horizontu.

„ROZPIS OVĚŘEN“ a „ALARMY OVĚŘENY“ jsou dvě různé věci.

## Strukturální audit – první kostra

`CommanderScheduleAudit` kontroluje už na úrovni core:

- platnost současného canonical kontraktu,
- existenci a platnost `dateFrom` / `dateTo`,
- počet dnů pobytu odvozený z data od–do,
- události mimo pobyt,
- obsahově duplicitní události i při různých `stableId`,
- časové překryvy jako povinný bod k ruční kontrole,
- dny pobytu bez jediné události jako povinný bod k ruční kontrole,
- součty všech událostí / procedur / jídel.

Tato vrstva **neumí potvrdit shodu s papírem**. To bude samostatná source-reconciliation vrstva.

## Zdrojová reconciliace – další krok

Pro každý řádek originálu vytvořit nezávislý záznam:

`datum + čas od + čas do + název + lokalita + druh + sourcePage/sourceRow`

Poté provést obousměrné párování:

- source → canonical: každý zdrojový řádek má právě jeden protějšek,
- canonical → source: každá kanonická událost má právě jeden zdrojový řádek.

Finální gate:

- missing = 0,
- extra = 0,
- mismatched fields = 0,
- unresolved = 0.

## Předstihy / odchod

Současný Commander už podporuje více úrovní nastavení předstihu:

1. konkrétní událost,
2. typ procedury nebo jídla,
3. lokální výchozí hodnota,
4. hodnota konkrétní události ze zdrojového rozpisu,
5. typová hodnota ze zdrojového rozpisu,
6. výchozí hodnota rozpisu.

Acceptance audit proto musí pro každou událost uložit a ověřit:

- efektivní počet minut,
- zdroj této hodnoty,
- výsledný `leaveAt`,
- shodu s AlarmKit projekcí.

Předstihy nejsou součástí originálního procedurálního času; mění pouze okamžik odchodu/alarmu.

## Fyzický read-back

Po přijetí nové revize rozpisu nebo změně předstihu:

1. vytvořit alarmovou projekci,
2. naplánovat ji,
3. přečíst skutečný stav z platformy,
4. porovnat `stableId`, `startAt`, `leaveAt` a projekční revizi,
5. uložit horizont, do kterého je stav skutečně ověřen.

Aplikace nesmí říkat „alarmy v pořádku“, pokud pouze úspěšně zavolala plánovací API.

## Live Activities

Live Activity je prezentační vrstva, ne bezpečnostní autorita. Může selhat nebo nebýt viditelná bez toho, aby to změnilo platnost rozpisu nebo alarmů. Zítřejší práce na Live Activities má vycházet z ověřeného kanonického rozpisu a z téže projekce předstihů.

## Předstihy – UI

Současná obrazovka Předstihy funkčně dává smysl, ale používá systémový `Form`, proto její řádky působí skoro černě a vizuálně se odlišují od Commanderu. Funkční logiku zatím neměnit. Později pouze přestylovat řádky na stejné `commanderCard` povrchy jako zbytek aplikace.

## Doporučené pořadí další práce

1. dokončit source-reconciliation datový model,
2. přidat audit report do diagnostiky aplikace,
3. přidat revizní merge/replacement pravidla,
4. otestovat 28 → změna několika procedur → 35 dnů,
5. napojit fyzický AlarmKit read-back na audit report,
6. teprve potom znovu rozjet ostré Live Activities.

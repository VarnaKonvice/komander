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

## Provozní očekávání pro Petrův pobyt

Tato pravidla jsou **kontrolní očekávání**, nikoli univerzální právní invarianty:

- neděle: 0 léčebných procedur a očekávaná snídaně + oběd + večeře,
- pondělí–sobota: očekávání alespoň 3 procedur denně,
- sobota se proto kontroluje stejně jako ostatní léčebné dny, ale nižší počet je pouze warning k ověření proti papíru,
- běžná denní formální návštěva sesterny / kontrola sestrou se **nepočítá jako procedura**, pokud není výslovně uvedena v procedurálním rozpisu,
- lékařská nebo sesterská kontrola se později může modelovat jako samostatný typ události, ale nesmí uměle zvyšovat počet procedur.

Důvod pro warning místo blokující chyby: veřejné předpisy a informace pojišťoven určují podmínky a délku lázeňské péče, ale nenašli jsme obecné veřejné pravidlo, které by pro každou indikaci a každého poskytovatele právně nařizovalo přesně 3 procedury každý Po–So. Někteří poskytovatelé a odborné materiály běžně uvádějí 3 procedury denně a neděli jako klidový režim. Commander proto takový vzorec používá jako silnou anomální kontrolu, ne jako náhradu skutečného papíru.

## Zdrojové revize a reconciliace

Kostra `CommanderScheduleSourceRevision` nyní uchovává:

- identitu revize,
- čas převzetí,
- rozsah `coverageFrom` / `coverageTo`,
- důvod změny,
- hashe zdrojových fotografií/souborů,
- jednotlivé zdrojové řádky včetně stránky.

`CommanderScheduleSourceReconciler` provádí obousměrné párování zdrojového papíru proti kanonickému rozpisu ve stejném rozsahu. Rozlišuje:

- přesnou shodu,
- chybějící zdrojový řádek,
- kanonickou událost navíc,
- jednoznačný near-match s konkrétně vypsanými rozdílnými poli.

Near-match se nikdy automaticky neopravuje. Je pouze diagnostikou pro člověka.

## Překryvy nejsou automaticky chyba

Časový překryv je **kontrolní anomálie**, ne automatické odmítnutí rozpisu.

Reálné příklady, které musí Commander umět přijmout po potvrzení:

- jeden fyzioterapeutický blok obsahuje více dílčích cvičení, jejichž časy se na papíře překrývají,
- krátká procedura se překryje se začátkem 45minutového jídelního okna,
- procedura začne ještě před koncem jídla, ale po reálném přesunu zbývá dost času.

Audit proto rozlišuje:

- `procedure-overlap-review` – procedura × procedura,
- `meal-procedure-overlap-review` – procedura × jídlo.

U jídla report počítá **přímý časový překryv** a kolik minut z jídelního okna zbývá. Čas přesunu mezi lokalitami se zatím automaticky neodečítá, protože bez explicitního modelu vzdáleností by to byl odhad.

Příklad: večeře 17:30–18:15 a procedura 17:30–17:40 → přímý překryv 10 min, z jídelního okna zbývá 35/45 min; Commander upozorní, ale dovolí člověku situaci potvrdit.

## Potvrzení očekávané výjimky

Warning lze ručně potvrdit jako očekávanou výjimku. Potvrzení obsahuje:

- `scheduleVersion`,
- jednoznačný `reviewKey`,
- čas potvrzení,
- volitelnou poznámku.

Důležité bezpečnostní pravidlo: potvrzení platí jen pro **stejnou verzi kanonického rozpisu**. Po nové revizi papíru / změně rozpisu se stejná anomálie musí znovu zkontrolovat.

Blokující `error` nelze potvrzením warningu obejít. Stav `ROZPIS OVĚŘEN` může vzniknout jen při:

- 0 blokujících chybách,
- 0 nepotvrzených warningech,
- přesné source-to-canonical reconciliaci.

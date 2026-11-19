# Offline import papírového rozpisu

## Ovládání

1. V **Pobytu** klepni na **Vyfotit rozpis** nebo vyber fotografie. Na iPhonu je stejný import dostupný také při přidání prvního pobytu.
2. U vícestránkového rozpisu přidej všechny stránky. U rozpisu vyfoceného po částech nech na každém snímku vidět hlavičku s datem nebo datum příslušné části.
3. V náhledu zkontroluj počet událostí. U zvýrazněného řádku lze opravit jednotlivé údaje, nahradit fotografii nebo výslovně vynechat řádek, který do rozpisu nepatří.
4. Klepni na **Použít rozpis**. Při prvním pobytu na iPhonu dokonči stávající finální potvrzení pobytu.

## Pravidla shodná na obou platformách

- Rozpoznávače předávají text, jistotu a obdélníky v souřadnicích od levého horního rohu. Interpretace má vlastní hranici před stavbou kanonického rozpisu. Případný další interpretátor může předat data až této hranici.
- Sloupce určuje poloha buněk a rozpoznaná hlavička. Postranní tabulky s oddělenými hlavičkami se zpracují samostatně. Bez rozpoznaného sloupce místa lze převzít místo označené slovem jako „místnost“ nebo „budova“.
- Datum se dědí z předchozího čitelného řádku ve stejné části téže fotografie. Krátké datum s dnem a měsícem lze doplnit z doloženého roku na stránce. Chybějící rok bez opory a neexistující datum vyžadují opravu. Datum se automaticky nepřenáší na nezávislou fotografii.
- Čas začátku a volitelný konec pocházejí ze stejného řádku. Sloupec **Odchod** ani samotný čas ze sloupce **Konec** nesmí zastoupit začátek. Velikost a poloha textu slouží k přiřazení buněk. Pokud parser nedokáže prokázat přiřazení, předá nejasnost k opravě.
- Název procedury se kopíruje z podkladu. Údaj o místě zůstane „Neuvedeno v rozpisu“, pokud v podkladu chybí. Při neuvedeném konci je pro kanonický formát konec shodný se začátkem. Předstih a čas odchodu dál počítá stávající projekce.
- Záznamy se stejným datem, časem začátku a normalizovaným názvem se spojí. Rozdílný vyplněný konec, místo nebo podezřele blízký odlišný začátek se zobrazí ke kontrole. U každé zbývající nejasnosti musí uživatel údaj opravit, vyměnit snímek nebo výslovně vynechat nepatřičný řádek.
- Výstup je kanonický rozpis schématu 1 s lokálním časem Europe/Prague. Validace rozpisu a výměna aktivního pobytu používají existující import. Náhled ani neúspěšný import aktivní pobyt nemění.
- Android používá ML Kit s přibaleným modelem. iOS používá Apple Vision a systémové skenování dokumentů. Korekce perspektivy se zkouší při čitelném okraji, originál zůstává dostupný v relaci výběru. Fotografie ani text aplikace neodesílá na server.

## Reprodukovatelné podklady

- Stejný soubor `offline-ocr.json` v obou repozitářích testuje pravidla na souřadnicích a očekávaných kanonických událostech.
- Nativní iPhone repozitář obsahuje v `native/LazenskyCommanderApp/OCRAcceptance` generátor obrázků `GenerateImages.swift`, kontrolu parseru a Vision `run.sh` a průchod vyhrazeným simulátorem `simulator.sh`.
- Android spustí sdílené případy příkazem `dotnet test tests/LazenskyCommander.Tests`. Pro zkoušku obrázků bez sítě použij oddělenou instalaci na emulátoru, vyber vygenerované obrázky v galerii a porovnej náhled s očekávanými výsledky.
- iPhone. Z kořene `native/LazenskyCommanderApp` spusť `swift OCRAcceptance/GenerateImages.swift /tmp/commander-paper-qa` a `bash OCRAcceptance/run.sh /tmp/commander-paper-qa/*.png`. Kontrolu jádra spustíš přes `swift test --package-path ../LazenskyCommander`.

## Fyzické ověření na Galaxy A55 a iPhonu 16

1. Na každém telefonu použij připravený testovací build. Pokud výrobní aplikace obsahuje aktivní rozpis, před výměnou aplikace ověř stejný identifikátor a podpis a možnost návratu k předchozímu sestavení. Neodinstalovávej stávající aplikaci kvůli zkoušce.
2. Vyfoť stejný vytištěný rozpis rovně, šikmo, při horším světle a případně po částech. První snímek zkus přímo fotoaparátem, další také přes Galerii nebo Fotky.
3. Pořiď dva překrývající se snímky. Zkontroluj, že každá procedura je v náhledu jednou, a porovnej datum, začátek, konec, název i místo s papírem. Záměrně začni i snímkem, kde chybí datum. Zkus upravit nejasný řádek a nahradit snímek.
4. Před potvrzením zavři náhled a ověř, že původní rozpis je stále v aplikaci. Teprve s připraveným ověřeným rozpisem potvrď import. Zapni letový režim a ověř znovu náhled, načtení uloženého rozpisu po restartu, zachovaný předstih, widget a volitelný export do kalendáře. Čas odchodu porovnej s časem procedury.
5. Zapiš výsledky pro každý telefon zvlášť. Testovací obrázky jsou syntetické a nenahrazují fotografie skutečného lázeňského formuláře.

## Podepsaný iPhone balíček

Na Macu lze sestavit nový podepsaný balíček pro již přidaný iPhone přes
\`bash OCRAcceptance/export-iphone.sh /absolutni/cesta/Lazensky-Commander-iPhone-OCR.ipa\`.
Postup ověří podpis a platnost vloženého profilu a vytvoří IPA bez instalace do telefonu.
Fyzická instalace vyžaduje platný profil pro konkrétní zařízení.
## Import celého dokumentu

Náhled ukazuje údaje z hlavičky, předepsané procedury a naplánované události. V náhledu lze opravit hlavičku, název, počet a poznámku předepsané procedury i jednotlivou událost.

- **Pobyt** ukazuje termín, ubytování, údaje o pacientovi a předepsané procedury s počty.
- **Info** ukazuje ošetřujícího lékaře, diagnózu a poznámku, pokud je dokument obsahuje.
- **Dnes a Týden** a alarmy vycházejí z naplánovaných událostí. Záhlaví, tiskové údaje a souhrn předepsaných počtů události nevytvářejí.

PDF se čte po stránkách. Na iPhonu PDFKit a od Androidu 15 PDF Renderer poskytují text a jeho polohu. Stránky bez použitelné textové vrstvy, otočené stránky bez spolehlivé geometrie na iPhonu a PDF na starším Androidu používají lokální rozpoznání vykreslené stránky.

Osobní a zdravotní údaje z hlavičky a poznámky k předpisům jsou součástí místního rozpisu a do alarmového ani kalendářového exportu se nevkládají. Import nepoužívá vzdálený endpoint. Nativní iPhone ukládá papírový rozpis do aplikační složky vyřazené ze zálohování a Android má systémové zálohování aplikace vypnuté.

Případy v `full-document-ocr.json` na obou platformách pokrývají celý vícestránkový podklad, datum mimo pobyt, konflikt údajů, překryv snímků a 79 anonymizovaných dvojic času a názvu z geometrie pěti stran staršího průkazu z Darkova. Polohy jsou odvozené z rozpoznání původního skenu. Testovací texty a časy jsou náhradní hodnoty. Skutečné jméno, zdravotní údaje ani sken nejsou součástí Gitu.

Příkaz `swift OCRAcceptance/GenerateDocument.swift /tmp/commander-paper-qa` vytvoří dvoustránkové PDF s textovou první stranou a rastrovou druhou stranou. Příkaz `bash OCRAcceptance/run.sh /tmp/commander-paper-qa/whole-document-mixed.pdf` ověří dvě události, hlavičku a předpis.

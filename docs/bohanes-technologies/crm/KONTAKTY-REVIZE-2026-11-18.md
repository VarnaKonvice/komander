# Bohanes Technologies CRM – kontakty a kvalita dat, 18. 11. 2026

První průchod rozšíření přímých firemních kontaktů z veřejných zdrojů.

## Rozsah a skutečný stav

- Referenční ověřený soubor `data/verified-records.json`: **36 lokalit, 165 osob**, z toho **81 zapsaných e-mailů**, **75 telefonů**. Před revizí 161 osob, 74 e-mailů, 68 telefonů.
- Aplikace navíc kombinuje původních **41 lázeňských míst** s ověřenými záznamy; při čistém načtení bez místních úprav vychází **41 míst, 178 kontaktů, 95 zapsaných e-mailů, 89 telefonů**.
- V databázi je **9 samostatných odhadů** jmenných e-mailů podle opakovaného vzoru adres jiných veřejně uvedených zaměstnanců. Tyto adresy jsou `suggestedEmail`, **nikoli `email`**. V CRM mají výstrahu „NEOVĚŘENO, NEODESÍLAT“ a neobsahují klikací odkaz `mailto:`.
- U některých osob v historických datech je funkční/oddělení e-mail (`info@`, `reditel@`, `obchod@` aj.). V UI je označen jako sdílený/funkční a nelze jej zaměňovat za jmennou adresu.

## Nově doložená osobní / pracovní spojení

- **Karel Kalivoda – Mariánské Lázně:** přímý e-mail a telefon v dokumentu města České Budějovice z února 2025. Pozor: aktuálnost kontaktu není potvrzená k dnešku. Zdroj: https://www.c-budejovice.cz/sites/default/files/obsah/Magistrat/Informace/Archiv-poskytnutych-informaci/2025/prilohy_1.pdf
- **Mgr. Helena Kokešová, MUDr. Lucie Quiquerez, Mgr. Lucie Halušková – Janské Lázně:** oficiální vedení a přímé kontakty https://www.janskelazne.com/vedeni-lazni/
- **Ing. Petr Teichmann – Karlova Studánka:** oficiální vedení https://www.horskelazne.cz/o-nas/vedeni-lazni
- **MUDr. Kateřina Eretová – Alžbětiny lázně:** funkční email lékaře a přímý telefon https://spa5.cz/kontakt/
- **Jiří Fadler – Kostelec:** jmenný e-mail v pracovním inzerátu https://personalka.cz/1092375, telefon v jiné pracovní roli na oficiálním webu golfového klubu https://golfkostelec.cz/kontakt; před použitím ověřit aktuálnost.
- **Lázně Darkov:** číslo +420 596 373 301 ani `prislusnaosoba@darkov.cz` nelze použít jako obchodní spojení Lenky Krótké, protože slouží pro oznamování protiprávního jednání. https://www.laznedarkov.cz/kontakt

## Obchodní rozesílka

Záznam ve veřejném CRM neznamená svolení k marketingu. Newsletter lze v ČR zasílat při splnění právních podmínek (§ 7 zákona č. 480/2004 Sb.) a pravidel ÚOOÚ; samotná dostupnost e-mailu na internetu ani rozdělení 50 sdělení do série po pěti denně nezakládá oprávnění. Nejprve evidovat souhlasy či způsobilé existující zákaznické vztahy, odhlášení, zdroj kontaktu a datum, poté schválit text. U neověřených odhadů nikdy automaticky neodesílat.

Odkaz na výklad ÚOOÚ: https://uoou.gov.cz/cinnost/obchodni-sdeleni/casto-kladene-otazky-k-zakonu-c-4802004-sb

## Nasazení a ochrana

CRM: https://bohanes-technologies-crm.pages.dev/ (přístup heslem; bez ověření data 401). Soubor `site/_worker.js` chrání soubory; heslo/klíče nejsou zdrojové kódy a nesmí být commitovány. Lokální uživatelské obchodní poznámky jsou uloženy v `localStorage`, mohou se lišit mezi zařízeními. Ověřené veřejné doplnění se načítá s novou verzí do dříve existujících záznamů bez přepisování vlastních obchodních úprav.

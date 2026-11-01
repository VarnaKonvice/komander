# Bohanes Technologies – AI a systémová architektura

## Základní koncept
- Hermes = hlavní koordinátor firemních procesů.
- ThinkingCap Qwen = lokální model pro Hermes.
- LM Studio není pro první verzi nutné.
- Radovan = strategická a konverzační vrstva pro Petra.
- Hermes = disciplinované provádění workflow.
- CRM = centrální evidence firem, kontaktů, obchodních případů, dokumentů a aktivit.

## První agentní role
- Procedury
- CRM
- Research
- Dokumenty
- Kontrolor

Později lze přidat marketing, finance/právo a další role podle skutečné potřeby.

## Procedury – správný význam
Procedurový vstup není ceník.

Klient po příjezdu do lázní dostane měsíční rozpis procedur bez cen. Procedurový agent má tento rozpis:
1. přečíst z PDF/fotky/skenu/formuláře,
2. převést do jednotné struktury,
3. přeložit do datového formátu Lázeňského komandéra,
4. označit nejasnosti místo domýšlení,
5. předat výsledek Kontroloru,
6. po validaci přiřadit ke konkrétnímu klientovi, pobytu a instalaci.

## Identita klienta, pobytu a instalace
Tyto identity musí být oddělené.

### 1. customer_id
Trvalá identita uživatele/klienta v systému Bohanes.
- nemění se při odinstalaci aplikace,
- může mít více pobytů,
- může používat více zařízení,
- může aplikaci odinstalovat a znovu nainstalovat.

### 2. stay_id
Jedinečný pobyt klienta.
- stejné customer_id může mít více stay_id,
- každý pobyt má svůj procedurový plán,
- eviduje lázně, datum pobytu a zdroj dokumentu.

### 3. installation_id
Identita konkrétní instalace aplikace na zařízení.
- je technická identita instalace,
- po reinstalaci se nesmí považovat za jediný zdroj identity klienta,
- server ji páruje s customer_id,
- jeden customer_id může mít během času více installation_id.

### Doporučené schéma
customer_id
  ├── stay_id 2026-001
  │    └── procedure_plan_id
  ├── stay_id 2027-004
  │    └── procedure_plan_id
  └── installations
       ├── installation_id A
       └── installation_id B

Díky tomu reinstalace aplikace neztratí historii klienta.

## Vazba formulář → klient → pobyt → instalace
Každý importovaný procedurový formulář musí získat:
- customer_id
- stay_id
- installation_id (pokud existuje)
- source_type = lázně / web / ruční import / jiný zdroj
- datum pobytu
- zdrojový dokument
- stav zpracování
- verzi převodu

## Zdroj instalace
U každé registrace evidovat:
- spa = klient přišel přes konkrétní lázně,
- web = přímý klient z webu,
- referral = doporučení,
- manual = ručně založený,
- unknown = zdroj neurčen.

Tím bude možné měřit, odkud klienti skutečně přicházejí.

## E-mailový dohled
Hermes má mít přístup k firemním schránkám v povoleném rozsahu.

První režim:
- kontrola nových e-mailů přibližně každých 5 minut,
- třídění podle firmy/kontaktu/tématu,
- přiřazení ke CRM,
- vytvoření úkolu, pokud z mailu plyne akce,
- upozornění Petrovi jen tehdy, když je potřeba reakce nebo rozhodnutí,
- návrh odpovědi může připravit,
- odeslání až po schválení.

## Kalendář a dostupnost Petra
Před vytvořením úkolu nebo schůzky má Hermes:
1. zkontrolovat kalendář,
2. zjistit reálné volné okno,
3. navrhnout čas,
4. po schválení zapsat událost,
5. připojit firmu, kontakt, telefon, e-mail a stručný kontext.

## Tok po poradě
Radovan → strukturovaný výstup → Hermes → CRM / úkol / kalendář / dokumenty / návrh e-mailu

## Pravidla bezpečnosti
- číst může široce,
- zapisovat jen do povolených systémů,
- mazat až po potvrzení,
- e-maily odesílat až po potvrzení,
- každý automatický zásah musí mít auditní stopu.

## Disk
První verze na interním SSD Mac Studia.
Rezerva: přibližně 80 GB.
Později lze modely, knowledge base, dokumenty a archiv přesunout na externí Thunderbolt SSD.

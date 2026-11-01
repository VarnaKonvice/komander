# Bohanes HQ

Firemní AI centrála Bohanes Technologies.

## Co je Bohanes HQ
Bohanes HQ je centrální koordinační vrstva pro obchod, CRM, procedury Lázeňského komandéra, dokumenty, e-mail a kalendář, research, právo, marketing, finance a kontrolu.

Technický základ první verze:
- Hermes Agent = orchestrátor workflow,
- ThinkingCap Qwen = lokální AI model,
- Mac Studio = první lokální provoz,
- CRM Bohanes Technologies = centrální evidence firem, kontaktů a obchodních aktivit.

## Agentní oddělení
- Obchod & CRM
- Procedury / Lázeňský komandér
- Právní oddělení
- Marketing
- Finance a účetnictví
- Dokumenty
- E-mail a kalendář
- Research & veřejné zdroje
- Kontrola a schvalování

## Role Radovana
Radovan zpracuje porady, nejednoznačná zadání, strategii a souvislosti. Výstup předá Bohanes HQ ve strukturované podobě. Bohanes HQ následně rozdělí úkoly agentům a provede definované workflow.

## Identita klienta, pobytu a instalace
Identity musí být oddělené:

- customer_id = trvalá identita klienta v systému Bohanes,
- stay_id = jeden konkrétní lázeňský pobyt,
- installation_id = jedna konkrétní instalace Lázeňského komandéra,
- procedure_plan_id = konkrétní procedurový plán pro daný pobyt.

Jeden customer_id může mít více stay_id a více installation_id.

## Aktivace Lázeňského komandéra
1. Klient stáhne aplikaci z App Store nebo Google Play.
2. Aplikace při prvním spuštění vytvoří installation_id a bezpečně se zaregistruje na Bohanes Backend.
3. Klient se spáruje s customer_id. Párování může proběhnout přihlášením, jednorázovým kódem nebo QR kódem.
4. Pokud klient přichází přes lázně, jednorázový kód/QR zároveň identifikuje konkrétní stay_id.
5. Po úspěšném spárování se jednorázový kód zneplatní.
6. Server eviduje vztah customer_id ↔ stay_id ↔ installation_id.

## Reinstalace aplikace
Installation_id není jediná identita klienta.

Po odinstalaci a nové instalaci může vzniknout nové installation_id. Klient se znovu ověří a nová instalace se připojí ke stejnému customer_id. Historie pobytů a procedur zůstává na serveru.

## Zpracování procedurového rozpisu
Procedurový dokument není ceník. Je to rozpis procedur konkrétního klienta během pobytu.

1. Do Bohanes HQ přijde procedurový formulář jako PDF, fotografie, sken nebo jiný podporovaný dokument.
2. Procedurový agent dokument přečte.
3. Převede obsah do jednotného datového formátu Lázeňského komandéra.
4. Nejasné položky nesmí domýšlet; označí je ke kontrole.
5. Kontrolní agent ověří strukturu a úplnost.
6. Výsledek získá procedure_plan_id a přiřadí se ke správnému customer_id a stay_id.
7. Bohanes Backend zpřístupní plán pouze autorizovanému klientovi.
8. Aplikace si procedury bezpečně stáhne ze serveru.
9. Push notifikace případně jen oznámí, že je nový plán připraven; citlivý obsah se neposílá v push zprávě ani běžným e-mailem.

## Evidence zdroje klienta
U registrace se eviduje source_type, např.:
- spa = konkrétní lázeňský dům,
- web = přímý klient z webu,
- referral = doporučení,
- manual = ruční založení,
- unknown = neurčeno.

## E-mail a kalendář
Bohanes HQ může:
- pravidelně kontrolovat povolené firemní schránky,
- třídit nové zprávy podle firmy, kontaktu a tématu,
- ukládat související aktivitu do CRM,
- připravovat úkoly a návrhy odpovědí,
- kontrolovat kalendář před návrhem termínu.

Citlivé akce jako odesílání e-mailů, mazání nebo zásadní změny mají v první fázi vyžadovat schválení.

Volitelně lze zřídit vlastní servisní adresu typu hq@bohanestechnologies.cz jako centrální vstupní schránku systému.

## Bezpečnostní princip
Server rozhoduje, který klient smí získat který procedure_plan_id. App Store ani Google Play neslouží jako zdroj identity klienta; pouze distribuují aplikaci.

## Infografika
Viz soubor: bohanes-hq-infografika.svg

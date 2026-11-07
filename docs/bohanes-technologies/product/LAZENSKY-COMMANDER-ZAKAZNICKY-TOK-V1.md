# Lázeňský Commander – schválený zákaznický tok v1

**Stav:** schválený produktový kontrakt pro PILOT 1 a následný převod do C#/.NET  
**Datum:** 7. 11. 2026

## Zásada

Aplikace pracuje s konkrétním pobytem (stayID). Rozhodnutí B2B/B2C se dělá podle konkrétních lázní a platnosti jejich smlouvy v okamžiku první aktivace pobytu.

Již aktivovaný B2B pobyt zůstává B2B do konce své aktivace, i když partnerská smlouva lázní později skončí.

Cena se určuje podle **počtu dní zbývajících do konce pobytu v okamžiku první aktivace**, nikoli podle původní délky pobytu.

## B2B – partnerské lázně

1. Lázně vytvoří běžný procedurový rozpis a znají své vlastní číslo pobytu.
2. Klient zvolí elektronické doručení rozpisu do telefonu. Tato volba musí být prokazatelně zaznamenatelná.
3. Lázeňský systém předá integrační vrstvě minimálně číslo pobytu, telefon určený pro doručení a procedurový rozpis.
4. Integrační vrstva vytvoří interní stayID, převede rozpis do kanonického formátu Commanderu a odstraní údaje, které Commander pro svou funkci nepotřebuje.
5. Klient dostane servisní SMS s odkazem na konkrétní pobyt.
6. Pokud Commander má, odkaz jej otevře. Pokud ne, vede k instalaci a po instalaci pokračuje v převzetí pobytu.
7. Commander zobrazí souhrn pobytu a tlačítko **Přijmout rozpis**.
8. Přijetím vznikne aktivace a vazba instalace Commanderu na stayID.
9. Pokud mají příslušné lázně v okamžiku aktivace platnou partnerskou smlouvu, klient neplatí. Aktivace se zapíše do B2B billingového přehledu.
10. Aktualizace stejného pobytu používají vyšší scheduleVersion; Commander je převezme a přepočítá alarmy.

### QR jako záložní cesta

Na tištěném procedurovém rozpisu může být QR odkaz na konkrétní pobyt. QR není primární distribuční cesta a není platební klíč.

Protože může být papír nebo fotografie QR dostupná jiné osobě, samotný QR nesmí být dostatečný k převzetí osobního rozpisu. Při použití QR se vlastnictví pobytu ověří jednorázovým kódem zaslaným na telefon evidovaný u pobytu.

## B2C – nepartnerské lázně / samostatný klient

1. Klient otevře Commander a zvolí **Přidat pobyt**.
2. Dodá procedurový rozpis (cílově fotografie nebo PDF jednotlivých listů).
3. Integrační vrstva rozpis převede do stejného kanonického formátu jako u B2B.
4. Klient před aktivací zkontroluje lázně, termín pobytu a připravený rozpis.
5. Server ověří, zda mají identifikované lázně v okamžiku aktivace platnou partnerskou smlouvu.
6. Pokud ne, jde o B2C aktivaci. Klient před nákupem uvidí cenu podle počtu zbývajících dní.
7. Po úspěšné platbě klient přijme pobyt; dále funguje stejný Commander jako u B2B.

Pro App Store verzi se digitální aktivace B2C nesmí navrhnout tak, aby obcházela pravidla Apple pro nákup digitálních funkcí. Platební implementace je samostatný adaptér a nesmí být součástí business logiky rozpisu a alarmů.

## Billing B2B

Účtovací událost vzniká až při úspěšné první aktivaci pobytu, nikoli při vytvoření rozpisu nebo odeslání SMS.

Minimální položka billingového přehledu:
- partnerské lázně,
- jejich číslo pobytu,
- interní stayID,
- datum a čas aktivace,
- počet zbývajících dní při aktivaci,
- použité cenové pásmo,
- účtovaná částka.

Lázně musí dostat měsíční přehled podle svých vlastních čísel pobytů. Konkrétní účetní formát (CSV, ISDOC, XML/API) je integrační detail a nemá měnit produktový kontrakt.

## Ochrana osobních údajů – návrhové pravidlo

Commander nemá pro párování potřebovat jméno, datum narození, pohlaví ani diagnózu.

Pro běžnou funkci jsou potřebné zejména:
- identifikátor pobytu,
- termín pobytu,
- procedury, časy a místa,
- technická identita instalace,
- dočasně telefon pro doručení/ověření B2B.

Pokud zdrojový dokument obsahuje další osobní nebo zdravotní údaje, integrační vrstva je nesmí bez funkční potřeby převádět do provozního datasetu Commanderu.

## Co je už implementováno v PILOT 1

PILOT 1 už obsahuje kanonický rozpis, verzování, validaci, offline snapshot, alarmy, předstihy, widgety, ruční JSON import a export kalendáře.

B2B/B2C aktivace, SMS, QR ověření, zpracování fotografie/PDF, billing a platební adaptér jsou schválený cílový kontrakt; v současném PILOT 1 nejsou vydávány za hotovou funkci.

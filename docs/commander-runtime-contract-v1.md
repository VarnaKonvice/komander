# Lázeňský Commander – runtime kontrakt v1

Pracovní větev: `lc/liveactivity-rebuild-v1`; základní HEAD rekonstrukce `b8cd52a`. Změny tohoto průchodu jsou do fyzického acceptance záměrně necommitnuté.

Tento kontrakt odděluje zdroj pravdy, projekce, jejich ověření a systémové limity. Cílem je, aby fyzický stav iPhonu byl dokazatelný a aby zelený stav aplikace neznamenal více, než skutečně ověřila.

## 1. Zdroj pravdy

- Jediný canonical zdroj lázeňského rozpisu je `data/schedule.json`.
- Každá publikovaná canonical změna zvyšuje `scheduleVersion` a aktualizuje `updatedAt`.
- Commander nikdy nezapisuje lokální předstihy zpět do canonical rozpisu.
- Lokální předstihy tvoří pouze lokální projekční revizi nad stejným canonical snapshotem.
- Google Kalendář, iPhone UI, AlarmKit/ActivityKit a Apple Watch jsou projekce stejného canonical rozpisu; žádná z nich nesmí být druhým zdrojem pravdy.

## 2. Přijetí rozpisu na iPhonu

Po přijetí nové platné canonical verze musí iPhone:

1. atomicky přijmout a uložit canonical snapshot,
2. odvodit efektivní časy odchodů,
3. reconciliovat AlarmKit,
4. provést skutečný systémový read-back budoucích AlarmKit alarmů,
5. připravit/reconciliovat Live Activity stav,
6. vytvořit a předat Watch snapshot stejné canonical identity a projekční revize,
7. zapsat trvalý diagnostický záznam tohoto průchodu.

Novější platný canonical snapshot se nesmí rollbacknout starší verzí. Stejná `scheduleVersion` s jiným canonical obsahem se nesmí přijmout jako legitimní aktualizace.

## 3. Stav připravenosti

Aplikace nesmí mít jeden neurčitý stav „ověřeno“ pro několik různých systémů.

### AlarmKit připraven

Lze tvrdit pouze tehdy, když pro všechny požadované budoucí alarmy existuje skutečný systémový AlarmKit záznam se správným:

- canonical stable ID,
- platformním ID,
- efektivním `leaveAt`,
- scheduleVersion / projekční identitou potřebnou pro prezentaci.

Read-back musí proběhnout po zápisu. Pouhé uložení lokálního mapování není důkaz.

### Live Activity připravena

Musí být vyhodnocena samostatně. `AlarmKit ověřeno` nesmí implicitně znamenat, že existuje správná Live Activity.

AlarmKit konfigurace nesmí spoléhat na Commander kartu volna ani Stop handoff. AlarmKit vlastní celý odchodový countdown a alert. Commander kontext procedury/jídla se připravuje samostatně se scheduled startem v `leaveAt`; do `startAt` ukazuje následující událost jako `Začíná za`, od `startAt` `Právě…`. Pro jeden projekční průchod musí AlarmKit, Commander Live Activity a Watch používat stejné zachycené `LeadTimeOverrides` a stejnou `projectionRevision`; změna lokálního předstihu během `await` se nesmí promítnout jen do jedné projekce. Jeho existence ani selhání nesmí měnit ověření AlarmKitu.

### Watch synchronizovány

Stav `queued` nebo `sent` není totéž jako `verified`. Diagnostika musí zobrazovat, zda Watch potvrdily stejnou projekční identitu. Selhání Watch nesmí rollbacknout canonical rozpis ani zrušit správné iPhone alarmy.

### Google Kalendář

Je serverová projekce canonical rozpisu a není důkazem, že iPhone stejnou verzi přijal nebo že vytvořil AlarmKit alarmy.

## 4. Trvalá diagnostika

Poslední souhrn nesmí přepsat jediný důkaz o předchozím selhání.

Každý synchronizační/recovery průchod musí do omezeného rotujícího ledgeru uložit alespoň:

- čas zahájení a dokončení,
- build identitu aplikace,
- kanál (`production` / E2E),
- canonical `scheduleVersion`,
- zdroj (`cached` / remote),
- projekční revizi,
- pro každý budoucí alarm: stable ID, title, startAt, efektivní leaveAt, uložené platformní ID,
- AlarmKit read-back: nalezené platformní ID a skutečný fixed alert time,
- vytvoření / update / cancel / cleanup a konkrétní důvod,
- Live Activity očekávaný stav, nalezený stav a případnou chybu request/update,
- Watch projection identity a stav `queued/sent/verified/failed`,
- aktivaci/úklid fallback notifikace,
- výsledek celého průchodu.

Záznam musí vznikat před opravnou mutací i po ní, aby následný foreground recovery nezničil důkaz o původním stavu.

## 5. Recovery

- Foreground/bootstrap/manual sync jsou legitimní recovery vstupy.
- Krátký odložený `Task` není background garance a nesmí být tak prezentován.
- Pokud je aplikace suspendovaná, změna souboru na GitHubu sama iPhone neprobudí.
- Již jednou ověřené systémové AlarmKit alarmy musí fungovat bez běžící aplikace.
- Nový canonical rozpis během suspendování vyžaduje samostatný garantovaný transport/probuzení; dokud není implementován, aplikace to nesmí tvrdit.

## 6. AlarmKit a Commander Live Activity

Schválený fyzický tok je:

1. před odchodem AlarmKit vlastní systémový countdown,
2. v `leaveAt` AlarmKit vlastní `VYRAZIT TEĎ` a skutečný alarm,
3. Stop pouze zastaví AlarmKit; **nevytváří ani neprodlužuje Commander Live Activity**,
4. po Stop má být už připravený Commander kontext viditelný bez hluché mezery a do `startAt` ukazovat `Začíná za …`,
5. v `startAt` se tatáž Commander prezentace lokálně přepne na `PRÁVĚ JÍDLO` / `PRÁVĚ PROBÍHÁ` a ukazuje čas do `endAt`,
6. v `endAt` přejde přes `staleDate` a časovou fázi na embedded další událost, případně na `Skončilo`; lokální Personal Team varianta negarantuje okamžitý skutečný end/dismissal bez dalšího execution time.

Produkční coordinator drží malý rolling window nejvýše dvou nejbližších neskončených Commander aktivit. Celé reconciliation operace jsou serializované i přes jejich interní `await`; z více současných odpovídajících instancí stejného canonical `stableId` se ponechá jediná preferovaná aktivní/pending instance a ostatní se ukončí. V této dvojici má pozdější událost vyšší `relevanceScore`, ale správnost UI na něm nesmí stát: pokud předchozí aktivita po `endAt` zůstane `.stale`, její embedded `nextEvent` se časově překlopí na stejný relevantní následující program. Budoucí aktivity používají ActivityKit scheduled start v `leaveAt`. Protože lokální scheduled start vyžaduje `AlertConfiguration`, používá se tichý bundled zvuk; iOS ale může systémový start alert vizuálně zobrazit. `staleDate` samo aktivitu neukončuje a nesmí být vydáváno za přesný lokální scheduler endu. Při každém návratu aplikace do `.active` proběhne nejdřív čistě lokální reconciliation Commander aktivit; teprve potom se uplatní desetisekundový throttle dražší cached/remote synchronizace. Skončené karty se tak uklidí a rolling window doplní i při rychlém foregroundu bez zbytečného síťového nebo AlarmKit průchodu.

## 7. Provisioning / obnova aplikace

Obnova aplikace je samostatný systémový tok a není součástí lázeňského `schedule.json`.

- Zdroj pravdy je skutečný embedded provisioning profil nainstalované aplikace.
- Reminder používá stabilní notification identifier.
- Doporučený čas obnovy je jeden den před expirací profilu. U sedmidenního profilu tedy upozornění přichází přibližně šestý den po instalaci/obnově; nejde o slepý opakovaný šestidenní timer.
- Otevření aplikace nesmí posouvat deadline na „dnes + 6 dní“.
- Pokud je obnova již due, doručené upozornění nesmí zmizet jen kvůli foregroundu.
- Teprve skutečně nový provisioning profil / nový platný termín smí staré delivered upozornění odstranit a naplánovat nový reminder.

## 8. Fyzický acceptance gate

Před každým ostrým fyzickým testem musí být před zamknutím telefonu zaznamenáno:

- přesný git SHA / build identita nainstalované aplikace,
- canonical scheduleVersion,
- seznam očekávaných budoucích alarmů,
- skutečný AlarmKit read-back každého z nich,
- stav Live Activity přípravy,
- Watch projection identity,
- provisioning reminder stav.

Fyzický PASS vzniká až skutečným průchodem na zařízení. CI/build ani diagnostika po následném recovery ho nenahrazují.

## 9. Co není zatím garantováno

Dokud nebude výslovně doplněn systémový background/push transport, není garantováno, že změna `schedule.json` během dlouhodobě suspendované aplikace sama probudí iPhone a okamžitě přepíše jeho lokální alarmy.

Stejná hranice platí pro refill Commander Live Activities. Lokální coordinator záměrně připravuje nejvýše dvě nejbližší neskončené události, protože pending/active Live Activities sdílejí systémový limit. Bez dalšího execution time aplikace není garantováno, že po prvních dvou připravených aktivitách vznikne třetí a další. Projekt výslovně přijímá tento bezplatný Personal Team kontrakt s foreground refillem; backend/APNs ani placené Apple Developer členství nejsou součástí cílové architektury. Celodenní garantovanou upozorňovací vrstvou proto zůstává AlarmKit, ne Commander Live Activity.

Tato mez nesnižuje spolehlivost již jednou ověřených budoucích AlarmKit alarmů; odděluje pouze distribuci nové canonical verze od jejího lokálního provedení.

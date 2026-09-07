# Lázeňský Commander – runtime kontrakt v1

Pracovní větev: `lc/native-stabilization-v2`.

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

Pokud AlarmKit konfigurace spoléhá na existující kartu volna/handoff, musí být tato konkrétní karta skutečně doložena. Pouhá existence předchozí události v rozpisu není dostatečný důvod k použití alert-only AlarmKit konfigurace.

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

## 6. Handoff a Live Activity

Schválený fyzický tok zůstává:

1. před odchodem jantarový stav / odpočet,
2. v `leaveAt` červený `VYRAZIT TEĎ`,
3. po Stop zůstává červený stav až do začátku události,
4. od startu zelený `PRÁVĚ PROBÍHÁ`.

Pokud není možné prokázat existenci handoff karty, AlarmKit nesmí být nakonfigurován tak, že právě tato karta je jediným vlastníkem předodchodové prezentace.

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

Tato mez nesnižuje spolehlivost již jednou ověřených budoucích AlarmKit alarmů; odděluje pouze distribuci nové canonical verze od jejího lokálního provedení.

# Lázeňský Commander – runtime kontrakt v1

Pracovní větev: `lc/alarm-liveactivity-unification-v1`. Aktuální architektura navazuje na historickou rekonstrukci `lc/liveactivity-rebuild-v1`, ale Stop-create handoff už není podporovaný.

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

AlarmKit vlastní celý odchodový countdown a alert. Commander Live Activity se připravuje z legitimního foreground execution time ještě před Stopem: pokud je kotevní procedura v budoucnu, používá ActivityKit scheduled start v jejím canonical `leaveAt`; pokud už tento okamžik nastal a aplikace je v popředí, aktivita se spustí okamžitě. Stop intent Commander aktivitu nikdy nevytváří z backgroundu. Fronta uvnitř `ContentState` nese nejbližší neskončené události v jednom omezeném okně; do `startAt` hlavní položka ukazuje `Následuje`, od `startAt` `Právě probíhá` a v `endAt` se tatáž karta posune na další položku. Pro jeden projekční průchod musí AlarmKit, Commander Live Activity a Watch používat stejné zachycené `LeadTimeOverrides` a stejnou `projectionRevision`; změna lokálního předstihu během `await` se nesmí promítnout jen do jedné projekce. Existence ani selhání Commander vrstvy nesmí měnit ověření AlarmKitu.

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

Schválený runtime tok je:

1. před odchodem AlarmKit vlastní systémový countdown,
2. foreground/bootstrap synchronizace z canonical rozpisu naplánuje nejvýše jednu Commander Live Activity; kotevní událostí je první ještě relevantní povinná procedura a scheduled start je její canonical `leaveAt`,
3. v `leaveAt` AlarmKit vlastní `ČAS VYRAZIT` a skutečný alarm; Commander aktivita se ve stejném časovém okně aktivuje systémovým scheduled startem, nikoli background requestem ze Stop intentu,
4. Stop pouze zastaví AlarmKit alarm; vlastní Commander ActivityKit instanci nevytváří ani nezakládá konkurenční handoff cestu,
5. dynamický stav nese chronologickou frontu nejvýše šesti neskončených událostí uvnitř jednoho maximálně 7 h 50 min okna a `staleDate` nepřekračuje toto okno,
6. před `startAt` tatáž karta zobrazuje `NÁSLEDUJE`; v `startAt` se přes explicitní `TimelineView` přepne na `PRÁVĚ PROBÍHÁ` a po `endAt` přejde na další známou událost nebo na skončený stav,
7. při překryvu zůstává jako hlavní dříve zahájená stále probíhající událost; následující událost je zobrazena pod ní a po konci první automaticky převezme hlavní pozici,
8. foreground reconciliation aktualizuje jediného keepera, ukončí historické duplicity a pokud žádná aktivita neexistuje, smí naplánovat právě jednu novou scheduled/foreground instanci.

ActivityKit dynamický obsah je uložen v `ContentState`; event-specifická data se proto nemají modelovat jako série nových Commander aktivit. `staleDate` není příkaz k ukončení, ale okamžik zastarání obsahu a při update se posouvá dál. Systémová AlarmKit countdown/alert prezentace je samostatná systémová vrstva a během odchodové fáze může dočasně koexistovat s jedinou Commander Live Activity; aplikace ale nesmí vytvářet druhou vlastní Commander kartu kvůli další proceduře nebo jídlu.

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

Commander používá nejvýše jednu vlastní Live Activity současně. Události se nepřipravují jako více ActivityKit instancí; jsou uložené jako omezená fronta v dynamickém `ContentState` jediné aktivity. Vznik aktivity patří foreground/scheduled coordinatoru, nikoli Stop intentu. Pokud se dvě události překrývají, dříve začatá dosud běžící událost zůstává hlavní a překrývající událost se zobrazuje jako „Současně“; po konci první se tatáž Live Activity automaticky přepne na druhou.

ActivityKit má systémový limit aktivní životnosti. Commander proto plánuje okno maximálně 7 h 50 min od canonical `leaveAt` kotevní procedury a nezařazuje do fronty události, které by skončily za touto hranicí. Není tedy garantována jedna fyzická ActivityKit instance přes celý lázeňský den delší než toto okno. Celodenní garantovanou upozorňovací vrstvou zůstává AlarmKit; Commander pokrývá povinnou procedurální část dne jednou předem připravenou aktivitou.

Tato mez nesnižuje spolehlivost již jednou ověřených budoucích AlarmKit alarmů; odděluje pouze distribuci nové canonical verze od jejího lokálního provedení.

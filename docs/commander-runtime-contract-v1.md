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

AlarmKit vlastní pouze skutečný zvukový alert v canonical `leaveAt`; vlastní předodchodový countdown záměrně nepoužívá. Commander nad stejným canonical rozpisem připravuje několik časově navazujících Live Activity oken a je jedinou průběžnou vizuální vrstvou před odchodem, aby si AlarmKit a Commander nekonkurovaly na Lock Screenu, Dynamic Islandu ani Apple Watch. Každé okno se z foreground/bootstrap reconciliation naplánuje předem; standardně začíná hodinu před první událostí, nebo už v canonical `leaveAt`, pokud je tento čas dřívější. Jídlo může být stejnou kotvou jako procedura. Stop intent Commander aktivitu nikdy nevytváří z backgroundu.

Uvnitř okna nese `ContentState` nejvýše šest chronologických událostí. Před `leaveAt` hlavní položka ukazuje `Vyrazit za` a odpočet do odchodu; od `leaveAt` do `startAt` ukazuje `Čas vyrazit` a odpočet do začátku; od `startAt` do `endAt` ukazuje `Právě probíhá`; po `endAt` se posune na další položku nebo `Skončilo`. Pokud `leaveAt` další události nastane ještě během předchozí události, odchod na další událost dostává prezentační prioritu. Pro jeden projekční průchod musí AlarmKit, Commander Live Activity a Watch používat stejné zachycené `LeadTimeOverrides` a stejnou `projectionRevision`; změna lokálního předstihu během `await` se nesmí promítnout jen do jedné projekce. Existence ani selhání Commander vrstvy nesmí měnit ověření AlarmKitu.

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

1. Canonical rozpis a lokální předstihy určují pro každou událost `leaveAt`, `startAt` a `endAt`.
2. AlarmKit zůstává jedinou zvonící bezpečnostní vrstvou. Každá událost používá tradiční alert-only fixed alarm přímo v canonical `leaveAt`; `countdownDuration` se nepoužívá a widget extension neobsahuje AlarmKit `ActivityConfiguration`.
3. Foreground/bootstrap reconciliation rozdělí zbývající den na nejvýše tři předem naplánovaná Commander okna. Standardní kontext začíná 60 minut před první událostí okna; pokud efektivní `leaveAt` vychází dříve, okno začne už v `leaveAt`.
4. Jídlo i procedura mohou být kotvou okna. Události s volnou mezerou nejvýše dvě hodiny mohou zůstat v jednom okně; delší mezera vytvoří další okno. Jedno okno má hard cap šest událostí a nesmí překročit 7 h 50 min aktivního rozpočtu.
5. Budoucí okna se připravují jako ActivityKit scheduled start s tichým `CommanderSilentAlert.wav`; skutečný zvuk odchodu zůstává pouze AlarmKitu.
6. Před `leaveAt` Commander ukazuje `VYRAZIT ZA` a odpočet do odchodu. Od `leaveAt` do `startAt` ukazuje `ČAS VYRAZIT` a odpočet do začátku. Od `startAt` do `endAt` ukazuje `PRÁVĚ PROBÍHÁ`.
7. Karta současně ukazuje následující událost jako `Potom` / `Současně`, včetně názvu, času a na Lock Screenu také místa. Pokud nastane `leaveAt` další události ještě během probíhající předchozí události, další odchod převezme hlavní pozici.
8. Každá událost používá schválenou kategorickou ikonu a barvu; odchodový urgentní stav může dočasně použít výrazný odchodový akcent.
9. Stop intent pouze zastaví AlarmKit alarm. Nevytváří ani neaktualizuje Commander Live Activity z backgroundu.
10. Foreground reconciliation aktualizuje správná aktivní/pending okna, nahrazuje zastaralé pending snapshoty a odstraňuje historické duplicity nebo již nežádoucí instance.

Technicky může být během dne několik různých ActivityKit instancí, ale jejich plánovaná aktivní časová okna se nepřekrývají. Pending následník může existovat současně se současnou aktivitou, protože musí být připraven dříve, než aplikace případně usne. `staleDate` označuje staré UI, není to přesný příkaz k budoucímu odstranění; proto není bez dalšího foreground/background execution garantováno, že stará skončená karta zmizí přesně v okamžiku startu následníka. AlarmKit tím není dotčen.

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

Commander může během dne použít několik po sobě jdoucích Live Activity oken. Reconciliation plánuje nejvýše tři nejbližší a každé drží nejvýše šest událostí. Aktivní okna jsou plánována bez překryvu; pending následník však může být v systému připraven současně se současnou aktivitou.

ActivityKit má systémová omezení životnosti a počtu současně naplánovaných aktivit. Pokud systém některé vzdálenější pending okno odmítne, Commander nesmí kvůli tomu změnit ani zrušit správné AlarmKit alarmy. Další foreground/bootstrap reconciliation se smí o přípravu chybějícího okna pokusit znovu.

`staleDate` není future dismissal scheduler. Bez dalšího execution time tedy není garantováno přesné systémové odstranění skončené karty ve stejné sekundě, kdy začne nový blok. Tohle musí fyzický E2E sledovat jako samostatnou prezentační vlastnost, ne zaměňovat s platností AlarmKitu.

Tato omezení nesnižují spolehlivost již jednou ověřených budoucích AlarmKit alarmů; oddělují pouze kontextovou Live Activity vrstvu od bezpečnostní vrstvy odchodu.

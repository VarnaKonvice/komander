# Commander: provozní manuál

Platí pro finální kód druhého reliability passu nad checkpointem `b4c2881fef3fec6de3a7d56959027310068df0fe`, větev `lc/alarm-liveactivity-unification-v1`. Tento pass neinstaloval aplikaci na zařízení, nespouštěl skutečné alarmy a neměnil produkční rozpis ani signing.

## A. Zdroj pravdy a načtení rozpisu

Zdroj rozpisu je produkční `data/schedule.json`, jehož raw GitHub URL určuje `AppConfiguration`. iPhone, Watch a widgetové soubory jsou lokální cache. Lokální předstihy jsou samostatné preference, nejsou změnou rozpisu na serveru.

Při spuštění iPhone načte poslední validní uložený rozpis, provede jeho lokální kontrolu a potom zkusí síť. Jeden synchronizační průchod stáhne celý rozpis jednou. Kontroluje jeho strukturu, unikátní stable ID, časy, verzi a předstihy. Novější platnou verzi uloží; stejná verze se stejným obsahem je opakování. Starší verzi nebo jiný obsah pod stejnou verzí nepřijme a nadále používá uložený rozpis. Chyba fetch nebo validace nemaže poslední validní snapshot.

Ze stejného rozpisu a zachycené revize předstihů vzniká sada AlarmKit alarmů, příprava Commander Live Activity a celý vícedenní Watch snapshot. Změna předstihu navyšuje `projectionRevision`; nemění `scheduleVersion` a nepotřebuje síť. Další změna během probíhající synchronizace vyvolá následný průchod. Lokální přepočet má přednost před čekajícím síťovým refreshem.

Úspěch iPhone synchronizace znamená ověřenou přípravu AlarmKit a ověřený úklid případné zálohy. Watch potvrzení je samostatné. Odpojené Watch tedy samy o sobě nejsou selháním iPhone alarmů. Stav „předáno“ není důkaz zobrazení na hodinkách; potvrzení dokládá přijatou identitu rozpisu a revize.

Domácí iPhone widget má vlastní fetch a validovanou diskovou cache. Bez iPhone App Group nevidí lokální předstihy aplikace. Proto ukazuje začátky a konce událostí, nikoli údajně přesný lokální odchod. Reload vyvolaný aplikací nepřenáší preference do widgetu.

## B. Chronologie jedné události

`startAt` a `endAt` jsou začátek a konec v rozpisu. `leaveAt` je začátek minus účinný předstih. Konec je plánovaný čas, nikoli potvrzení účasti nebo dokončení léčby.

| Okamžik | Chování našeho kódu |
| --- | --- |
| Dlouho před událostí | Dnes a Watch vyberou relevantní událost dne. Commander připravuje omezený počet Live Activity oken; vzdálená událost nemusí mít viditelnou kartu. Domácí widget odpočítává do začátku. |
| Před `leaveAt` | Aplikace a Watch odpočítávají do odchodu. Aktivní Commander karta má při aktuálním obsahu `departureCountdown`. AlarmKit je samostatný zvukový alarm, bez vlastního předodchodového countdownu. |
| Přesně `leaveAt` | Výpočet Dnes/Watch přejde na „vyrazit“. Již naplánovaný AlarmKit má fixed čas přesně `leaveAt`. Reconcile v tomto okamžiku už nevytváří nový alarm pro tento uplynulý deadline. |
| Stop před začátkem | Stop aktualizuje existující aktivní/stale Commander kartu na `startCountdown`, odpočet do začátku. Z background Stop nevytváří novou Activity. Opakování stejného stavu neodesílá další alert. |
| Přesně `startAt` | Časový výpočet přejde na probíhající událost. Cold/foreground reconcile volí `eventContext`. Stop zpracovaný od tohoto okamžiku rovněž volí `eventContext`. |
| Během události | Dnes a Watch zobrazují průběh a odpočet do konce. Commander `eventContext` poskytuje časový kontext začátku a konec. |
| Přesně `endAt` | Událost už není aktivní; vybere se další relevantní nebo „Dnes hotovo“. Stop pro skončenou událost se ignoruje. Reconcile uklízí skončená nepotřebná okna. |
| Další událost | Je-li už čas odejít na další, odchod má přednost i před dosud probíhající starší událostí. Z více aktivních událostí má přednost poslední začátek. Jídla se časově účastní stejného výběru. |

Při překryvu může po skončení kratší pozdější události stále zbývat delší starší událost; výběr znovu vychází ze skutečně platných intervalů. Opožděný Stop starší události nepřepíná fokus zpět, pokud fokus již přešel na pozdější událost, jejíž odchod nastal. Změněné časy téhož stable ID zneplatní starý callback.

Odchod na zítřejší událost může nastat ještě dnes: například začátek 00:10, předstih 20 minut → odchod 23:50. Od 23:50 jej Dnes/Watch zahrnou, i přes půlnoc. Před odchodem může dnešní dokončený program ještě hlásit „Dnes hotovo“ a nabídnout další událost. Událost s koncem před začátkem v témže datu není podporovaný zápis přes půlnoc.

## C. Co zobrazují jednotlivé plochy

| Plocha | Před odchodem | Od odchodu do začátku | Během události | Po konci / bez dat |
| --- | --- | --- | --- | --- |
| Aplikace Dnes | Odchod, následující události, celá denní osa | Výzvu vyrazit a začátek | Průběh a konec podle rozpisu | Další událost nebo hotovo; chybějící rozpis není potvrzení dokončení |
| Commander Live Activity, Lock Screen, Dynamic Island | `departureCountdown` v připraveném okně | Po Stop/reconcile `startCountdown` | Po aktuálním Stop/reconcile `eventContext` | Konec bloku, případně další připravený blok; úklid při reconcile |
| Domácí iPhone widgety a jejich accessory varianty | Začátek za… | Stále začátek za…; lokální odchod neznají | Do konce | Další událost / dnes hotovo; bez validních dat výzva načíst rozpis, nikoli falešné hotovo |
| Watch app | Odchod z doručených předstihů | Vyrazit, čas začátku | Průběh, konec | Další / hotovo; po expiraci cache bez programu |
| Watch widget | Stejná projekce z Watch App Group cache | Odchod/začátek | Konec | Timeline přejde na další stav nebo bez dat |
| Systémově zrcadlená Live Activity na Watch | Obsah Commander ActivityKit karty | Obsah aktualizované karty | Kontext karty | Podle systémového zrcadlení a životnosti Activity |

Watch widget a systémová Live Activity jsou dvě různé plochy. Potvrzení WatchConnectivity pro cache neprokazuje doručení ActivityKit aktualizace do Smart Stacku.

Domácí widget připravuje timeline s hranicemi událostí, dnem a minutovými body na šest hodin. Při chybě nebo bez dat žádá další refresh za 15 minut. Watch timeline obsahuje odchod, začátek, konec, hranice dnů a expiraci; po nečitelném/chybějícím snapshotu rovněž žádá nový pokus za 15 minut. Skutečný čas vykreslení a refreshe řídí WidgetKit.

Live Activity má systémově běžící omezený timer, ale změna čísla timeru není nová aktualizace jejího strukturovaného obsahu. Samotný průchod přes začátek či konec **nezaručuje** probuzení aplikace nebo změnu `presentationMode`/fokusu. U spící aplikace tak může zůstat starší fáze s odpočtem na nule až do Stop, reconcile nebo systémového překreslení. Přesný automatický přechod celé karty bez update/push není tímto passem prokázán ani garantován. Kód nepovažuje samotné `stale` za důkaz konce události; renderer „Skončilo“ navíc podmiňuje časem konce celého bloku.

## D. Restart, offline a nedostupná zařízení

- **Kill/relaunch iPhone:** canonical snapshot, běžné předstihy, mapování alarmů a vlastnictví mají úložiště. Před platformním schedule se zapisuje rezervované alarm ID. Opakování po nejasném úspěchu použije stejné ID, nikoli další náhodné. Cancel lze opakovat po již úspěšném platformním zrušení.
- **Zvonící alarm:** běžný foreground reconcile jej nepovažuje za uživatelské Stop. Zachová nezměněný aktuální zvonící alarm; zachová i doloženě vlastní zvonící alarm bez mapování po přerušeném zápisu. U takového sirotka chybí spolehlivá vazba na čas konce, proto má přednost nezastavit zvuk bez uživatele. Cizí platformní ID adapter nevrací jako vlastní a neruší.
- **Poškozené alarmové úložiště:** chyba se propaguje, místo aby aplikace předstírala prázdný úspěšný stav a vytvořila další alarmy. Chybějící nebo nevalidní schedule/widget cache neposkytuje validní program. Poškozený soubor a dočasně nečitelný soubor nejsou úspěšný read-back.
- **Live Activity po restartu aplikace:** coordinator kontroluje existující ActivityKit aktivity, jejich statickou identitu, obsah a revizi. Udržuje jednu kartu na anchor, uklízí duplicity a odmítne starší projekci i podle obsahu přeživší aktivity. Stop a reconcile sdílejí frontu zápisů v procesu. Toto není důkaz atomických transakcí mezi libovolnými systémovými procesy.
- **Offline iPhone:** poslední rozpis a lokální přepočet nevyžadují fetch. Síťový neúspěch sám nevymaže rozpis a sám nepotvrzuje poruchu AlarmKit. Novou serverovou změnu offline zařízení znát nemůže.
- **Watch offline/restart:** přijímají celý vícedenní snapshot s předstihy a revizí, atomicky jej ukládají. Opakovaná zpráva je idempotentní; starší verze/revize ani konflikt stejné verze nepřepíše novější cache. Při změně předstihu stačí novější `projectionRevision` při stejném rozpisu.
- **Odpojené Watch:** iPhone používá application context; okamžitá dosažitelnost není podmínkou naplánovaného alarmu. Přenos a potvrzení mohou počkat na obnovení spojení. Poslední dostupný rozpis neobsahuje nedoručené změny.
- **Zamčené Watch:** chyba čtení nesmaže již platné zobrazení v běžící Watch app. Po cold startu bez přístupu k úložišti nelze data vymyslet; widget má bezpečný fallback a žádost o opakování. Dostupnost souborů před prvním odemčením po rebootu a systémové doručení je nutné ověřit fyzicky.
- **Expirace Watch/widget cache:** konec poslední události plus 24 hodin. Přesně při expiraci už není rozpis aktivní. Půlnoc sama cache nemaže; vícedenní program funguje bez nového fetch.
- **Oprávnění:** odmítnutý AlarmKit nesmí blokovat validní canonical data. Aplikace může zkusit samostatná záložní oznámení; teprve ověřený AlarmKit a úklid zálohy znamená úspěch bez zálohy. Zamítnutá oznámení vyžadují zásah uživatele. Běžná oznámení nejsou zárukou ekvivalentní AlarmKit zvuku.

Testy prokazují obnovu uloženého stavu a rozhodování fake platformy. Zda skutečný systém zachová a včas spustí alarm při kill, rebootu, zamčení nebo Focus, musí ukázat fyzický test.

## E. Předstihy

Nastavení nabízí obecný default, typ/kategorii procedury nebo typ jídla a výjimku konkrétní události. Povolený rozsah je 0–180 minut. Přesná priorita finálního kódu od nejsilnější:

1. Lokální výjimka konkrétního stable ID.
2. Lokální typ procedury nebo jídla.
3. Lokální kategorie procedury.
4. Lokální obecný default.
5. Předstih konkrétní události ze zdrojového rozpisu.
6. Typ procedury/jídla ve zdrojovém nastavení.
7. Zdrojový obecný default.

Lokální default tedy vědomě přebíjí i předstih události uvedený pouze ve zdroji. Nastavení kategorie odstraňuje starší lokální typové výjimky té kategorie. Reset jedné úrovně odkryje nižší úroveň; reset všech odstraní všechny lokální výjimky. Výsledkem je přepočet nad uloženým rozpisem, nový revision a následné předání na Watch. Domácí iPhone widget lokální odchod nezobrazuje.

Visual Review provádí změny a reset pouze v paměti. Preference store v tomto režimu ani nečte, ani nezapisuje persistentní hodnotu, i kdyby dostal stejný klíč. Potvrzení auditních výjimek v preview se také neukládá. Po relaunchi je preview znovu výchozí. Normální Debug se řídí pouze aktuálními preview argumenty; starý persistentní příznak jej nezapne. Widgetový preview vyžaduje compile-time `COMMANDER_VISUAL_REVIEW`. Acceptance fixtures mají vlastní namespace preferencí/snapshotu a normální build jejich vstup nepoužívá; nejsou povolením spouštět testovací alarmy během tohoto passu.

## F. Záměrné hranice a systémová omezení

- Rozpis neobsahuje docházku, potvrzení léčby ani GPS. „Hotovo“ je časový stav rozpisu.
- Přesně v minulém nebo současném `leaveAt` se nově nezakládá catch-up alarm. Existující platformní alarm má tuto hranici pokrýt; pozdní první načtení nedožene zmeškané zvonění.
- Časy jsou lokální Europe/Prague. Neexistující jarní hodina i opakovaná podzimní hodina se odmítají. Formát nemá offset/fold, takže obě podzimní 02:xx nedokáže bezpečně rozlišit. Kontroluje se i odvozený odchod, ještě před uložením canonical snapshotu. Běžné jednoznačné časy před/po změně fungují; jarní odečtení předstihu počítá skutečné minuty.
- Commander připravuje nejvýše 3 Live Activity okna, standardně s kontextem od min(odchod, začátek minus 60 minut), maximální volnou mezerou 2 hodiny, rozpočtem 7 h 50 min a nejvýše 6 událostmi na okno. Payload se navíc omezuje podle velikosti. Celý pobyt tedy není neomezeně předem pokryt kartami; další příprava potřebuje reconcile. Extrémně dlouhá událost může přežít rozpočet vlastního okna.
- ActivityKit povolení, systémové limity, naplánované spuštění okna, Lock Screen, Dynamic Island a Smart Stack závisí na systému. Unit test ani unsigned build je nepotvrzuje.
- WidgetKit řídí skutečné refreshe. Timeline vyjadřuje správný požadovaný stav, nikoli garantované probuzení přesně na sekundu. Nezměněný offline feed nemůže dokládat, že na serveru mezitím nevznikla nová verze.
- Samostatné Watch alarmy jsou volitelné běžné lokální notifikace. Plánují nejbližších nejvýše 60 budoucích odchodů, respektují systémová oprávnění a Focus. Cache obsahuje i zbytek rozpisu; doplnění dalšího okna vyžaduje reconciliation.
- Watch delivery failure nezpůsobuje záměrně další iPhone alarmové retry. Doručení může být potřeba znovu vyvolat při aktivaci nebo další synchronizaci.
- Acceptance launcher má exkluzivní PID lock, bezpečné převzetí prokazatelně mrtvého vlastníka a omezené čekání na zařízení. Neověřitelné vlastnictví zachová a skončí chybou. Dočasný DerivedData vzniká přes `mktemp`, úklid ověřuje cestu i vlastnický marker a běží také na EXIT/INT/TERM. SIGKILL či výpadek počítače nelze odchytit; neprokázané pozůstatky cizího/staršího běhu se automaticky nemažou. Úklid souborů při signálu není potvrzení odstranění již nainstalovaných alarmů na zařízení.
- Provisioning reminder nebyl rozšířen; testy nadále odlišují pending a delivered oznámení. Datum platnosti určuje profil, samotný build není důkaz prodloužení na zařízení.

## G. Co ještě musí parent agent ověřit fyzicky

Fyzický E2E je skutečný běh autorizovaného izolovaného testu na iPhone a párovaných Watch, s read-backem a pozorováním výsledku. Pouhé „build succeeded“, předaná zpráva, READY nebo plánovaný timer není fyzický PASS. Nejbezpečnější výchozí bod je oddělený target `LazenskyCommanderPhysicalAcceptance`; jeho postup je v `docs/physical-alarm-acceptance.md`. Postup nyní rozlišuje `startCountdown` po Stop před začátkem a `eventContext` po aktualizaci od začátku.

Parent agent má po samostatném povolení fyzického testu ověřit:

1. Identitu nainstalovaného buildu a izolaci testovacích dat, ownership, bundle a prefs; před startem skutečný read-back všech alarmů na správné `leaveAt` a připravených Activity oken.
2. Zvuk v odchodu pro jídlo i proceduru, Stop před začátkem, Stop přesně v začátku, opakovaný Stop a opožděný callback po změně času stejného stable ID; žádnou duplicitní kartu/alarm.
3. Lock Screen, Dynamic Island a Watch Smart Stack před odchodem, mezi odchodem a startem, během události, na konci, při překryvu a přes delší mezeru; zaznamenat, které texty/fokus se skutečně mění bez aktivní aplikace.
4. Kill před alarmem, mezi alarmem a startem, během a po události; samostatně reboot telefonu/hodinek a první odemčení. Ověřit zvuk i read-back po návratu, nejen UI.
5. Offline iPhone, dlouho odpojené Watch, reconnect, změnu pouze lead-time revision, zamčené Watch a nové načtení widgetu. ACK porovnat s přesnou identitou cache; systémovou ActivityKit kartu ověřit zvlášť.
6. Odepření/odvolání AlarmKit i notification oprávnění a návrat oprávnění; chování zálohy a její odstranění bez dvojího upozornění.
7. Skutečné refresh hranice všech podporovaných widgetových velikostí, půlnoc a expiraci; domácí iPhone widget nesmí tvrdit lokální odchod.
8. Úklid testovacích alarmů, aktivit a souborů a ověřený návrat k normálnímu buildu. Fyzický PASS z tohoto passu nevznikl.

## Lokální ověření tohoto passu

Deterministické Swift testy pokrývají hranice, stale fázi, odchod přes půlnoc, DST, opožděný Stop, ephemeral preference, pořadí fetch/cache, restart Watch cache a zachování zvonícího sirotka. Existující suite navíc pokrývá souběžnou reconciliation, nejasný platformní úspěch, ownership, oprávnění, fallback, Watch ACK, provisioning a plánování Activity. Přímé ActivityKit/SwiftUI wiring kontroly zůstávají source-shape, protože tento Swift package neběží v iPhone extension procesu. Shell testy spouštějí izolované lock/cleanup funkce a fake čekání; nespouštějí instalaci.

Příkazy z kořene worktree:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/commander-pass2-module-cache swift test --disable-sandbox --package-path native/LazenskyCommander
CLANG_MODULE_CACHE_PATH=/private/tmp/commander-pass2-module-cache swift run --disable-sandbox --package-path native/LazenskyCommander LazenskyCommanderCoreCheck
node --input-type=module -e 'import {runPublicScheduleSuite} from "./tests/public-schedule-suite.mjs"; const r = await runPublicScheduleSuite({repoRoot:process.cwd()}); console.log(JSON.stringify(r,null,2)); if(r.failed)process.exit(1)'
node tests/brand-assets-suite.mjs
node tests/calendar-sync-suite.mjs
node tests/google-calendar-auth-suite.mjs
node tests/refresh-launcher-suite.mjs
node tests/acceptance-reliability-suite.mjs
xcodebuild -project native/LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj -scheme LazenskyCommanderApp -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/commander-pass2-debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 'OTHER_SWIFT_FLAGS=$(inherited)' build
git diff --check
```

Samotné `node tests/public-schedule-suite.mjs` testy nespouští: soubor exportuje funkci, kterou je potřeba zavolat, viz výše. Build je unsigned generický iOS Debug, bez `COMMANDER_VISUAL_REVIEW` a bez instalace; neprokazuje platnost Personal Team profilu.

Výsledek finálních gates dne 29. 9. 2026:

| Gate | Výsledek |
| --- | --- |
| Swift Testing | 277 testů PASS, 0 selhání; 13 nových definic (12 behaviorálních, 1 kontrola platformního propojení), včetně parametrizovaných scénářů |
| CoreCheck | PASS |
| Public schedule | 38/38 PASS |
| Brand assets | 10/10 PASS |
| Calendar sync | 26/26 PASS |
| Google calendar auth | 5/5 PASS |
| Refresh launcher / provisioning | 18/18 PASS |
| Acceptance reliability | 14/14 PASS; 5 nových behaviorálních scénářů |
| Celý `LazenskyCommanderApp`, normální Debug, generic iOS, unsigned | BUILD SUCCEEDED, včetně závislých Watch/widget targetů |
| `git diff --check` | PASS |

Build logy a výstupy sad jsou v `/private/tmp/commander-pass2-*.log`; dočasný DerivedData a pomocná module cache byly po ověření odstraněny. HEAD zůstal na checkpointu, změny nejsou commitnuté ani pushnuté.

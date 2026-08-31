# Obnovení aplikace s Apple Personal Team

Soubor `Obnovit Lázeňský Commander.command` bezpečně načte aktuální verzi produkční větve `main` z GitHubu, obnoví vývojářský podpis a nainstaluje povinnou iPhone aplikaci. Používá Git, plný Xcode, Automatic Signing projektu a oficiální Apple nástroje `devicectl`, `security` a `plutil`.

Nativní Apple Watch aplikace je dočasně volitelná. Launcher ji nemaže ani neobchází; pokud jsou hodinky pro Xcode skutečně způsobilé, po dokončené obnově iPhonu se ji pokusí samostatně sestavit, podepsat, nainstalovat a ověřit. Selhání tohoto volitelného kroku nezmění úspěšnou obnovu iPhonu na chybu.

## Běžné obnovení

1. Připoj iPhone k MacBooku Air kabelem.
2. Odemkni iPhone.
3. Pokud není dostupná Wi-Fi, zapni hotspot nebo USB internet z iPhonu.
4. Dvojklikni na `Obnovit Lázeňský Commander.command`.
5. Počkej na dialog `HOTOVO – Lázeňský Commander na iPhonu byl obnoven.`

Apple Watch nemusí být připojené. Pokud je chceš zkusit obnovit současně, nasaď je, odemkni a nech poblíž iPhonu a Macu.

Po ověření podpisu launcher dekóduje `embedded.mobileprovision` právě sestavené iPhone aplikace. Zkontroluje `CreationDate` a `ExpirationDate`; doporučený termín je jeden kalendářní den před expirací v Europe/Prague. Známý prošlý profil nesmí být nainstalován. Po ověřené instalaci zobrazí skutečnou platnost a `DALŠÍ OBNOVA NEJPOZDĚJI`. Pouze pokud metadata nelze bezpečně přečíst, použije šest kalendářních dní od úspěšné instalace a výslovně označí termín jako odhad.

Automatic Signing může znovu použít dosud platný profil. V takovém případě zůstává skutečný termín stejný; nový build ani opětovná instalace samy o sobě platnost neprodlužují. Launcher nemaže profily ani nepředstírá novou expiraci. Nový profil automaticky přinese nový termín.

Launcher nikdy neinstaluje náhodně checkoutnutou větev. Nejprve ověří, že `origin` ukazuje na `VarnaKonvice/komander` a pracovní strom je zcela čistý. Potom fetchne pouze `main`, odmítne lokální vlastní nebo odlišné commity, přepne na tuto větev a znovu ověří přesnou shodu s GitHub commitem. Pokud se na GitHubu změnil i samotný obnovovací launcher, pokračuje právě staženou verzí. Nepoužívá `git pull`, merge ani reset.

Interní vývojářský override `LC_REFRESH_TARGET_BRANCH` umožňuje explicitně vybrat jinou větev a zachová se i při opětovném spuštění staženého launcheru. Běžný dvojklik bez override vždy vybírá `main`. Dokud feature větev není v `main`, nepoužívej tento launcher k jejímu fyzickému ověřování; použij přímý developerský build.

## Připomenutí na iPhonu

Po ověřené instalaci launcher otevře iPhone aplikaci. Samostatná servisní funkce při spuštění a návratu do popředí přečte profil z aktuálně nainstalovaného bundle, bez sítě a bez změny rozpisu. V `Nastavení > Obnova aplikace` jsou `Platnost aplikace do`, `Obnovit nejpozději` a stav připomenutí. Obnovu není potřeba ručně potvrzovat. Pokud spuštění nelze potvrdit, launcher to výslovně oznámí; instalace samotná ještě nepřesune lokální připomenutí.

Při prvním použití stačí jednou zvolit `Povolit připomenutí obnovy`, pokud aplikace dosud nemá oprávnění k lokálním notifikacím. Při odmítnutí tlačítko otevře systémová Nastavení. Další obnovy už potvrzení nevyžadují.

Právě jeden nerepetitivní lokální reminder používá identifier `lazensky.commander.provisioning.renewal.v1`. Nový profil odstraní staré připomenutí a naplánuje nové na doporučený termín včetně času; shodný profil se správným pending requestem nic nepřeplánuje. Stav `Naplánováno` se zobrazí až po read-backu požadavku. Po uplynutí termínu aplikace vyzve k obnově a nevytváří opakované okamžité notifikace.

Jde o standardní `.active` notifikaci se systémovým zvukem, která respektuje nastavení oznámení a Focus. Nepoužívá AlarmKit, fallback namespace ani rozpis a v E2E kanálu se neaktivuje. Commander Test zůstává nedotčený. Text: `Obnov Lázeňský Commander` / `Připoj iPhone k MacBooku Air a spusť jedno-klikové obnovení.`

V unsigned/simulator buildu bez profilu nebo při neznámém formátu aplikace zobrazí nedostupnou platnost a nevymýšlí termín. Metadata jsou čtena z omezeného DER/CMS kontejneru a plist parserem, nikoli vyhledáváním libovolného XML. Parser nenahrazuje ověření podpisu iOS. Formát provisioning profilu není stabilní veřejný kontrakt; neznámá data proto musí bezpečně vrátit nedostupný údaj. Viz [Apple TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles).

Rozpis se aktualizuje odděleně z canonical `data/schedule.json` na GitHubu; obnova aplikace tento datový tok ani jeho source-of-truth pravidla nemění.

Projekt nadále obsahuje Watch targety, sdílené schéma `LazenskyCommanderWatchApp` a celou Watch funkcionalitu. Povinný tok nejprve dokončí a ověří iPhone instalaci. Teprve potom volitelný tok ověří Watch destination, samostatně sestaví a podepíše Watch target, nainstaluje ho přes `devicectl` a ověří bundle ID `com.varnakonvice.lazenskycommander.watchkitapp`.

CoreDevice může u spárovaných Apple Watch vrátit zastaralý stav Režimu vývojáře. Launcher proto tento údaj používá jen pro diagnostiku a o způsobilosti rozhodne Xcode nad konkrétním UDID. Odmítnutí Watch destination, buildu nebo instalace vede ke stavu `WATCH: přeskočeno`, ne k červené chybě celé obnovy.

## Když se zobrazí CHYBA

- Zkontroluj kabel a nech iPhone po celou dobu připojený.
- Odemkni iPhone a případně potvrď `Důvěřovat tomuto počítači`.
- Ověř, že je na iPhonu zapnutý Režim vývojáře.
- Zkontroluj internet přes Wi-Fi, hotspot nebo USB tethering.
- Pokud launcher hlásí neuložené změny nebo odlišné lokální commity, nic nemaž. Repozitář musí nejdřív zkontrolovat vývojář.
- Pokud selže Apple provisioning, otevři jednou Xcode a zkontroluj, že je v Accounts přihlášený správný Apple účet Personal Team.
- Technický log je uložen v `~/Library/Logs/LazenskyCommanderRefresh/`.

Stav `WATCH: přeskočeno` není chyba obnovy iPhonu. Podrobnosti jsou v technickém logu. Pro pozdější pokus lze hodinky nasadit, odemknout, ověřit na nich Režim vývojáře a nechat Xcode dokončit přípravu zařízení.

Launcher aplikaci před instalací neodinstalovává. Standardní upgrade instalace proto zachová lokální data, pokud to iOS pro danou podepsanou aplikaci umožní.

## Bezpečná kontrola

Servisní režim `--check` provede stejnou bezpečnou aktualizaci a kontrolu cílové Git větve a potom povinný preflight Macu, Xcode projektu, internetu a jednoho odemčeného fyzického iPhonu. Volitelně také vypíše, zda jsou Watch právě způsobilé. Nic nesestaví, nepodepíše ani nenainstaluje.

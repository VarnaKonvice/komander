# Obnovení aplikace s Apple Personal Team

Soubor `Obnovit Lázeňský Commander.command` bezpečně načte aktuální ověřenou verzi větve `lc/stability-pass-v1` z GitHubu, obnoví vývojářský podpis a nainstaluje povinnou iPhone aplikaci. Používá pouze Git, plný Xcode, Automatic Signing projektu a oficiální Apple nástroj `devicectl`.

Nativní Apple Watch aplikace je dočasně volitelná. Launcher ji nemaže ani neobchází; pokud jsou hodinky pro Xcode skutečně způsobilé, po dokončené obnově iPhonu se ji pokusí samostatně sestavit, podepsat, nainstalovat a ověřit. Selhání tohoto volitelného kroku nezmění úspěšnou obnovu iPhonu na chybu.

## Běžné obnovení

1. Připoj iPhone k MacBooku Air kabelem.
2. Odemkni iPhone.
3. Pokud není dostupná Wi-Fi, zapni hotspot nebo USB internet z iPhonu.
4. Dvojklikni na `Obnovit Lázeňský Commander.command`.
5. Počkej na dialog `HOTOVO – Lázeňský Commander na iPhonu byl obnoven.`

Apple Watch nemusí být připojené. Pokud je chceš zkusit obnovit současně, nasaď je, odemkni a nech poblíž iPhonu a Macu.

Bezplatné vývojářské podepsání přes Apple Personal Team má krátkou platnost, obvykle sedm dní. Po úspěšné instalaci launcher zobrazí `DALŠÍ OBNOVA NEJPOZDĚJI` jako šest kalendářních dní od aktuálního data. Datum nečte z provisioning profilu.

Launcher nikdy neinstaluje náhodně checkoutnutou větev. Nejprve ověří, že `origin` ukazuje na `VarnaKonvice/komander` a pracovní strom je zcela čistý. Potom fetchne pouze `lc/stability-pass-v1`, odmítne lokální vlastní nebo odlišné commity, přepne na tuto větev a znovu ověří přesnou shodu s GitHub commitem. Pokud se na GitHubu změnil i samotný obnovovací launcher, pokračuje právě staženou verzí. Nepoužívá `git pull`, merge ani reset.

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

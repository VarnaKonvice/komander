# Obnovení aplikace s Apple Personal Team

Soubor `Obnovit Lázeňský Commander.command` bezpečně načte aktuální ověřenou verzi větve `lc/stability-pass-v1` z GitHubu, obnoví vývojářský podpis a nainstaluje iPhone aplikaci včetně zabalené Watch aplikace. Používá pouze Git, plný Xcode, Automatic Signing projektu a oficiální Apple nástroj `devicectl`.

## Běžné obnovení

1. Připoj iPhone k MacBooku Air kabelem.
2. Odemkni iPhone.
3. Nasaď a odemkni spárované Apple Watch a nech je poblíž iPhonu a Macu.
4. Pokud není dostupná Wi-Fi, zapni hotspot nebo USB internet z iPhonu.
5. Dvojklikni na `Obnovit Lázeňský Commander.command`.
6. Počkej na dialog `HOTOVO – Lázeňský Commander byl obnoven na iPhonu i Apple Watch.`

Bezplatné vývojářské podepsání přes Apple Personal Team má krátkou platnost, obvykle sedm dní. Obnovení přibližně každých šest dní ponechá rezervu před vypršením instalace.

Launcher nikdy neinstaluje náhodně checkoutnutou větev. Nejprve ověří, že `origin` ukazuje na `VarnaKonvice/komander` a pracovní strom je zcela čistý. Potom fetchne pouze `lc/stability-pass-v1`, odmítne lokální vlastní nebo odlišné commity, přepne na tuto větev a znovu ověří přesnou shodu s GitHub commitem. Pokud se na GitHubu změnil i samotný obnovovací launcher, pokračuje právě staženou verzí. Nepoužívá `git pull`, merge ani reset.

Rozpis se aktualizuje odděleně z canonical `data/schedule.json` na GitHubu; obnova aplikace tento datový tok ani jeho source-of-truth pravidla nemění.

Projekt obsahuje sdílená schémata `LazenskyCommanderApp` a `LazenskyCommanderWatchApp`. Launcher nejprve sestaví iPhone aplikaci se zabalenou Watch aplikací, potom samostatně sestaví a podepíše Watch target pro konkrétní fyzické hodinky. Po instalaci iPhone aplikace nainstaluje Watch aplikaci přímo přes `devicectl` a ověří na hodinkách bundle ID `com.varnakonvice.lazenskycommander.watchkitapp`.

## Když se zobrazí CHYBA

- Zkontroluj kabel a nech iPhone po celou dobu připojený.
- Odemkni iPhone a případně potvrď `Důvěřovat tomuto počítači`.
- Ověř, že je na iPhonu zapnutý Režim vývojáře.
- Nasaď a odemkni Apple Watch a ověř na nich Režim vývojáře. Po jeho zapnutí dokonči požadovaný restart.
- Pokud Xcode hodinky vidí jako nezpůsobilé nebo bez známé architektury, nech iPhone i Watch odemčené poblíž Macu a otevři jednou Xcode, aby dokončil přípravu zařízení.
- Zkontroluj internet přes Wi-Fi, hotspot nebo USB tethering.
- Pokud launcher hlásí neuložené změny nebo odlišné lokální commity, nic nemaž. Repozitář musí nejdřív zkontrolovat vývojář.
- Pokud selže Apple provisioning, otevři jednou Xcode a zkontroluj, že je v Accounts přihlášený správný Apple účet Personal Team.
- Technický log je uložen v `~/Library/Logs/LazenskyCommanderRefresh/`.

Launcher aplikaci před instalací neodinstalovává. Standardní upgrade instalace proto zachová lokální data, pokud to iOS pro danou podepsanou aplikaci umožní.

## Bezpečná kontrola

Servisní režim `--check` provede stejnou bezpečnou aktualizaci a kontrolu cílové Git větve a potom preflight Macu, Xcode projektu, internetu, jednoho odemčeného fyzického iPhonu a jediných dostupných fyzických Apple Watch. Nic nesestaví, nepodepíše ani nenainstaluje.

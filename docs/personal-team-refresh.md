# Obnovení aplikace s Apple Personal Team

Soubor `Obnovit Lázeňský Commander.command` obnoví vývojářský podpis a nainstaluje aktuální lokální verzi aplikace na vlastní iPhone. Používá pouze plný Xcode, Automatic Signing projektu a oficiální Apple nástroj `devicectl`.

## Běžné obnovení

1. Připoj iPhone k MacBooku Air kabelem.
2. Odemkni iPhone.
3. Pokud není dostupná Wi-Fi, zapni hotspot nebo USB internet z iPhonu.
4. Dvojklikni na `Obnovit Lázeňský Commander.command`.
5. Počkej na dialog `HOTOVO – Lázeňský Commander byl obnoven.`

Bezplatné vývojářské podepsání přes Apple Personal Team má krátkou platnost, obvykle sedm dní. Obnovení přibližně každých šest dní ponechá rezervu před vypršením instalace.

Launcher nestahuje zdrojový kód, nemění Git větev a neinstaluje automaticky novější verzi aplikace. Vždy zobrazí větev a commit, které jsou právě v lokálním repozitáři. Rozpis se aktualizuje odděleně z canonical `data/schedule.json` na GitHubu; obnovení podpisu tento datový tok nemění.

## Když se zobrazí CHYBA

- Zkontroluj kabel a nech iPhone po celou dobu připojený.
- Odemkni iPhone a případně potvrď `Důvěřovat tomuto počítači`.
- Ověř, že je na iPhonu zapnutý Režim vývojáře.
- Zkontroluj internet přes Wi-Fi, hotspot nebo USB tethering.
- Pokud selže Apple provisioning, otevři jednou Xcode a zkontroluj, že je v Accounts přihlášený správný Apple účet Personal Team.
- Technický log je uložen v `~/Library/Logs/LazenskyCommanderRefresh/`.

Launcher aplikaci před instalací neodinstalovává. Standardní upgrade instalace proto zachová lokální data, pokud to iOS pro danou podepsanou aplikaci umožní.

## Bezpečná kontrola

Servisní režim `--check` provede preflight Macu, Xcode projektu, internetu a jednoho odemčeného fyzického iPhonu. Nic nesestaví, nepodepíše ani nenainstaluje.

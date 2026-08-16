# Automatický rozpis

`schedule.json` je veřejný zdroj pravdy pro Commander. Po každé publikované změně zvyšte `scheduleVersion` a nastavte `updatedAt` na platný ISO čas.

Commander načte novější platný rozpis při startu, návratu do aplikace a po obnovení připojení. Poslední úspěšně ověřený rozpis zůstává v zařízení pro offline použití.

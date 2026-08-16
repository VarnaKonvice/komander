# Privátní rozpis

`schedule.enc.json` je jediný soubor určený k publikaci pro automatický sync. Obsahuje AES-GCM šifrovaný feed, jehož jednorázový datový klíč je zašifrovaný veřejným RSA klíčem Petra.

`schedule-public-key.json` je veřejný klíč používaný Radovanem pro vytvoření feedu. Do této složky nikdy neukládejte potvrzený rozpis v plaintextu ani soukromý klíč. Feed se vytváří lokálně nástrojem `tools/private-schedule-feed.html`.

## Kanonický formát feedu

Obálka má vždy `format`, `version`, `scheduleVersion` a `updatedAt`. Objekt `crypto` obsahuje pouze `algorithm`, `wrappedKey`, `payloadIv` a `ciphertext`; `wrappedKey` je AES-256 klíč zabalený RSA-OAEP/SHA-256, `payloadIv` je jednorázový 12byte AES-GCM IV a ciphertext obsahuje i autentizační tag. RSA-OAEP nemá IV a žádné další kryptografické pole se nepoužívá.

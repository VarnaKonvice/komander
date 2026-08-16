# Potvrzený model rozpisu

Jediným zdrojem pravdy pro Commander, šifrovaný feed a podklady pro Kalendář je tento JSON model. `scheduleVersion` je celé kladné číslo a při každé publikované změně se zvýší. Radovan jej zašifruje výhradně pomocí `data/schedule-public-key.json`; nepotřebuje žádný soukromý klíč ani párování zařízení.

```json
{
  "schemaVersion": 1,
  "scheduleVersion": 7,
  "updatedAt": "2026-08-15T08:00:00.000Z",
  "stay": {
    "spa": "Testovací lázně",
    "dateFrom": "2026-08-15",
    "dateTo": "2026-08-21",
    "room": "208",
    "doctor": "MUDr. Test",
    "mealShift": "II. směna"
  },
  "events": [
    {
      "stableId": "stay-2026-08-15-magnet-0820",
      "date": "2026-08-15",
      "start": "08:20",
      "end": "08:40",
      "title": "Magnetoterapie",
      "location": "LDB - Elektroléčba",
      "kind": "procedure",
      "procedureType": "Magnetoterapie",
      "mealType": "",
      "leadTimeMinutes": null,
      "source": "confirmed"
    }
  ],
  "settings": {
    "defaultLeadTimeMinutes": 20,
    "procedureTypeOverrides": { "Jodobromová koupel": 30 },
    "mealOverrides": { "Snídaně": 15, "Oběd": 15, "Večeře": 15 }
  }
}
```

Každý kalendářový podklad se odvozuje z `events[]` a obsahuje: `stableId`, `title`, ISO `start`/`end`, `location`, `kind`, `procedureType`, `mealType` a výsledné `leadTimeMinutes`.

## Šifrovaná obálka

Jediný publikovatelný soubor `data/schedule.enc.json` má tento kontrakt:

```json
{
  "format": "lazensky-commander-encrypted-feed",
  "version": 2,
  "scheduleVersion": 7,
  "updatedAt": "2026-08-15T08:00:00.000Z",
  "crypto": {
    "algorithm": "RSA-OAEP-256/AES-256-GCM",
    "wrappedKey": "base64url(RSA-OAEP/SHA-256(AES-256 key))",
    "payloadIv": "base64url(12-byte AES-GCM IV)",
    "ciphertext": "base64url(AES-GCM ciphertext including authentication tag)"
  }
}
```

Metadata obálky jsou AES-GCM additional authenticated data. Změna `scheduleVersion` nebo `updatedAt` proto vede k odmítnutí dešifrování. `keyIv` neexistuje: RSA-OAEP žádné IV nepoužívá.

## Priorita předstihu

Jedna funkce `getEffectiveLeadTime()` používá tuto sestupnou prioritu: lokální override konkrétní události, lokální override typu procedury/jídla, lokální výchozí hodnota, explicitní `leadTimeMinutes` události, automatický override typu ve zdroji, automatický výchozí předstih pobytu. Hodnota `0` je platná; `null`, `undefined` a prázdná hodnota znamenají „nenastaveno“. Klíče typů se porovnávají po trimu, NFC normalizaci a case-foldingu `cs-CZ`; stabilní ID událostí zůstávají přesná. Výpočet je `triggerAt = start - leadTimeMinutes`.

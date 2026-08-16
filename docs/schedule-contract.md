# Potvrzený model rozpisu

Jediným zdrojem pravdy pro Commander a podklady pro Kalendář je veřejný soubor `data/schedule.json`. `scheduleVersion` je celé kladné číslo a při každé publikované změně se zvýší. `updatedAt` musí obsahovat platný ISO čas.

```json
{
  "schemaVersion": 1,
  "scheduleVersion": 7,
  "updatedAt": "2026-08-15T08:00:00.000Z",
  "stay": {
    "spa": "Testovací lázně",
    "dateFrom": "2026-08-15",
    "dateTo": "2026-08-21"
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
      "procedureType": "Magnetoterapie"
    }
  ],
  "settings": {
    "defaultLeadTimeMinutes": 20,
    "procedureTypeOverrides": { "Jodobromová koupel": 30 },
    "mealOverrides": { "Snídaně": 15, "Oběd": 15, "Večeře": 15 }
  }
}
```

Commander kontroluje soubor při startu, návratu do aplikace a obnovení internetu. Novější platný rozpis automaticky uloží; offline používá poslední úspěšně uloženou verzi.

## Priorita předstihu

Jedna funkce `getEffectiveLeadTime()` používá tuto sestupnou prioritu: lokální override konkrétní události, lokální override typu procedury/jídla, lokální výchozí hodnota, explicitní `leadTimeMinutes` události, automatický override typu ve zdroji a automatický výchozí předstih pobytu. Hodnota `0` je platná; `null`, `undefined` a prázdná hodnota znamenají „nenastaveno“.

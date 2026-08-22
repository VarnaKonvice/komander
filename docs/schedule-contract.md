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

PWA kontroluje soubor při startu, návratu do aplikace a obnovení internetu. Novější platný rozpis automaticky uloží; offline používá poslední úspěšně uloženou verzi. iPhone companion provede při ruční synchronizaci jediný fetch, validuje celý `Schedule` a tentýž objekt předá AlarmKitu, Live Card, lokálnímu snapshot store a Watch transportu.

## Lokální kompatibilita

`lazensky_commander_public_schedule_v1` je pouze validovaná lokální cache staženého `data/schedule.json` pro offline provoz. Není to další zdroj rozpisu a nesmí se plnit z jiných lokálních dat.

`lazensky_commander_schedule_v10` zůstává dočasně jednosměrnou kompatibilní projekcí této cache pro dříve nainstalované verze PWA. Aktuální inline UI, nový schedule feed ani `day-overview-v1.js` jej nečtou jako vstup. Po úspěšném načtení kanonického rozpisu se stále přepisuje po dobu kompatibilitního období.

Aktuální aplikace nevytváří vlastní lokální rozpis: historický import v inline UI je deaktivovaný a rozpis se načítá pouze z kanonického feedu.

## Alarm contract

The versioned platform-neutral payload and reconciliation contract used by the native iOS AlarmKit app is documented in [native-alarm-contract.md](native-alarm-contract.md). It is derived from this canonical schedule and does not add another source of truth.

`alarmContract(schedule, overrides)` je společný neměnný výstup pro webovou a současnou nativní alarmovou vrstvu. Vrací jednu položku pro každou událost se strukturou `stableId`, `scheduleVersion`, `kind`, `title`, `location`, `startAt`, `endAt`, `effectiveLeadTimeMinutes` a `leaveAt`. `leaveAt` vždy vychází z `getEffectiveLeadTime()`; nesmí existovat druhý výpočet předstihu. `data/schedule.json` obsahuje kanonický rozpis a zdrojová nastavení, zatímco preference zařízení se předávají jako explicitní JSON `overrides`; do rozpisu nepatří.

Webový i Swift live-state používají alarmový kontrakt stejné události místo vlastního výpočtu `leaveAt`. AlarmKit, Live Activity metadata, Watch timeline a lokální Watch notifikace proto spotřebovávají stejný výsledný čas.

## LIVE STATE CONTRACT

`computeLiveState(schedule, now, overrides)` je společná čistá specifikace pro web a nativní Swift/AlarmKit vrstvu. Časy jsou místní časy rozpisu a předstih vždy vychází z `getEffectiveLeadTime()`.

- `UPCOMING`: existuje další dnešní událost a `now < leaveAt`.
- `LEAVE_NOW`: `leaveAt <= now < startAt`; je čas vyrazit.
- `IN_PROGRESS`: `startAt <= now < endAt`; událost právě probíhá.
- `DAY_DONE`: všechny dnešní události skončily; `nextEvent` případně ukazuje první budoucí událost.
- `NO_SCHEDULE`: rozpis nebo aktuální čas nejsou použitelné.

Na hranici `endAt` se hledá další událost. Po půlnoci se stav vyhodnocuje podle nového místního dne.

## iPhone a Watch distribuce

Implementovaný nativní tok je:

`data/schedule.json -> NativeAlarmContract -> iPhone Live Card + AlarmKit -> WatchScheduleSnapshot -> WatchConnectivity updateApplicationContext -> validovaná App Group cache -> Watch app + WidgetKit + lokální Watch notifikace`

`WatchScheduleSnapshot` obsahuje celý canonical `Schedule`, nikoli pouze aktuální den. Watch cache používá jedinou version policy: identický snapshot je idempotentní, nižší nebo konfliktní verze se odmítne a uloží se jen vyšší validní verze. Uložení je atomické. Widget timeline obsahuje přechody dne, countdownu, `leaveAt`, `startAt`, `endAt` a expirace, takže další den funguje ze stejné cache bez nového spojení s iPhonem.

Celý pobyt zůstává aktivní do konce poslední události plus 24 hodin. Rolling limit 60 se týká pouze pending lokálních Watch notifikací; nikdy nezkracuje Watch snapshot ani cache. Watch nemají direct internet fetch, GPS ani cellular závislost.

## Vizuální kontrakt

`assets/icons/lazensky-v1/icon-map.json` a `colors.json` jsou společný vizuální kontrakt PWA, iPhonu, Live Activity, Watch app a widgetu. PWA používá 256px varianty, iPhone 512px a malé nativní plochy 128px varianty stejné schválené kresby. Neznámá procedura nedostává `individual_rehab` ani jinou falešnou kategorii: zachová zdrojový text, nemá ikonový klíč a používá neutrální Commander purple.

## Google Calendar sync

Google Calendar je pouze odvozená projekce celého `data/schedule.json`, včetně minulých událostí. Sdílený `calendar-contract.js` určuje stejnou sémantiku pro PWA `calendarContract()` i serverový sync: `procedure` → `Procedury`, `meal` → `Jídlo`, místní čas `Europe/Prague`, identita `stableId` a `syncKey = "lc:<stableId>"`. Skutečná Google calendar ID se předávají výhradně prostředím a nepatří do rozpisu ani zdrojového kódu.

Událost je vlastněná Commanderem pouze tehdy, když její Google private extended properties současně obsahují `managedBy = "lazensky-commander"`, neprázdné canonical `stableId` a odpovídající `syncKey`. Marker `[LC:<stableId>]` v popisu je čitelná diagnostická stopa, nikoli oprávnění k úpravě. Synchronizátor smí aktualizovat a mazat jen takto vlastněné události; osobních a cizích položek se nedotýká.

Nové `stableId` se vytvoří, změněný obsah se aktualizuje, nezměněný obsah nevyvolá žádný write a vlastněná událost odstraněná z rozpisu se smaže. Změna `meal ↔ procedure` přesune stejné `stableId` mezi kalendáři. Google reminders jsou vypnuté a projekce nepřidává attendees ani Google Meet. Provozní nastavení a GitHub Actions jsou popsané v [google-calendar-sync.md](google-calendar-sync.md).

## Priorita předstihu

Jedna funkce `getEffectiveLeadTime()` používá tuto sestupnou prioritu: lokální override konkrétní události, lokální override typu procedury/jídla, lokální výchozí hodnota, explicitní `leadTimeMinutes` události, automatický override typu ve zdroji a automatický výchozí předstih pobytu. Hodnota `0` je platná; `null`, `undefined` a prázdná hodnota znamenají „nenastaveno“.

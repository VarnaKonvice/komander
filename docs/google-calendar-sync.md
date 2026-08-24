# Google Calendar sync

## Architektura

Jediným zdrojem pravdy je `data/schedule.json`. Google Calendar není vstup do aplikace a změny provedené ručně v Google Calendar se nevracejí do rozpisu.

```text
data/schedule.json
  -> calendar-contract.js / LazenskySchedule.calendarContract()
  -> calendar-sync/schedule-projection.mjs
  -> calendar-sync/calendar-reconciliation.mjs
  -> calendar-sync/google-calendar-adapter.mjs
  -> Google Calendar: Procedury + Jídlo
```

Synchronizuje se celý canonical rozpis, tedy minulé, dnešní i budoucí události. AlarmKit future-only filtr se na kalendář nepoužívá.

## Google obsah a vlastnictví

- `procedure` patří do logického kalendáře `Procedury`; `meal` do `Jídlo`.
- Časy používají `Europe/Prague`, canonical datum a canonical `start`/`end`.
- Název a místo jsou canonical `title` a `location`.
- Popis obsahuje `Lázeňský Commander` a `[LC:<stableId>]`.
- Google reminder je odvozený z canonical alarm contractu: `useDefault = false` a právě jeden popup override s `minutes = startAt - leaveAt = effectiveLeadTimeMinutes`. Hodnota `0` znamená popup v čase začátku. Email ani druhý popup se nepřidávají.
- Projekce nepřidává attendees, Google Meet ani conference data.

Calendar popup je záložní odvozené upozornění. Pokud uživatel používá nativní aplikaci, primární vrstvou zůstává AlarmKit naplánovaný přímo na stejné canonical `leaveAt`; Google Calendar není další alarmový ani schedule zdroj pravdy.

Vlastnictví se ověřuje výhradně společnou kombinací private extended properties:

```text
managedBy = lazensky-commander
stableId  = <canonical stableId>
syncKey   = lc:<canonical stableId>
```

Samotný textový marker v popisu nestačí. Cizí položky, neúplně označené položky a položky jiného systému se nikdy neupravují ani nemažou.

Reconciliation pravidla jsou:

- chybějící `stableId`: create;
- stejné `stableId` se změněným kalendářově relevantním obsahem, včetně popup reminderu: update;
- stejný obsah: unchanged bez API write;
- vlastněné `stableId`, které zmizelo z rozpisu: delete;
- změna `meal ↔ procedure`: create/udržení v novém kalendáři a delete ve starém.

## Barevný kontrakt

Klasifikaci událostí stále provádí existující PWA vizuální kontrakt. `assets/icons/lazensky-v1/icon-map.json` obsahuje pro všech 12 schválených klíčů deterministické `googleCalendarColorId`. Google neumí použít Commander PNG jako ikonu události ani libovolnou hex barvu. Neznámá procedura proto zůstává bez `colorId` a použije výchozí neutrální barvu cílového kalendáře; nikdy se nepřeklasifikuje na `individual_rehab`.

| Icon key | Google `colorId` |
| --- | --- |
| `meal_breakfast` | `6` |
| `meal_lunch` | `6` |
| `meal_dinner` | `6` |
| `pool` | `7` |
| `iodobrom` | `5` |
| `whirlpool` | `7` |
| `peat_wrap` | `11` |
| `imoove` | `2` |
| `massage` | `10` |
| `hydrojet` | `9` |
| `electro_therapy` | `3` |
| `individual_rehab` | `10` |

## Service account

1. V Google Cloud projektu zapnout Google Calendar API.
2. Vytvořit service account bez domain-wide delegation.
3. Oba cílové kalendáře explicitně sdílet s e-mailem service accountu s oprávněním upravovat události.
4. Do GitHub repository secret uložit celý service-account JSON pod názvem `LC_GOOGLE_SERVICE_ACCOUNT_JSON`.
5. Do GitHub repository variables uložit ID kalendářů jako `LC_GOOGLE_CALENDAR_PROCEDURES_ID` a `LC_GOOGLE_CALENDAR_MEALS_ID`.

Credentials, private key, tokeny ani konkrétní calendar IDs se necommitují. Nástroj při chybějící nebo neplatné konfiguraci skončí před vytvořením Google adaptéru a před prvním write. Chybové hlášky nevypisují credential JSON ani tělo odpovědi Google API.

## GitHub Actions

Workflow `.github/workflows/google-calendar-sync.yml` provede write pouze pro `refs/heads/main`:

- automaticky po pushi na `main`, jen když se změnil `data/schedule.json`;
- ručně přes `workflow_dispatch`, pokud je spuštěn nad `main`.

Workflow checkoutne repozitář, nainstaluje zamčené Node dependencies, validuje canonical schedule a sestaví lokální dry-run plán. Teprve potom načte secrets/variables a provede produkční reconciliation. Logovaný výsledek obsahuje jen `scheduleVersion`, `desired`, `created`, `updated`, `deleted` a `unchanged`.

Pull request ani běžný push feature branche produkční write nespouští. `.github/workflows/public-schedule-tests.yml` na nich provádí pouze unit testy s fake adaptérem.

## Lokální dry-run

```bash
npm ci --prefix calendar-sync --ignore-scripts
node calendar-sync/sync-google-calendar.mjs --dry-run
```

Dry-run validuje `data/schedule.json`, vytvoří sdílenou kalendářovou projekci a reconciliation plán proti prázdnému lokálnímu adaptéru. Nepotřebuje Google účet ani environment variables a nemá žádnou implementovanou write cestu. Produkční režim je explicitní `--write` a bez všech tří environment hodnot bezpečně selže.

Regresní testy se spouštějí příkazem:

```bash
node tests/calendar-sync-suite.mjs
```

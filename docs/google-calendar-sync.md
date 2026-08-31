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

## Bezklíčová autentizace GitHub -> Google

Produkční GitHub Actions nepoužívá service-account JSON key ani dlouhodobý GitHub secret. Přihlášení je založené na GitHub OIDC a Google Workload Identity Federation s krátkodobým tokenem.

Google Cloud konfigurace:

- projekt: `lazensky-commander`;
- project number: `217549425263`;
- Workload Identity Pool: `github-actions`;
- OIDC provider: `github-actions`;
- issuer: `https://token.actions.githubusercontent.com`;
- service account: `lazensky-commander-calendar-sy@lazensky-commander.iam.gserviceaccount.com`;
- GitHub repository ID povolený providerem a service-account impersonation policy: `1246852468` (`VarnaKonvice/komander`).

Provider mapuje `google.subject = assertion.sub`, `attribute.repository_id = assertion.repository_id` a `attribute.workflow_ref = assertion.workflow_ref`. Attribute condition omezuje autentizaci na repository ID `1246852468`.

Pro service-account impersonation musí být v Google Cloud zapnuté potřebné IAM/STS služby včetně Service Account Credentials API. Google Calendar API musí být zapnuté samostatně.

Service account nemá domain-wide delegation ani obecné Google Cloud role pro Calendar. Přístup ke kalendářům vzniká pouze tak, že kalendáře `Procedury` a `Jídlo` jsou explicitně nasdílené tomuto service accountu s oprávněním měnit události a zobrazit jejich podrobnosti. Service account nesmí spravovat sdílení kalendáře.

Soukromý klíč se nevytváří. `google-github-actions/auth` vytvoří pouze krátkodobý ADC credential file pro daný běh workflow; `gha-creds-*.json` je v `.gitignore`.

## GitHub Actions

Workflow `.github/workflows/google-calendar-sync.yml` provede write pouze pro `refs/heads/main`:

- automaticky po pushi na `main`, jen když se změnil `data/schedule.json`;
- ručně přes `workflow_dispatch`, pokud je spuštěn nad `main`.

Workflow postupuje v tomto pořadí:

1. checkout repozitáře;
2. instalace zamčených Node dependencies;
3. validace canonical schedule a lokální dry-run;
4. `google-github-actions/auth@v3` získá přes GitHub OIDC krátkodobé Google ADC credentials a impersonuje vyhrazený service account;
5. produkční reconciliation zapíše pouze Commander-owned události.

Workflow má `permissions: contents: read` a `id-token: write`. Nepoužívá `LC_GOOGLE_SERVICE_ACCOUNT_JSON` ani žádný Google credential secret.

ID cílových kalendářů jsou pro tento jedno-uživatelský projekt ne-tajné provozní identifikátory a jsou připnuté přímo v main-only workflow. Nejsou autentizačním údajem a samy o sobě neposkytují přístup ke kalendáři. Tím odpadá další ruční správa GitHub variables.

Pull request ani běžný push feature branche produkční write nespouští. `.github/workflows/public-schedule-tests.yml` na nich provádí pouze unit/static testy s fake adaptérem a kontrolou bezklíčové auth konfigurace.

## Adapter a lokální autentizace

`calendar-sync/google-calendar-adapter.mjs` používá v produkci Application Default Credentials z `GOOGLE_APPLICATION_CREDENTIALS`, který nastaví OIDC auth action. Google klient dostává pouze Calendar OAuth scope.

Pro zpětnou kompatibilitu lokálních vývojových testů adapter zatím umí také explicitní `LC_GOOGLE_SERVICE_ACCOUNT_JSON`; produkční workflow tuto cestu nepoužívá a žádný takový secret není potřeba. Tato fallback větev se může odstranit po úplném přechodu testovací infrastruktury na ADC.

Produkční write selže před vytvořením Google adaptéru, pokud není k dispozici ani ADC, ani explicitní legacy credential, nebo pokud chybí cílové calendar ID.

## Lokální dry-run

```bash
npm ci --prefix calendar-sync --ignore-scripts
node calendar-sync/sync-google-calendar.mjs --dry-run
```

Dry-run validuje `data/schedule.json`, vytvoří sdílenou kalendářovou projekci a reconciliation plán proti prázdnému lokálnímu adaptéru. Nepotřebuje Google účet ani environment variables a nemá žádnou implementovanou write cestu. Produkční režim je explicitní `--write`.

Regresní testy:

```bash
node tests/calendar-sync-suite.mjs
node tests/google-calendar-auth-suite.mjs
```

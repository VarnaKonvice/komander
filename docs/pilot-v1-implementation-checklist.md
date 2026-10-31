# Lázeňský Commander Pilot v1 – implementační checklist

Aktualizováno: 2026-10-23

## Stav 0 – ochrana současné verze

- [x] Zachovat dirty worktree bez resetu/checkoutu/clean.
- [x] Zachovat všechny existující regresní testy.
- [x] Sepsat cílovou pilotní architekturu.
- [x] Sepsat migrační mapu současných souborů.
- [x] Přidat první platform-neutral SpaProfile model.
- [x] Přidat SpaProfile testy.
- [x] Ověřit celý Core suite po prvním architektonickém kroku.
- [x] Ověřit současný iOS build.

Aktuální gate: 328/328 testů, iOS BUILD SUCCEEDED.

## Stav 1 – zmrazení osobního Commanderu

Cíl: dnešní osobní verze zůstane referenční funkční implementací.

- [ ] Uzavřít otevřené chyby současného iPhone runtime.
- [ ] Zapsat referenční build + screenshoty hlavních stavů.
- [ ] Zapsat fyzický alarm acceptance.
- [ ] Označit osobní Watch/Widget/LiveActivity funkce jako optional capability.
- [ ] Nepřidávat nové funkce do osobního UI, pokud nejde o opravu.

Gate:
- plný test suite zelený,
- fyzický telefon bez otevřené kritické chyby,
- referenční build dohledatelný.

## Stav 2 – komerční doménové jádro

Cíl: vše, co později sdílí iOS a Android smluvně, je explicitní a platform-neutral.

- [x] SpaProfile základ.
- [ ] SpaProfile source contract / JSON schema.
- [ ] Procedure alias resolver.
- [ ] Procedure validation result: accepted / review / rejected.
- [ ] Meal shift model + assignment pravidla.
- [ ] Visit/routine event policy.
- [ ] Tenant/Stay identity.
- [ ] Versioned schedule envelope.
- [ ] Čistý AlertPlan nezávislý na AlarmKit názvosloví.
- [ ] UserAlertPreferences – jednoduchý kontrakt.
- [ ] Incident/audit event model bez citlivého obsahu.

Gate:
- žádný UIKit/SwiftUI/AlarmKit/WatchConnectivity import,
- unit test pro každé pravidlo,
- žádné Darkov-specific if/else v produkční doméně.

## Stav 3 – nový pilotní iOS composition root

Cíl: nová aplikace používá stejné doménové jádro, ale nezdědí dnešní monolitický ViewModel.

- [ ] Založit PilotApp target.
- [ ] AppCompositionRoot.
- [ ] AppSyncCoordinator.
- [ ] ActivationViewModel.
- [ ] TodayViewModel.
- [ ] StayViewModel.
- [ ] SettingsViewModel.
- [ ] DiagnosticsRecorder.

Pilotní target NEOBSAHUJE v kritické cestě:
- WatchConnectivity,
- ActivityKit,
- WidgetKit,
- provisioning Personal Team UI.

Kalendář je volitelná capability: jeho selhání nesmí ovlivnit rozpis ani alarmy.

Gate:
- pilotní app target se sestaví samostatně,
- žádný view model > cca 300 řádků,
- view modely neplánují alarmy přímo.

## Stav 4 – základní pacientské UI

Cíl: pacient nemusí rozumět technologii.

### Aktivace
- [ ] QR scan.
- [ ] Ruční kód jako fallback.
- [ ] Jedna potvrzovací obrazovka s názvem lázní a termínem pobytu.
- [ ] Bez registrace heslem v pilotu, pokud není nutná.

### Dnes
- [ ] Velká karta další události.
- [ ] Víceřádkový název.
- [ ] Velký čas.
- [ ] Výrazný „Vyrazit v …“.
- [ ] Výrazné místo.
- [ ] Chronologický zbytek dne.
- [ ] Offline stav bez technického žargonu.

### Týden
- [ ] Přehled minimálně dneška + dalších dnů.
- [ ] Zítřejší program čitelný bez papírového rozpisu.
- [ ] Velké texty a jednoduché rozbalení dne.

### Pobyt
- [ ] Přehled celého pobytu.
- [ ] Souhrny nesmí nahradit přesný rozpis.

### Info
- [ ] Lázeňský dům.
- [ ] Termín pobytu.
- [ ] Pokoj.
- [ ] Lékař / pracoviště, pokud je zdroj poskytuje.
- [ ] Jídelní směna.
- [ ] Další stabilní údaje z profilu pobytu.

### Nastavení
- [ ] Stav upozornění.
- [ ] Jeden globální předstih.
- [ ] Přístupnost / velikost.
- [ ] Ruční aktualizace.
- [ ] Sbalená sekce Pokročilé.

Gate:
- použitelná pouze s telefonem,
- žádný widget/watch krok v onboardingu.

## Stav 5 – přístupnost

- [ ] Dynamic Type normální.
- [ ] Dynamic Type XXXL.
- [ ] Accessibility sizes.
- [ ] VoiceOver pořadí.
- [ ] VoiceOver názvy hlavních tlačítek.
- [ ] Kontrast.
- [ ] Žádná informace pouze barvou.
- [ ] Dlouhý název procedury bez useknutí kritického textu.
- [ ] Velké touch targets.
- [ ] Ověřit systémové možnosti blikání/haptiky v onboarding nápovědě.

Gate:
- největší podporovaný text nerozbije Dnes,
- hlavní tok je možné dokončit VoiceOverem.

## Stav 6 – iOS upozornění

### Plný režim
- [ ] AlarmKit adapter iOS 26+.
- [ ] Read-back.
- [ ] Reconciliation.
- [ ] Audit důkazu naplánování.

### Kompatibilní režim
- [ ] Local notification adapter.
- [ ] Jasně označit nižší systémovou garanci.
- [ ] Ověřit background chování na fyzických starších iPhonech.

### Společné
- [ ] Stejný AlertPlan.
- [ ] Stejný title/location/start.
- [ ] Žádná samostatná Watch logika.
- [ ] Systémové zrcadlení na hodinky je pouze bonus.

Gate:
- každý supported iOS má definovanou úroveň služby,
- pacient ví, když oprávnění chybí.

## Stav 7 – backend / lázeňská integrace

- [ ] Tenant profile endpoint.
- [ ] Stay activation endpoint.
- [ ] Schedule endpoint.
- [ ] Version / ETag nebo ekvivalent.
- [ ] Krátkodobý nebo omezený aktivační token.
- [ ] TLS.
- [ ] Serverové autentizační klíče.
- [ ] Audit změn.
- [ ] Retention pravidla.
- [ ] Měsíční pseudonymní dodací list pro fakturaci.

Gate:
- mobil nečte veřejný GitHub raw schedule,
- bez serverové identity nelze cizí pobyt stáhnout.

## Stav 8 – integrační workshop prvních lázní

- [ ] Kdo vytváří rozpis.
- [ ] Jaký software používají.
- [ ] Existuje API/export.
- [ ] Jak vzniká změna již vydaného rozpisu.
- [ ] Katalog procedur.
- [ ] Kategorie procedur.
- [ ] Očekávané délky.
- [ ] Výchozí předstihy.
- [ ] Budovy/místnosti.
- [ ] Jídelní směny.
- [ ] Vizity.
- [ ] Víkendy/svátky.
- [ ] 10+ anonymizovaných reprezentativních pobytů.
- [ ] Test změny během pobytu.
- [ ] Kontaktní vlastník pilotu na straně lázní.

Výstup:
- SpaProfile v1,
- importní mapování,
- acceptance fixtures,
- pilotní provozní postup.

## Stav 9 – pilot 50–100 pacientů

Měřit:
- počet nabídnutých aktivací,
- počet dokončených aktivací,
- čas aktivace,
- potřebu pomoci personálu,
- počet sync problémů,
- počet nesprávných rozpisů,
- počet chybně naplánovaných alertů,
- počet support požadavků,
- typ telefonu / OS anonymizovaně v agregaci,
- používání přístupnostních režimů.

Stop podmínky:
- nevyřešená chyba canonical času,
- neauditovatelný alert incident,
- ruční administrativní práce na většině aktivací.

## Stav 10 – Android

Začít až když iOS pilotní kontrakty nejsou v pohybu.

- [ ] Kotlin/Android projekt.
- [ ] Stejný backend API contract.
- [ ] Stejný SpaProfile contract.
- [ ] Stejný AlertPlan semantics.
- [ ] Android exact alarm / notification adapter.
- [ ] Battery optimization diagnostika.
- [ ] Velké texty a accessibility.
- [ ] Samsung fyzický test.
- [ ] Druhý OEM fyzický test (Xiaomi/Redmi) před širším rolloutem.

Android nesmí kopírovat iOS implementační detaily. Kopíruje pouze doménové kontrakty a chování.

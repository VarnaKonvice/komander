# Nezazvonění 7. 9. 2026 ve 13:50 – otevřený incident

## Fyzické důkazy

Na produkčním iPhonu nebyl před odchodem jantarový stav, ve 13:50 nezazvonil AlarmKit a nezobrazila se červená karta. Rozpis v5 v `main/data/schedule.json` obsahuje masáž 14:00–14:20 s canonical předstihem 10 minut. Lokální overrides před incidentem nejsou doloženy.

Diagnostika v 14:16 ukazovala v5, AlarmKit v5 ověřeno v 14:15, authorized, pojistka nevyužito, obnova opravena, desired 7, create/update/cancel 0/0/0, repairs 1. Tento údaj nedokládá čas prvního přijetí v5, dřívější oprávnění ani přípravu alarmu před 13:50. Otevření aplikace mohlo provést novou synchronizaci.

## Co přesně znamenají počty

Bez lokálních overrides zbývá v 14:15 právě sedm budoucích odchodů: dnešní večeře a šest zítřejších událostí. Masáž s leaveAt 13:50 již není součástí kontrolovaného desired setu. Ověření těchto sedmi alarmů tedy nemůže potvrdit minulý odchod masáže.

`AlarmSyncService` zvyšuje `repairAttempts` také při odstranění lokálního mapování na již neexistující systémový alarm. Tento úklid probíhá před sestavením hlavního plánu a nezvyšuje jeho create/update/cancel čítače. Také úklid orphan ID má vlastní větev. Proto `repairs=1, 0/0/0` není důkazem vytvoření nebo opravy budoucího alarmu. U odpovídající verze implementace by skutečné vytvoření náhrady zvýšilo create nebo update.

Nový behaviorální test `postDepartureVerifiedCanReportOneRepairWithoutChangingFutureAlarms` připraví osm alarmů, odstraní jeden již minulý ze simulovaného systému a po foreground synchronizaci očekává přesně v5/desired7/repair1/0/0/0. Sedm budoucích platformních ID se nezmění. Test nesimuluje zvuk a neurčuje, zda minulý alarm zazvonil. Test je přidaný, zatím nespouštěný; předchozí zelené CI/buildy nebyly opakovány.

## Konkrétní mezery v implementaci

- Remote schedule fetch i opravné průchody vyžadují běžící aplikaci. Bootstrap, foreground a ruční synchronizace jsou vstupy; odložený patnáctisekundový Task není systémový background scheduler. Pokud příprava před suspendováním neproběhne nebo selže, další repair může přijít až s foregroundem. Publikace JSON ani Google Calendar aplikaci nevzbudí.
- Ověření AlarmKitu je oddělené od přípravy ActivityKit. Produkční `main` potlačuje ActivityKit request error a provádí pouze read, jehož obsah nekontroluje. Může tedy hlásit verified s chybějící aktivitou až do dalšího foreground pokusu. To vysvětluje možnou absenci aktivity, samo o sobě nikoli absenci zvuku. Stabilizační větev už tyto chyby vrací do diagnostiky.
- Stabilizační adapter vybírá přímý AlarmKit alarm bez countdownu podle existence předchozí události v rozpisu (`hasFreeTimeSource`), nikoli podle důkazu aktuálně existující karty volna. Pokud karta chybí, může chybět jantarová prezentace i při existujícím zvukovém alarmu. Tuto cestu nelze bez znalosti instalovaného buildu přiřadit danému incidentu.
- `main` obsahuje jiný adapter než stabilizační větev (mj. nemá nový `CommanderAlarmStopIntent`). Běžný obnovovací launcher vybírá main. Samotný produkční bundle ID a scheduleVersion 5 nerozlišují instalovaný commit.
- Současné UI uchovává poslední souhrn, ne trvalou historii jednotlivých pokusů/SDK pozorování. Novější zelený průchod překryje předchozí selhání. Z poskytnutého screenshotu nelze zpětně určit přijetí v5, vytvoření ID masáže, jeho fireDate ani důvod případného zániku.

## Závěr a nutný další důkaz

Incident zůstává nevyřešený; aplikace nemá nový fyzický PASS a není uzavřená pro začlenění. Není prokázáno, že v 14:15 vznikl chybějící alarm, ani že příčinou nezazvonění byla ActivityKit chyba. Je prokázána mezera mezi následným ověřením budoucích alarmů a dokazováním předchozího alarmového toku.

Další postup je read-only získání instalačního/build logu a případných dochovaných iPhone logů pro období před 13:50. Neměnit instalaci před zajištěním těchto důkazů. Pokud historie není dostupná, nelze tento minulý incident přesně rekonstruovat; další instrumentace musí trvale zachytit fetch/accept čas a verzi, efektivní leaveAt, platformní ID, SDK schedule/read-back výsledek a konkrétní důvod cleanup/repair **před mutací**, nezávisle na výsledku posledního průchodu. Další screenshot až po recovery tento důkaz nenahradí.

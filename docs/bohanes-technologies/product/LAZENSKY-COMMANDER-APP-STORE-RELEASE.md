# Lázeňský Commander – App Store release minimum

**Stav:** pracovní checklist, ověřeno proti aktuální dokumentaci Apple dne 7. 11. 2026.

- App Review musí dostat plný přístup k funkcím; pokud je potřeba aktivace/QR/backend, dodat funkční demo nebo vzorový QR.
- Digitální funkce odemykané spotřebiteli v aplikaci se pro standardní App Store distribuci navrhují s In-App Purchase, pokud konkrétní schválená distribuční výjimka neurčí jinak.
- B2B partner aktivace je samostatný smluvní kanál; aplikace musí umět ověřit již existující oprávnění bez zásahu do logiky rozpisu.
- Apple Standard EULA lze použít bez vlastní EULA.
- Privacy Policy URL je pro App Store povinná a odkaz musí být snadno dostupný také v aplikaci.
- App Store Connect musí pravdivě popsat skutečné zpracování dat aplikací i použitými SDK.
- Minimum aplikace je iOS 16.1; AlarmKit je funkční až od iOS 26.1. Starší podporovaný iOS používá Commander bez systémových Commander alarmů.
- První spuštění nesmí samo vyžádat Kalendář ani běžná oznámení. Přístup k Apple Kalendáři se žádá až po ručním zapnutí této volitelné funkce v Nastavení.
- Před vydáním doplnit ověřené identifikační údaje provozovatele a podporu.

Oficiální zdroje:
- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement
- https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy

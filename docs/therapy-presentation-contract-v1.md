# Commander – léčebné skupiny a délky

Schválené rozhodnutí pro navazující UI/datový krok po stabilizaci alarmového toku.

## Pobyt

Karta `Pobyt` zobrazuje každou konkrétní proceduru samostatně a bez nutnosti rozbalování. Uživatel má hned vidět například `Magnetoterapie 3/5`, `Hydrojet 1/2`, `Jodobromová koupel 2/4` apod.

Procedury se NESČÍTAJÍ do jedné společné řádky podle léčebné skupiny. Skupina určuje pouze sdílenou vizuální identitu/barvu. Konkrétní název a jeho vlastní počet zůstávají viditelné.

## Barevné skupiny

Stejná léčebná skupina používá stejnou barvu napříč Commanderem. Počáteční taxonomie:

- `elektrolecba`: magnetoterapie, ultrazvuk, čtyřkomorovka a obdobné elektroléčebné procedury;
- `masaze`: klasická masáž, Hydrojet a obdobné masážní procedury;
- `koupele_vodolecba`: jodobromová, perličková, bublinková, vířivá vana a obdobné koupele/vodoléčba;
- `rehabilitace_cviceni`: individuální rehabilitace, cvičení, chodicí pás a obdobné pohybové procedury;
- `logopedie_ergoterapie`: logopedie a ergoterapie;
- další skupiny se přidají až podle skutečného lázeňského rozpisu, ne předem.

Legenda v `Info` není povinná, pokud je systém barev v reálném rozpisu dostatečně intuitivní. Pokud se ukáže nejednoznačnost, přidá se stručná legenda až následně.

## Délky událostí

Canonical rozpis je zdroj pravdy. Pokud sken/papírový rozpis uvádí začátek a konec, použije se přesná délka z něj a lokální nastavení ji nepřepisuje.

Výchozí délky slouží pouze pro případ, kdy konec z podkladu není znám:

- procedura: 20 minut;
- jídlo: 45 minut.

Typová výjimka (např. desetiminutová elektroléčba) se použije pouze při chybějícím konci v canonical podkladu. Délka nesmí vytvořit druhý lokální zdroj pravdy odlišný od Google Kalendáře, AlarmKitu, Watch nebo Commander UI.

## Pořadí práce

Tento kontrakt se implementuje až po uzavření současného alarmového stabilizačního balíku: runtime ledger + ověřený Live Activity handoff/fallback. Design Lock Screen Live Activity se tímto dokumentem nemění.

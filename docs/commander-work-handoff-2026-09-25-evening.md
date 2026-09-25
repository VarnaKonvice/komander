# Lázeňský Commander — evening handoff 2026-09-25

## Freeze point

Petr considers the current visual state near-final. Do not make further visual changes until the next session starts from this exact state.

Verified before freeze:
- 210/210 Swift package tests passed.
- Physical iPhone build succeeded and was installed.
- Dnes and Pobyt visual proofs were captured in the final semantic/alignment pass.

## Approved visual/state changes from this evening

- Commander brand/header remains fixed across tabs.
- The tab context row remains fixed below it while content scrolls underneath.
- Global `ROZPIS` status pill sits in the right side of that row and opens the audit detail.
- Day summary uses three wide tiles only: Terapie / Konec procedur / Volno do večeře.
- Dinner time is not duplicated in the summary.
- Today stay indicator uses `Den pobytu` + compact `current / total` + progress bar.
- Day/stay semantics are blue/cyan.
- Aggregate therapy/procedure semantics are pink.
- Individual procedure/category colors remain unchanged.
- `Odchod za` capsule uses Commander navy/blue rather than near-black.
- Bottom navigation has a slightly squarer outer radius to better match the Commander header family.

## Must fix tomorrow before continuing Live Activities / alarms

### 1. Audit-detail navigation bug

Reproduction reported by Petr:
- Open `Kontrola rozpisu` by tapping the global `ROZPIS · 1 kontrola` pill while on `Dnes`.
- The dedicated audit screen opens correctly.
- Tapping the bottom `Dnes` tab does not return/dismiss/pop the audit detail because `Dnes` is already the selected root tab.
- Entering the audit from another root tab behaves differently when switching tabs.

Required behavior:
- Bottom tab taps must always return to that tab's root screen, even when the selected tab is already active and a pushed audit detail is on top.
- Do not leave navigation behavior dependent on which tab launched the audit.

Likely architectural direction:
- Treat the audit as a dedicated destination owned by Settings / a root navigation coordinator, and let the global status pill deep-link to it.
- Alternatively use a modal/sheet/full-screen presentation whose dismissal semantics are independent of the current tab.
- Preserve the visible global status pill; only fix the navigation ownership/dismissal model.

### 2. Restore Pobyt content; keep audit separate

Petr explicitly wants `Pobyt` restored to its intended stay-content role. The audit is a separate screen, conceptually under `Nastavení`.

Required structure:
- `Pobyt`: stay/procedure summary and its original stay information; do not repurpose it as audit UI.
- `Info`: stay metadata such as doctor/diagnosis/room according to the existing approved design.
- `Nastavení`: contains the normal entry `Kontrola rozpisu`.
- Global `ROZPIS` status pill may open the same dedicated audit screen directly.

Before changing Pobyt tomorrow, compare against the last approved pre-audit visual checkpoint rather than redesigning from memory.

## Next larger work after these two fixes

Resume the safety/audit work, then Live Activities and alarm/read-back work from branch `lc/schedule-acceptance-audit-v1`.

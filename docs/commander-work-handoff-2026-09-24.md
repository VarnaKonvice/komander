# Commander UI Work handoff — 24. 9. 2026

## Environment
- Worktree: /Users/petrbohanes/komander-app-schedule-redesign
- Branch: lc/app-schedule-redesign-v1
- Base HEAD: 0a2c2d197a73913386f9630fdbb24ce91d883166
- Xcode: 27.0
- Swift: 6.4
- Physical iPhone 16 UDID: 00008140-0019586A3607001C
- Simulator iPhone 16 UDID: 4326B970-343F-4DBA-B1AD-FF174B3D4066

## Single visual source of truth
Read docs/commander-approved-visual-source-2026-09-24.md.
The user will also attach the approved infographic. Do not invent or substitute colors, icons, categories, layout logic, or alternate references.

## Already prepared
- Central category -> color mapping is in Shared/CommanderBrandAssets.swift.
- Central category -> symbol mapping is in the same file.
- All normal circular icon badges use one standard 50 pt size.
- Only the two featured cards in Co mě teď čeká may use 59 pt.
- CommanderSymbolBadge normalizes inner glyph footprint.
- Summary-card colors are aligned to the approved infographic.
- Past-state dimming and business/data logic must remain untouched.

## Heavy UI work remaining
- Lighten summary cards and procedure rows slightly without changing page background.
- Increase category-color presence in card faces.
- Preserve crisp neon edges.
- No broad blur, haze, milkiness, or glowing text fog.
- Verify Today, Today's program, Week collapsed/expanded, and current/future cards.

## Validation
Run:
git diff --check
swift test --package-path native/LazenskyCommander

Then physical iPhone build with:
xcodebuild -project native/LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj -scheme LazenskyCommanderApp -configuration Debug -destination 'platform=iOS,id=00008140-0019586A3607001C' -allowProvisioningUpdates build

Do not commit or push.

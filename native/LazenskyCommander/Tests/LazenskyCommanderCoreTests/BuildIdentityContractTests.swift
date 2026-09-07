#if canImport(Testing)
import Foundation
import Testing

@Test func stabilizationInstallerEmbedsExactBuildIdentityWithoutChangingProductionDefault() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  let plist = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/Info.plist"),
    encoding: .utf8
  )
  #expect(plist.contains("<key>LCBuildBranch</key>"))
  #expect(plist.contains("<string>$(LC_BUILD_BRANCH)</string>"))
  #expect(plist.contains("<key>LCBuildCommit</key>"))
  #expect(plist.contains("<string>$(LC_BUILD_COMMIT)</string>"))

  let diagnostics = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/CommanderSystemStatusView.swift"),
    encoding: .utf8
  )
  #expect(diagnostics.contains("Nainstalovaný kód"))
  #expect(diagnostics.contains("LCBuildBranch"))
  #expect(diagnostics.contains("LCBuildCommit"))
  #expect(diagnostics.contains("commit.prefix(8)"))

  let productionRefresh = try String(
    contentsOf: repo.appendingPathComponent("Obnovit Lázeňský Commander.command"),
    encoding: .utf8
  )
  #expect(productionRefresh.contains("TARGET_BRANCH=\"${LC_REFRESH_TARGET_BRANCH:-main}\""))

  let stabilization = try String(
    contentsOf: repo.appendingPathComponent("Nainstalovat stabilizační test.command"),
    encoding: .utf8
  )
  #expect(stabilization.contains("TARGET_BRANCH=\"lc/native-stabilization-v2\""))
  #expect(stabilization.contains("LC_BUILD_BRANCH = %s"))
  #expect(stabilization.contains("LC_BUILD_COMMIT = %s"))
  #expect(stabilization.contains("XCODE_XCCONFIG_FILE=\"$TEMP_XCCONFIG\""))
  #expect(stabilization.contains("LC_REFRESH_TARGET_BRANCH=\"$TARGET_BRANCH\""))
  #expect(stabilization.contains("Pokud Diagnostika ukáže jinou identitu"))
}
#endif

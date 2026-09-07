#if canImport(Testing)
import Foundation
import Testing

@Test func installedBuildIdentityIsEmbeddedAndVerifiedBeforeInstallation() throws {
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

  let refresh = try String(
    contentsOf: repo.appendingPathComponent("Obnovit Lázeňský Commander.command"),
    encoding: .utf8
  )
  #expect(refresh.contains("LC_BUILD_BRANCH=\"$TARGET_BRANCH\""))
  #expect(refresh.contains("LC_BUILD_COMMIT=\"$GIT_COMMIT\""))
  #expect(refresh.contains("APP_BUILD_BRANCH=\"$(plist_raw LCBuildBranch"))
  #expect(refresh.contains("APP_BUILD_COMMIT=\"$(plist_raw LCBuildCommit"))
  #expect(refresh.contains("$APP_BUILD_BRANCH\" != \"$TARGET_BRANCH"))
  #expect(refresh.contains("$APP_BUILD_COMMIT\" != \"$GIT_COMMIT"))
}
#endif

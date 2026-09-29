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
  let unified = try String(
    contentsOf: repo.appendingPathComponent("Otestovat Lázeňský Commander.command"),
    encoding: .utf8
  )
  #expect(stabilization.contains("exec /bin/bash \"$SCRIPT_DIR/Otestovat Lázeňský Commander.command\" \"$@\""))
  #expect(unified.contains("build_branch=\"$(/usr/bin/git -C \"$REPO_ROOT\" branch --show-current"))
  #expect(unified.contains("build_commit=\"$(/usr/bin/git -C \"$REPO_ROOT\" rev-parse HEAD"))
  #expect(unified.contains("LC_BUILD_BRANCH=\"$build_branch\" LC_BUILD_COMMIT=\"$build_commit\""))
  #expect(unified.contains("BUILD_BRANCH=\"$(/usr/bin/git -C \"$REPO_ROOT\" branch --show-current"))
  #expect(unified.contains("BUILD_COMMIT=\"$(/usr/bin/git -C \"$REPO_ROOT\" rev-parse HEAD"))
  #expect(unified.contains("LC_BUILD_BRANCH=\"$BUILD_BRANCH\""))
  #expect(unified.contains("LC_BUILD_COMMIT=\"$BUILD_COMMIT\""))
  #expect(unified.contains("--build-normal"))
  #expect(unified.contains("--install-normal"))
  #expect(!unified.contains("git checkout"))
  #expect(!unified.contains("git reset"))
  #expect(!unified.contains("git clean"))
}
#endif

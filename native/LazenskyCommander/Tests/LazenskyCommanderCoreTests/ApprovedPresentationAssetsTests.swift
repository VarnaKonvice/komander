import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test(arguments: [
  ("Magnetoterapie", "electro_therapy"),
  ("Individuální rehabilitace", "individual_rehab"),
  ("Jodobromová koupel", "iodobrom"),
  ("Čtyřkomorová lázeň", "electro_therapy"),
  ("Snídaně", "meal_breakfast"),
  ("Oběd", "meal_lunch"),
  ("Večeře", "meal_dinner"),
  ("Hydrojet", "hydrojet"),
  ("iMoove", "imoove")
])
func approvedPresentationUsesCanonicalArtworkAndProcedureColor(title: String, key: String) throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("assets/icons/lazensky-v1")
  let map = try JSONDecoder().decode(CommanderIconMap.self, from: Data(contentsOf: root.appendingPathComponent("icon-map.json")))
  let colors = try JSONDecoder().decode(CommanderColorMap.self, from: Data(contentsOf: root.appendingPathComponent("colors.json")))
  let icon = try #require(map.classify(title: title))
  #expect(icon.key == key)
  #expect(icon.accent == colors.procedures[key.hasPrefix("meal_") ? "meal" : key])
  let png = try Data(contentsOf: root.appendingPathComponent("icons/128/\(key).png"))
  #expect(Array(png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
  #expect(map.classify(title: "Neznámá procedura XYZ") == nil)
}

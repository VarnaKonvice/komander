import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test(arguments: [
  ("Magnetoterapie", "electro_therapy", "#6D5BD0"),
  ("Individuální rehabilitace", "individual_rehab", "#22A06B"),
  ("Jodobromová koupel", "iodobrom", "#B27A2C"),
  ("Čtyřkomorová lázeň", "electro_therapy", "#6D5BD0"),
  ("Snídaně", "meal_breakfast", "#50B863"),
  ("Oběd", "meal_lunch", "#50B863"),
  ("Večeře", "meal_dinner", "#50B863"),
  ("Hydrojet", "hydrojet", "#0EA5E9"),
  ("iMoove", "imoove", "#149B91")
])
func approvedPresentationUsesApprovedCategoryColor(
  title: String,
  key: String,
  expectedColor: String
) throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let assets = root.appendingPathComponent("assets/icons/lazensky-v1")
  let map = try JSONDecoder().decode(
    CommanderIconMap.self,
    from: Data(contentsOf: assets.appendingPathComponent("icon-map.json"))
  )
  let colors = try JSONDecoder().decode(
    CommanderColorMap.self,
    from: Data(contentsOf: assets.appendingPathComponent("colors.json"))
  )
  let icon = try #require(map.classify(title: title))
  #expect(icon.key == key)
  #expect(icon.accent == expectedColor)
  #expect(colors.procedures[key.hasPrefix("meal_") ? "meal" : key] == expectedColor)
  #expect(map.classify(title: "Neznámá procedura XYZ") == nil)
}

@Test func approvedNativeProcedureSymbolsMatchVisualSourceOfTruth() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appendingPathComponent(
      "native/LazenskyCommanderApp/Shared/CommanderBrandAssets.swift"
    ),
    encoding: .utf8
  )

  #expect(source.contains("case .meal: return Colors.mealGreen"))
  #expect(source.contains("case .water: return Colors.waterAqua"))
  #expect(source.contains("case .rehabilitation: return Colors.rehabilitationBlue"))
  #expect(source.contains("case .massage: return Colors.massageCoral"))
  #expect(source.contains("case .heatWrap: return Colors.heatOchre"))
  #expect(source.contains("case .electro: return Colors.electroIndigo"))
  #expect(source.contains("case .fallback: return Colors.therapyPink"))

  #expect(source.contains("case .meal: return \"fork.knife\""))
  #expect(source.contains("case .water: return \"drop\""))
  #expect(source.contains("case .rehabilitation: return \"figure.run\""))
  #expect(source.contains("case .massage: return \"leaf.fill\""))
  #expect(source.contains("case .heatWrap: return \"commander.heat.waves\""))
  #expect(source.contains("case .electro: return \"atom\""))
  #expect(source.contains("case .fallback: return \"cross.case.fill\""))
}

import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test(arguments: [
  ("Elektrický chodník", "individual_rehab", "#22A06B"),
  ("Motomed", "individual_rehab", "#22A06B"),
  ("Individuální LTV", "individual_rehab", "#22A06B"),
  ("ILTV ergoterapie", "individual_rehab", "#22A06B"),
  ("ILTV Imoove", "imoove", "#149B91"),
  ("Perličková koupel+zábal", "whirlpool", "#38BDF8"),
  ("Vodní CO2 koupel+zábal", "whirlpool", "#38BDF8"),
  ("CO2 koupel+zábal", "whirlpool", "#38BDF8"),
  ("Vířivá koupel HKK", "whirlpool", "#38BDF8"),
  ("Celotělová vířivá koupel", "whirlpool", "#38BDF8"),
  ("Čtyřkomorová lázeň", "electro_therapy", "#6D5BD0"),
  ("Parafango-obklad", "peat_wrap", "#5B3A29"),
  ("Klasická masáž", "massage", "#65A30D"),
  ("Zábal", "peat_wrap", "#5B3A29")
])
func darkovVisualClassificationPreservesProcedureMeaning(
  title: String, expectedKey: String, expectedAccent: String
) throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let map = try JSONDecoder().decode(
    CommanderIconMap.self,
    from: Data(contentsOf: root.appendingPathComponent("assets/icons/lazensky-v1/icon-map.json"))
  )

  // Check original source text, case, decomposed Unicode and the unaccented
  // spellings used by imports. Both title-only and complete-event paths matter.
  let titles = [title, title.uppercased(), title.decomposedStringWithCanonicalMapping,
                title.folding(options: .diacriticInsensitive, locale: Locale(identifier: "cs_CZ"))]
  for variant in titles {
    let icon = try #require(map.classify(title: variant))
    #expect(icon.key == expectedKey, "Incorrect visual category for \(variant)")
    #expect(icon.accent == expectedAccent)
    let event = ScheduleEvent(
      stableId: "classification", date: "2026-09-30", start: "08:00", end: "08:20",
      title: variant, location: "RS A 4. etáž LAZ11", kind: .procedure,
      procedureType: variant, mealType: nil, leadTimeMinutes: nil
    )
    #expect(map.classify(event)?.key == expectedKey)
  }
}

import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test(arguments: [
  ("Elektrický chodník", "individual_rehab", "#2EE6C4"),
  ("Motomed", "individual_rehab", "#2EE6C4"),
  ("Individuální LTV", "individual_rehab", "#2EE6C4"),
  ("ILTV ergoterapie", "individual_rehab", "#2EE6C4"),
  ("ILTV Imoove", "imoove", "#2EE6C4"),
  ("Perličková koupel+zábal", "whirlpool", "#2ED4FF"),
  ("Vodní CO2 koupel+zábal", "whirlpool", "#2ED4FF"),
  ("CO2 koupel+zábal", "whirlpool", "#2ED4FF"),
  ("Vířivá koupel HKK", "whirlpool", "#2ED4FF"),
  ("Celotělová vířivá koupel", "whirlpool", "#2ED4FF"),
  ("Čtyřkomorová lázeň", "electro_therapy", "#D6B4FE"),
  ("Parafango-obklad", "peat_wrap", "#FFC857"),
  ("Klasická masáž", "massage", "#FF7A59"),
  ("Zábal", "peat_wrap", "#FFC857")
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

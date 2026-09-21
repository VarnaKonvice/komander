import Foundation
import LazenskyCommanderCore
import SwiftUI

enum CommanderBrandAssets {
    static let circularMarkName = "BrandCircularMark"
    static let smallGlyphName = "BrandSmallGlyph"

    static var circularMark: Image {
        Image(circularMarkName)
    }

    static var smallGlyph: Image {
        Image(smallGlyphName)
    }

    enum Colors {
        static let background = "#0E1530"
        static let panel = "#141C3E"
        static let panelStroke = "#4E68D8"
        static let primaryPurple = "#A873FF"
        static let locationBlue = "#4CC8FF"
        static let mealGreen = "#50B863"
        static let amber = "#FFB54A"
        static let freeBlue = "#2EA6FF"
        static let procedureCyan = "#2ED4FF"
        static let urgentOrange = "#FF8A00"
        static let criticalRed = "#F45A4A"
        static let textSecondary = "#A6B0D6"
        static let commanderPurple = "#6E56CF"
        static let commanderPurpleDark = "#4C359B"
        static let commanderPurpleLight = "#A178FF"
        static let waterBlue = "#2ED4FF"
        static let timeGold = "#FFC45A"
        static let brandSurfaceDark = "#2B1A4D"

        // One semantic palette shared by app, AlarmKit, Live Activity and Watch.
        static let heatOchre = "#D69E2E"
        static let waterAqua = "#2ED4FF"
        static let electroIndigo = "#8A7CFF"
        static let rehabilitationBlue = "#2EA6FF"
        static let massageCoral = "#FF7A59"
    }

    private static let iconMap: CommanderIconMap? = decode("icon-map")
    private static let palette: [String: [String: String]]? = decode("colors")

    private static func decode<T: Decodable>(_ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    static func approvedIcon(iconKey: String?, title: String) -> CommanderIconMap.Icon? {
        if let iconKey, let icon = iconMap?.icons.first(where: { $0.key == iconKey }) { return icon }
        return iconMap?.classify(title: title)
    }

    static func procedureAccentHex(iconKey: String?, title: String, isMeal: Bool) -> String {
        approvedIcon(iconKey: iconKey, title: title)?.accent
            ?? iconMap?.fallback.accent ?? Colors.commanderPurple
    }

    // Presentation state is deliberately separate from the approved procedure palette.
    // The approved visual reference overrides the old green/orange state choices in colors.json.
    enum Presentation {
        static var countdown: Color { Color(commanderPresentationHex: palette?["brand"]?["timeGold"] ?? Colors.timeGold) }
        static var active: Color { Color(commanderPresentationHex: palette?["brand"]?["commanderPurpleLight"] ?? Colors.commanderPurpleLight) }
        static var alert: Color { Color(commanderPresentationHex: Colors.criticalRed) }
        static var neutral: Color { Color(commanderPresentationHex: palette?["state"]?["day_done"] ?? "#9CA3AF") }
    }

    static func procedureSymbol(
        iconKey: String?,
        title: String,
        isMeal: Bool
    ) -> String {
        if isMeal || iconKey?.hasPrefix("meal_") == true { return "fork.knife" }
        let normalized = normalizedTitle(title)
        if ["jodobrom", "parafin", "parafango", "slatin", "raselin", "zabal"].contains(where: normalized.contains) { return "thermometer.medium" }
        if ["elektro", "magnet", "ultrazvuk", "galvan", "ctyrkomor", "laser"].contains(where: normalized.contains) { return "atom" }
        if ["viriv", "whirlpool", "perlick", "uhlicit", "bazen", "plav", "koupel"].contains(where: normalized.contains) { return "water.waves" }
        if ["imoove", "i-moove", "fyzioter", "fyzio", "rehab", "ltv", "ergoter", "cvic", "chuze", "chodici pas", "walking pas"].contains(where: normalized.contains) { return "figure.walk" }
        if ["hydrojet", "hydro jet", "masaz"].contains(where: normalized.contains) { return "figure.mind.and.body" }

        switch iconKey {
        case "electro_therapy": return "atom"
        case "iodobrom", "peat_wrap": return "thermometer.medium"
        case "whirlpool", "pool": return "water.waves"
        case "massage", "hydrojet": return "figure.mind.and.body"
        case "individual_rehab", "imoove": return "figure.walk"
        default: return "calendar"
        }
    }

    private static func normalizedTitle(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased(with: Locale(identifier: "cs_CZ"))
    }
}
/// Original approved artwork, never a semantic SF Symbol or a recolored template.
struct CommanderProcedureArtwork: View {
    let iconKey: String?
    let title: String
    let size: CGFloat

    var body: some View {
        let key = CommanderBrandAssets.approvedIcon(iconKey: iconKey, title: title)?.key
        Image(key ?? CommanderBrandAssets.circularMarkName, bundle: .main)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
            .accessibilityHidden(true)
    }
}

extension Color {
    init(commanderPresentationHex: String) {
        let value = commanderPresentationHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        self.init(red: Double((rgb >> 16) & 0xff) / 255,
                  green: Double((rgb >> 8) & 0xff) / 255,
                  blue: Double(rgb & 0xff) / 255)
    }
}

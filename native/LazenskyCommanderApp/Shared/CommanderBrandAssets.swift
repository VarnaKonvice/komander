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
        static let heatOchre = "#FFC857"
        static let waterAqua = "#2ED4FF"
        static let electroIndigo = "#D6B4FE"
        static let rehabilitationBlue = "#2EE6C4"
        static let massageCoral = "#FF7A59"
        static let therapyPink = "#FF5DA8"
        static let procedureEndNeutral = "#94A3B8"
        static let freeTimeCyan = "#2ED4FF"
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

    enum ProcedureFamily {
        case meal
        case water
        case rehabilitation
        case massage
        case heatWrap
        case electro
        case fallback

        var accentHex: String {
            switch self {
            case .meal: return Colors.mealGreen
            case .water: return Colors.waterAqua
            case .rehabilitation: return Colors.rehabilitationBlue
            case .massage: return Colors.massageCoral
            case .heatWrap: return Colors.heatOchre
            case .electro: return Colors.electroIndigo
            case .fallback: return Colors.therapyPink
            }
        }

        var symbol: String {
            switch self {
            case .meal: return "fork.knife"
            case .water: return "drop"
            case .rehabilitation: return "figure.run"
            case .massage: return "leaf.fill"
            case .heatWrap: return "commander.heat.waves"
            case .electro: return "atom"
            case .fallback: return "cross.case.fill"
            }
        }
    }

    static func procedureFamily(iconKey: String?, title: String, isMeal: Bool) -> ProcedureFamily {
        if isMeal || iconKey?.hasPrefix("meal_") == true { return .meal }

        let normalized = normalizedTitle(title)

        // One source of truth for every screen. Order is intentional.
        if ["jodobrom", "parafin", "parafango", "slatin", "raselin", "zabal"].contains(where: normalized.contains) {
            return .heatWrap
        }
        if ["elektro", "magnet", "ultrazvuk", "galvan", "galvanika", "ctyrkomor", "ctyrkomorovka", "razov", "shockwave"].contains(where: normalized.contains) {
            return .electro
        }
        if ["hydrojet", "hydro jet", "masaz"].contains(where: normalized.contains) {
            return .massage
        }
        if ["viriv", "whirlpool", "perlick", "uhlicit", "bazen", "plav", "koupel"].contains(where: normalized.contains) {
            return .water
        }
        if ["imoove", "i-moove", "fyzioter", "fyzio", "rehab", "ltv", "ergoter", "cvic", "chuze", "chodici pas", "walking pas", "senzomotor", "motodlaha"].contains(where: normalized.contains) {
            return .rehabilitation
        }

        switch iconKey {
        case "meal_breakfast", "meal_lunch", "meal_dinner":
            return .meal
        case "iodobrom", "peat_wrap":
            return .heatWrap
        case "electro_therapy":
            return .electro
        case "massage", "hydrojet":
            return .massage
        case "whirlpool", "pool":
            return .water
        case "individual_rehab", "imoove":
            return .rehabilitation
        default:
            return .fallback
        }
    }

    static func procedureAccentHex(iconKey: String?, title: String, isMeal: Bool) -> String {
        procedureFamily(iconKey: iconKey, title: title, isMeal: isMeal).accentHex
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
        procedureFamily(iconKey: iconKey, title: title, isMeal: isMeal).symbol
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

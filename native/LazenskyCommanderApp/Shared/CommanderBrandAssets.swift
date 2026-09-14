import Foundation
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
        static let waterBlue = "#38B6FF"
        static let timeGold = "#FFC45A"
        static let brandSurfaceDark = "#2B1A4D"

        // Procedure accents are deliberately vivid and shared by iPhone,
        // Live Activity / Dynamic Island and Watch. The purple Commander
        // identity remains the surface language; these colors are accents only.
        static let slatinaAmber = "#FFB54A"
        static let hydroCyan = "#2ED4FF"
        static let imooveTeal = "#2FC7A6"
        static let massageLime = "#8BC34A"
        static let electroIndigo = "#8A7CFF"
        static let physiotherapyBlue = "#2EA6FF"
        static let exercisePurple = "#A873FF"
        static let rehabGreen = "#22A06B"
    }

    static func procedureAccentHex(
        iconKey: String?,
        title: String,
        isMeal: Bool
    ) -> String {
        if isMeal || iconKey?.hasPrefix("meal_") == true {
            return Colors.mealGreen
        }

        let normalized = normalizedTitle(title)
        if normalized.contains("fyzioter") || normalized.contains("fyzio") {
            return Colors.physiotherapyBlue
        }
        if normalized.contains("cviceni") || normalized.contains("cvic") {
            return Colors.exercisePurple
        }

        switch iconKey {
        case "iodobrom", "peat_wrap":
            return Colors.slatinaAmber
        case "hydrojet", "whirlpool", "pool":
            return Colors.hydroCyan
        case "imoove":
            return Colors.imooveTeal
        case "massage":
            return Colors.massageLime
        case "electro_therapy":
            return Colors.electroIndigo
        case "individual_rehab":
            return Colors.rehabGreen
        default:
            return Colors.primaryPurple
        }
    }

    static func procedureSymbol(
        iconKey: String?,
        title: String,
        isMeal: Bool
    ) -> String {
        if isMeal || iconKey?.hasPrefix("meal_") == true { return "fork.knife" }

        let normalized = normalizedTitle(title)
        if normalized.contains("fyzioter") || normalized.contains("fyzio") {
            return "figure.walk"
        }
        if normalized.contains("cviceni") || normalized.contains("cvic") {
            return "figure.strengthtraining.traditional"
        }

        switch iconKey {
        case "electro_therapy": return "atom"
        case "iodobrom", "whirlpool": return "bathtub.fill"
        case "massage", "peat_wrap": return "figure.mind.and.body"
        case "pool", "hydrojet": return "water.waves"
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
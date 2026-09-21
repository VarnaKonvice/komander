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

    static func procedureAccentHex(
        iconKey: String?,
        title: String,
        isMeal: Bool
    ) -> String {
        if isMeal || iconKey?.hasPrefix("meal_") == true { return Colors.mealGreen }

        let normalized = normalizedTitle(title)
        // Heat must win before generic water/massage wording.
        if ["jodobrom", "parafin", "parafango", "slatin", "raselin", "zabal"].contains(where: normalized.contains) {
            return Colors.heatOchre
        }
        if ["elektro", "magnet", "ultrazvuk", "galvan", "ctyrkomor", "laser"].contains(where: normalized.contains) {
            return Colors.electroIndigo
        }
        if ["viriv", "whirlpool", "perlick", "uhlicit", "bazen", "plav", "koupel"].contains(where: normalized.contains) {
            return Colors.waterAqua
        }
        if ["imoove", "i-moove", "fyzioter", "fyzio", "rehab", "ltv", "ergoter", "cvic", "chuze", "chodici pas", "walking pas"].contains(where: normalized.contains) {
            return Colors.rehabilitationBlue
        }
        if ["hydrojet", "hydro jet", "masaz"].contains(where: normalized.contains) {
            return Colors.massageCoral
        }

        switch iconKey {
        case "iodobrom", "peat_wrap": return Colors.heatOchre
        case "whirlpool", "pool": return Colors.waterAqua
        case "electro_therapy": return Colors.electroIndigo
        case "individual_rehab", "imoove": return Colors.rehabilitationBlue
        case "massage", "hydrojet": return Colors.massageCoral
        default: return Colors.primaryPurple
        }
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
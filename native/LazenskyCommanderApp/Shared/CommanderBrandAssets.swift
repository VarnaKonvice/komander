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

    static let iconMap: CommanderIconMap? = decode("icon-map")
    static let colors: CommanderColorMap? = decode("colors")
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

        // The visual map ranks specific procedures above generic words such as
        // "zábal". Keep this separate from categories used by departure settings.
        switch iconMap?.classify(title: title)?.key ?? iconKey {
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
            break
        }

        switch CommanderProcedureCategory.classify(title) {
        case .rehabilitation: return .rehabilitation
        case .electro: return .electro
        case .water: return .water
        case .massage: return .massage
        case .heatWrap: return .heatWrap
        case .other: return .fallback
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
/// One approved visual language for procedure/category icons on every native surface.
/// Small surfaces scale the same badge; they never fall back to the Commander lotus mark.
struct CommanderProcedureArtwork: View {
    let iconKey: String?
    let title: String
    let size: CGFloat
    var kind: ScheduleKind? = nil

    private var isMeal: Bool {
        if kind == .meal || iconKey?.hasPrefix("meal_") == true { return true }
        let normalized = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased(with: Locale(identifier: "cs_CZ"))
        return ["snidane", "obed", "vecere"].contains(where: normalized.contains)
    }

    private var family: CommanderBrandAssets.ProcedureFamily {
        CommanderBrandAssets.procedureFamily(
            iconKey: iconKey,
            title: title,
            isMeal: isMeal
        )
    }

    private var accent: Color {
        Color(commanderPresentationHex: family.accentHex)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.13),
                            Color(commanderPresentationHex: "#052D78")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(accent, lineWidth: size >= 32 ? 1.45 : 1.0)

            if family.symbol == "commander.heat.waves" {
                CommanderHeatWavesArtwork(color: accent)
                    .frame(width: size * 0.55, height: size * 0.55)
            } else {
                Image(systemName: family.symbol)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(accent)
                    .frame(width: size * 0.54, height: size * 0.54)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct CommanderHeatWavesArtwork: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let stroke = max(1.3, min(w, h) * 0.085)

            ZStack {
                ForEach([0.29, 0.50, 0.71], id: \.self) { factor in
                    Path { path in
                        let x = w * factor
                        path.move(to: CGPoint(x: x, y: h * 0.66))
                        path.addCurve(
                            to: CGPoint(x: x, y: h * 0.47),
                            control1: CGPoint(x: x - w * 0.055, y: h * 0.60),
                            control2: CGPoint(x: x + w * 0.055, y: h * 0.54)
                        )
                        path.addCurve(
                            to: CGPoint(x: x, y: h * 0.28),
                            control1: CGPoint(x: x - w * 0.055, y: h * 0.41),
                            control2: CGPoint(x: x + w * 0.055, y: h * 0.35)
                        )
                        path.addCurve(
                            to: CGPoint(x: x, y: h * 0.11),
                            control1: CGPoint(x: x - w * 0.050, y: h * 0.22),
                            control2: CGPoint(x: x + w * 0.050, y: h * 0.16)
                        )
                    }
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
                    )
                }

                Capsule()
                    .fill(color)
                    .frame(width: w * 0.58, height: stroke * 1.15)
                    .position(x: w * 0.50, y: h * 0.84)
            }
        }
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

/// One timer renderer for system-hosted presentations. Watch foreground uses the
/// same semantic target with a snapshot string because it has its own TimelineView.
struct CommanderSystemCountdown: View {
  let target: Date

  var body: some View {
    // Keep both bounds absolute. The system-hosted renderer advances this timer
    // without waking the app. Do not provide pauseTime: a future pause date
    // physically froze the value captured when the Live Activity was archived.
    let lowerBound = target.addingTimeInterval(-24 * 60 * 60)
    Text(
      timerInterval: lowerBound...target,
      countsDown: true,
      showsHours: true
    )
  }
}

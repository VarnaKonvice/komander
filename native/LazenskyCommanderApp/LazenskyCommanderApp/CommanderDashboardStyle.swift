import LazenskyCommanderCore
import SwiftUI

// Source-of-Truth v3: saturated neon surfaces with crisp glow, no broad haze.
enum CommanderDesignTokens {
  enum Colors {
    static let background = Color(commanderHex: "#1542BA")
    static let backgroundDeep = Color(commanderHex: "#102884")
    static let panel = Color(commanderHex: "#1743A5")
    static let panelBright = Color(commanderHex: "#285DD7")
    static let panelStroke = Color(commanderHex: "#36DFFF")
    static let primaryPurple = Color(commanderHex: "#C77DFF")
    static let locationBlue = Color(commanderHex: "#65E5FF")
    static let mealGreen = Color(commanderHex: CommanderBrandAssets.Colors.mealGreen)
    static let amber = Color(commanderHex: "#FFC340")
    static let freeBlue = Color(commanderHex: CommanderBrandAssets.Colors.freeTimeCyan)
    static let procedureCyan = Color(commanderHex: CommanderBrandAssets.Colors.procedureCyan)
    static let urgentOrange = Color(commanderHex: "#FF8A3D")
    static let criticalRed = Color(commanderHex: "#FF5F59")
    static let therapyPink = Color(commanderHex: CommanderBrandAssets.Colors.therapyPink)
    static let procedureEndNeutral = Color(commanderHex: CommanderBrandAssets.Colors.procedureEndNeutral)
    static let textPrimary = Color(commanderHex: "#FFFFFF")
    static let textSecondary = Color(commanderHex: "#F2F6FF")
    // Supporting event information (location, departure) stays neutral white.
    // Event accent colors are reserved for the icon/title/border hierarchy.
    static let eventSupportingText = textPrimary
  }

  enum Spacing {
    static let tiny: CGFloat = 4
    static let metricTile: CGFloat = 1
    static let eventRows: CGFloat = 6
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let page: CGFloat = 14
    static let section: CGFloat = 20
    static let bottom: CGFloat = 24
    static let scrollTop: CGFloat = 12
    static let tabBarClearance: CGFloat = 92
  }

  enum Size {
    // Approved rule: one normal icon size everywhere.
    static let standardBadge: CGFloat = 50
    // Only the two highlighted cards in "Co mě teď čeká" may be larger.
    static let featuredBadge: CGFloat = 59
    static let primaryBadge: CGFloat = standardBadge
    static let sectionBadge: CGFloat = standardBadge
    static let rowMetricBadge: CGFloat = standardBadge
  }

  enum Radius {
    static let eventRow: CGFloat = 14
    static let card: CGFloat = 18
    static let header: CGFloat = 16
    static let inset: CGFloat = 12
  }

  enum CardSurface {
    case card
    case depthCard
    case depthInset
    case eventRow
    case header

    var radius: CGFloat {
      switch self {
      case .card, .depthCard: Radius.card
      case .depthInset: Radius.inset
      case .eventRow: Radius.eventRow
      case .header: Radius.header
      }
    }

    var isGlass: Bool { self == .header }

    var isDepth: Bool {
      switch self {
      case .depthCard, .depthInset: true
      default: false
      }
    }
  }

  enum Stroke {
    static let width: CGFloat = 1
    static let normal = Colors.panelStroke.opacity(0.55)
    static let strong = Colors.panelStroke.opacity(0.7)
  }

  enum Typography {
    case brand, screenTitle, subtitle, date, metric, label, section
    case eventTitle, location, time, departure, liveTitle, countdown

    var size: CGFloat {
      switch self {
      case .screenTitle: 37
      case .countdown: 27
      case .liveTitle: 25
      case .date: 23
      case .time: 21
      case .brand: 24
      case .section: 20
      case .eventTitle: 21
      case .metric: 21
      case .location: 18
      case .subtitle, .label, .departure: 17
      }
    }

    var weight: Font.Weight {
      switch self {
      case .brand, .location: .semibold
      case .subtitle, .label, .departure: .medium
      case .countdown: .heavy
      default: .bold
      }
    }

    var accessibilityScaleLimit: CGFloat {
      switch self {
      case .brand, .time: 1
      case .metric, .label: 1.25
      default: 1.6
      }
    }
  }

}

// One surface owner: parent cards hold blue light; children carry the category tint.
// A narrow halo supports the crisp stroke. No broad blur or stacked material layers.
private struct CommanderCardSurface: ViewModifier {
  var accent: Color?
  var surface: CommanderDesignTokens.CardSurface

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: surface.radius, style: .continuous)
    let tint = accent ?? CommanderDesignTokens.Colors.panelStroke

    // Keep the page/status-bar background unchanged. Cards add a crisp category tint.
    let baseColors: [Color] = {
      switch surface {
      case .header:
        return [
          Color(commanderHex: "#214B8A"),
          Color(commanderHex: "#172A59"),
          Color(commanderHex: "#0E1530")
        ]
      case .eventRow:
        return [
          Color(commanderHex: "#234E8E"),
          Color(commanderHex: "#192C5B"),
          Color(commanderHex: "#0E1530")
        ]
      case .depthInset:
        return [
          Color(commanderHex: "#204782"),
          Color(commanderHex: "#172952"),
          Color(commanderHex: "#0E1530")
        ]
      case .card, .depthCard:
        return [
          Color(commanderHex: "#1E447E"),
          Color(commanderHex: "#16274E"),
          Color(commanderHex: "#0E1530")
        ]
      }
    }()

    let crispWidth: CGFloat = 0.85

    content
      .background {
        shape.fill(
          LinearGradient(
            colors: baseColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .overlay {
          // Put category color into the actual card face. This is a flat tint,
          // not a haze layer: no white, blur, material or bloom.
          shape.fill(
            LinearGradient(
              colors: [
                tint.opacity(surface == .eventRow ? 0.08 : 0.05),
                tint.opacity(surface == .eventRow ? 0.035 : 0.025),
                tint.opacity(surface == .eventRow ? 0.012 : 0.010)
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
        }
      }
      .background {
        // Crisp neon only. No blur, material, white bloom or haze.
        ZStack {
          shape.stroke(tint.opacity(0.025), lineWidth: 1.6)
          shape.stroke(tint.opacity(0.075), lineWidth: 1.05)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
      .overlay {
        shape
          .strokeBorder(tint.opacity(0.34), lineWidth: crispWidth)
          .allowsHitTesting(false)
      }
  }
}

extension View {
  func commanderFont(_ style: CommanderDesignTokens.Typography) -> some View {
    modifier(CommanderFontModifier(style: style))
  }

  func commanderCard(
    accent: Color? = nil,
    surface: CommanderDesignTokens.CardSurface = .card
  ) -> some View {
    modifier(CommanderCardSurface(accent: accent, surface: surface))
  }
}

private struct CommanderFontModifier: ViewModifier {
  let style: CommanderDesignTokens.Typography
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

  func body(content: Content) -> some View {
    // Scale text locally for accessibility without scaling the grid or time-column geometry.
    let scale = dynamicTypeSize.isAccessibilitySize ? min(textScale, style.accessibilityScaleLimit) : 1
    content.font(.system(size: style.size * scale, weight: style.weight))
  }
}

struct CommanderGlassHeader: View {
  let tab: String
  var showsTabPill: Bool = false

  var body: some View {
    HStack(spacing: 8) {
      ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Color(commanderHex: "#26206C"), Color(commanderHex: "#0B377A")],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
        CommanderBrandAssets.circularMark
          .resizable()
          .scaledToFit()
          .padding(3)
      }
      .frame(width: CommanderDesignTokens.Size.standardBadge, height: CommanderDesignTokens.Size.standardBadge)
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(
            LinearGradient(
              colors: [CommanderDesignTokens.Colors.primaryPurple.opacity(0.68),
                       CommanderDesignTokens.Colors.procedureCyan.opacity(0.48),
                       Color.white.opacity(0.50)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 0.80
          )
      }
      .shadow(color: CommanderDesignTokens.Colors.procedureCyan.opacity(0.16), radius: 1.2)
      .accessibilityHidden(true)
      HStack(spacing: 0) {
        Text("Lázeňský ")
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        Text("Commander")
          .foregroundStyle(
            LinearGradient(
              colors: [CommanderDesignTokens.Colors.primaryPurple, Color(commanderHex: "#E77CFF")],
              startPoint: .leading, endPoint: .trailing
            )
          )
      }
      .commanderFont(.brand)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .layoutPriority(1)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .commanderCard(accent: CommanderDesignTokens.Colors.procedureCyan.opacity(0.85), surface: .header)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Lázeňský Commander")
  }
}

struct CommanderScheduleAuditStatusPill: View {
  let schedule: Schedule?

  private var status: (title: String, symbol: String, color: Color) {
    guard let schedule else {
      return ("Nenahrán", "questionmark.circle.fill", CommanderDesignTokens.Colors.textSecondary)
    }
    let report = CommanderScheduleAudit.run(schedule, policy: .petrSpaOperational)
    let errors = report.issues.filter { $0.severity == .error }.count
    let warnings = report.issues.filter { $0.severity == .warning }.count
    if errors > 0 {
      return (errors == 1 ? "1 chyba" : "\(errors) chyb", "exclamationmark.octagon.fill", CommanderDesignTokens.Colors.criticalRed)
    }
    if warnings > 0 {
      return (warnings == 1 ? "1 kontrola" : "\(warnings) kontroly", "exclamationmark.triangle.fill", CommanderDesignTokens.Colors.urgentOrange)
    }
    return ("Ověřeno", "checkmark.circle.fill", CommanderDesignTokens.Colors.mealGreen)
  }

  var body: some View {
    let status = status
    VStack(alignment: .trailing, spacing: 1) {
      Text("ROZPIS")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary.opacity(0.82))
      HStack(spacing: 4) {
        Image(systemName: status.symbol)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(status.color)
        Text(status.title)
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 7)
    .frame(width: 120)
    .background {
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .fill(
          LinearGradient(
            colors: [
              Color(commanderHex: "#234E8E"),
              Color(commanderHex: "#192C5B"),
              Color(commanderHex: "#0E1530")
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
    }
    .overlay {
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .strokeBorder(status.color.opacity(0.58), lineWidth: 0.85)
    }
    .shadow(color: status.color.opacity(0.12), radius: 1.0)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Rozpis, \(status.title)")
  }
}

struct CommanderPinnedTabHeader: View {
  let title: String
  let subtitle: String
  let schedule: Schedule?

  var body: some View {
    VStack(spacing: 8) {
      CommanderGlassHeader(tab: "", showsTabPill: false)

      HStack(alignment: .center, spacing: 10) {
        CommanderScreenHeading(title: title, subtitle: subtitle)
          .frame(maxWidth: .infinity, alignment: .leading)

        NavigationLink {
          CommanderScheduleAuditView(schedule: schedule)
        } label: {
          CommanderScheduleAuditStatusPill(schedule: schedule)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Otevře kontrolu rozpisu")
      }
    }
    .padding(.horizontal, CommanderDesignTokens.Spacing.page)
    .padding(.top, CommanderDesignTokens.Spacing.scrollTop)
    .padding(.bottom, 8)
  }
}

struct CommanderScreenHeading: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .commanderFont(.screenTitle)
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        .accessibilityAddTraits(.isHeader)
      Text(subtitle)
        .commanderFont(.subtitle)
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct CommanderTabScaffold<Content: View>: View {
  let tab: String
  let title: String
  let subtitle: String
  let schedule: Schedule?
  let content: Content

  init(
    tab: String,
    title: String,
    subtitle: String,
    schedule: Schedule?,
    @ViewBuilder content: () -> Content
  ) {
    self.tab = tab
    self.title = title
    self.subtitle = subtitle
    self.schedule = schedule
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      CommanderPinnedTabHeader(title: title, subtitle: subtitle, schedule: schedule)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          content
        }
        .padding(.horizontal, CommanderDesignTokens.Spacing.page)
        .padding(.bottom, CommanderDesignTokens.Spacing.bottom)
      }
      .scrollIndicators(.hidden)
      .clipped()
    }
    .background(CommanderDepthBackground().ignoresSafeArea())
    .toolbar(.hidden, for: .navigationBar)
  }
}

struct CommanderSectionCard<Content: View>: View {
  let title: String
  let symbol: String
  let accent: Color
  let content: Content

  init(
    title: String,
    symbol: String,
    accent: Color,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.symbol = symbol
    self.accent = accent
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.medium) {
      HStack(spacing: CommanderDesignTokens.Spacing.small) {
        CommanderSymbolBadge(
          symbol: symbol,
          color: accent,
          size: CommanderDesignTokens.Size.sectionBadge
        )

        Text(title)
          .commanderFont(.section)
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
      }
      content
    }
    .padding(CommanderDesignTokens.Spacing.medium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .commanderCard(accent: accent, surface: .depthCard)
  }
}

struct CommanderDetailRow: View {
  let title: String
  let value: String
  let symbol: String
  let accent: Color
  var valueColor = CommanderDesignTokens.Colors.textPrimary

  var body: some View {
    HStack(spacing: CommanderDesignTokens.Spacing.small) {
      CommanderSymbolBadge(
        symbol: symbol,
        color: accent,
        size: CommanderDesignTokens.Size.rowMetricBadge
      )

      VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.tiny) {
        Text(title)
          .commanderFont(.label)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        Text(value)
          .commanderFont(.metric)
          .foregroundStyle(valueColor)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(CommanderDesignTokens.Spacing.small)
    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    .commanderCard(accent: accent, surface: .depthInset)
    .accessibilityElement(children: .combine)
  }
}

struct CommanderProgressMeter: View {
  let title: String
  let value: String
  let fraction: Double
  let accent: Color

  var body: some View {
    VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.small) {
      HStack(alignment: .firstTextBaseline, spacing: CommanderDesignTokens.Spacing.small) {
        Text(title)
          .commanderFont(.label)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        Spacer(minLength: 0)
        Text(value)
          .commanderFont(.metric)
          .monospacedDigit()
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(CommanderDesignTokens.Colors.textSecondary.opacity(0.16))
          Capsule()
            .fill(
              LinearGradient(
                colors: [accent.opacity(0.78), accent, Color.white.opacity(0.72)],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            .shadow(color: accent.opacity(0.36), radius: 2)
        }
      }
      .frame(height: 12)
    }
    .accessibilityElement(children: .combine)
  }
}

struct CommanderNavigationRow: View {
  let title: String
  let subtitle: String
  let symbol: String
  let accent: Color
  var value: String? = nil

  var body: some View {
    HStack(spacing: CommanderDesignTokens.Spacing.small) {
      CommanderSymbolBadge(
        symbol: symbol,
        color: accent,
        size: CommanderDesignTokens.Size.rowMetricBadge
      )

      VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.tiny) {
        Text(title)
          .commanderFont(.metric)
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        Text(subtitle)
          .commanderFont(.label)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: CommanderDesignTokens.Spacing.small)
      if let value {
        Text(value)
          .commanderFont(.label)
          .foregroundStyle(accent)
          .monospacedDigit()
      }
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        .accessibilityHidden(true)
    }
    .padding(CommanderDesignTokens.Spacing.small)
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    .commanderCard(accent: accent, surface: .depthInset)
  }
}

enum CommanderEventAppearance {
  static func accent(for event: ScheduleEvent) -> Color {
    Color(commanderHex: CommanderVisualAssets.accent(for: event))
  }

  static func symbol(for event: ScheduleEvent) -> String {
    CommanderVisualAssets.symbol(for: event)
  }

}

struct CommanderSymbolBadge: View {
  let symbol: String
  let color: Color
  var size: CGFloat = CommanderDesignTokens.Size.standardBadge

  var body: some View {
    badgeGlyph
      .frame(width: size * 0.52, height: size * 0.52)
      .frame(width: size, height: size)
      .background(
        LinearGradient(
          colors: [color.opacity(0.13), Color(commanderHex: "#052D78")],
          startPoint: .topLeading, endPoint: .bottomTrailing
        ), in: Circle()
      )
      .overlay {
        Circle()
          .strokeBorder(color, lineWidth: 1.45)
          .allowsHitTesting(false)
      }
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private var badgeGlyph: some View {
    if symbol == "commander.heat.waves" {
      CommanderHeatWavesGlyph(color: color)
    } else {
      Image(systemName: symbol)
        .resizable()
        .scaledToFit()
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(color)
        .frame(width: size * 0.54, height: size * 0.54)
    }
  }
}

private struct CommanderHeatWavesGlyph: View {
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      let stroke = max(1.65, min(w, h) * 0.085)

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

struct CommanderQuoteCard: View {
  let text: String
  let symbol: String
  let accent: Color

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: symbol)
        .font(.system(size: 34, weight: .light))
        .foregroundStyle(accent)
        .accessibilityHidden(true)
      Text(text)
        .font(.system(size: 19, weight: .medium, design: .serif).italic())
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(18)
    .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
    .commanderCard(accent: CommanderDesignTokens.Colors.procedureCyan)
  }
}

enum CommanderDashboardPalette {
  static let background = CommanderDesignTokens.Colors.background
  static let backgroundDeep = CommanderDesignTokens.Colors.backgroundDeep
  static let backgroundLift = CommanderDesignTokens.Colors.panelBright
  static let surface = Color(commanderHex: CommanderBrandAssets.Colors.brandSurfaceDark)
  static let elevatedSurface = Color(red: 0.09, green: 0.12, blue: 0.24)
  static let glass = Color.white.opacity(0.105)
  static let glassStrong = Color.white.opacity(0.15)
  static let glassBorder = Color.white.opacity(0.14)
  static let commanderPurple = Color(commanderHex: CommanderBrandAssets.Colors.commanderPurple)
  static let commanderPurpleLight = CommanderDesignTokens.Colors.primaryPurple
  static let waterBlue = Color(commanderHex: CommanderBrandAssets.Colors.waterBlue)
  static let timeGold = Color(commanderHex: CommanderBrandAssets.Colors.timeGold)
  static let inProgress = Color(commanderHex: CommanderVisualAssets.colors?.state.inProgress ?? "#22C55E")
  static let alertRed = Color(red: 1.0, green: 0.34, blue: 0.39)
  static let neutral = Color.white.opacity(0.62)

  static var backgroundGradient: LinearGradient {
    LinearGradient(
      colors: [backgroundLift, background, backgroundDeep],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  static func eventAccent(for event: ScheduleEvent) -> Color {
    CommanderEventAppearance.accent(for: event)
  }

  static func eventKindLabel(for event: ScheduleEvent) -> String? {
    event.kind == .meal ? "Jídlo" : nil
  }
}

struct CommanderNeutralStateVisual: View {
  var accent = CommanderDashboardPalette.commanderPurple
  var size: CGFloat = 48

  var body: some View {
    CommanderBrandAssets.smallGlyph
      .resizable()
      .scaledToFit()
      .padding(size * 0.14)
      .frame(width: size, height: size)
      .background(CommanderDashboardPalette.glassStrong)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(accent.opacity(0.55), lineWidth: 1)
      }
      .accessibilityHidden(true)
  }
}

// Legacy iPhone views use the same approved badge, never a second PNG/icon palette.
struct CommanderEventIconView: View {
  let event: ScheduleEvent

  var body: some View {
    CommanderSymbolBadge(
      symbol: CommanderEventAppearance.symbol(for: event),
      color: CommanderEventAppearance.accent(for: event)
    )
  }
}

struct CommanderSectionTitle: View {
  let title: String
  var systemImage: String? = nil

  var body: some View {
    HStack(spacing: 8) {
      if let systemImage {
        Image(systemName: systemImage)
          .foregroundStyle(CommanderDashboardPalette.waterBlue)
          .accessibilityHidden(true)
      }
      Text(title)
        .font(.headline)
        .foregroundStyle(.white)
      Spacer(minLength: 0)
    }
  }
}

struct CommanderPageHeader: View {
  let title: String
  var subtitle: String? = nil
  var showsMark = true

  var body: some View {
    HStack(spacing: 12) {
      if showsMark {
        CommanderBrandAssets.circularMark
          .resizable()
          .scaledToFit()
          .frame(width: 44, height: 44)
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text("Lázeňský Commander")
          .font(.headline.weight(.bold))
          .foregroundStyle(.white)
        if let subtitle {
          Text(subtitle)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.72))
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
      Text(title)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(CommanderDashboardPalette.glassStrong)
        .clipShape(Capsule())
    }
    .padding(12)
    .background(.ultraThinMaterial)
    .background(CommanderDashboardPalette.glass)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(CommanderDashboardPalette.glassBorder, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}

struct CommanderScreenTitle: View {
  let title: String
  var subtitle: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.largeTitle.weight(.bold))
        .foregroundStyle(.white)
      if let subtitle {
        Text(subtitle)
          .font(.body.weight(.medium))
          .foregroundStyle(.white.opacity(0.72))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

struct CommanderInfoPanel<Content: View>: View {
  let title: String
  var systemImage: String? = nil
  let content: Content

  init(title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.systemImage = systemImage
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      CommanderSectionTitle(title: title, systemImage: systemImage)
      VStack(spacing: 0) {
        content
      }
      .background(CommanderDashboardPalette.glass)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(CommanderDashboardPalette.glassBorder.opacity(0.75), lineWidth: 1)
      }
    }
  }
}

struct CommanderInfoRow: View {
  let title: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.68))
      Spacer(minLength: 12)
      Text(value)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(.white.opacity(0.08))
        .frame(height: 1)
    }
  }
}

extension Color {
  init(commanderHex: String) {
    let value = commanderHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var rgb: UInt64 = 0
    Scanner(string: value).scanHexInt64(&rgb)
    self.init(
      red: Double((rgb >> 16) & 0xff) / 255,
      green: Double((rgb >> 8) & 0xff) / 255,
      blue: Double(rgb & 0xff) / 255
    )
  }
}

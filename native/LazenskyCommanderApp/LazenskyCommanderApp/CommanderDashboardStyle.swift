import LazenskyCommanderCore
import SwiftUI

// Source-of-Truth v2 shared by every main application tab.
enum CommanderDesignTokens {
  enum Colors {
    static let background = Color(commanderHex: "#0E1530")
    static let panel = Color(commanderHex: "#141C3E")
    static let panelStroke = Color(commanderHex: "#4E68D8")
    static let primaryPurple = Color(commanderHex: "#A873FF")
    static let locationBlue = Color(commanderHex: "#4CC8FF")
    static let mealGreen = Color(commanderHex: "#50B863")
    static let amber = Color(commanderHex: "#FFB54A")
    static let freeBlue = Color(commanderHex: "#2EA6FF")
    static let procedureCyan = Color(commanderHex: "#2ED4FF")
    static let urgentOrange = Color(commanderHex: "#FF8A00")
    static let criticalRed = Color(commanderHex: "#F45A4A")
    static let textPrimary = Color(commanderHex: "#FFFFFF")
    static let textSecondary = Color(commanderHex: "#A6B0D6")
  }

  enum Spacing {
    static let tiny: CGFloat = 4
    static let metricTile: CGFloat = 1
    static let eventRows: CGFloat = 6
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let page: CGFloat = 16
    static let section: CGFloat = 20
    static let bottom: CGFloat = 28
  }

  enum Size {
    static let sectionBadge: CGFloat = 40
    static let rowMetricBadge: CGFloat = 30
  }

  enum Radius {
    static let eventRow: CGFloat = 14
    static let card: CGFloat = 18
    static let header: CGFloat = 22
    static let inset: CGFloat = 12
  }

  enum CardSurface {
    case card
    case eventRow
    case header

    var radius: CGFloat {
      switch self {
      case .card: Radius.card
      case .eventRow: Radius.eventRow
      case .header: Radius.header
      }
    }

    var isGlass: Bool { self == .header }
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
      case .screenTitle: 34
      case .countdown: 24
      case .liveTitle: 22
      case .date: 20
      case .time: 18
      case .brand: 20
      case .section, .eventTitle: 17
      case .metric: 16
      case .location: 16
      case .subtitle, .label, .departure: 14
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

  static let cardBackground = LinearGradient(
    colors: [Colors.panel, Colors.background], startPoint: .topLeading, endPoint: .bottomTrailing
  )
  static let glassHighlight = LinearGradient(
    colors: [Colors.panelStroke.opacity(0.2), Colors.panelStroke.opacity(0.02)],
    startPoint: .topLeading, endPoint: .bottomTrailing
  )
}

private struct CommanderCardSurface: ViewModifier {
  var accent: Color?
  var surface: CommanderDesignTokens.CardSurface

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: surface.radius)
    content
      .background {
        ZStack {
          if surface.isGlass {
            shape.fill(.ultraThinMaterial)
              .overlay(CommanderDesignTokens.Colors.panel.opacity(0.8))
          } else {
            CommanderDesignTokens.cardBackground
          }
          CommanderDesignTokens.glassHighlight
        }
      }
      .background(CommanderDesignTokens.Colors.background)
      .clipShape(shape)
      .overlay {
        shape.strokeBorder(
          accent?.opacity(0.55) ?? CommanderDesignTokens.Stroke.normal,
          lineWidth: CommanderDesignTokens.Stroke.width
        )
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

  var body: some View {
    HStack(spacing: 6) {
      logo
      Text("Lázeňský \(Text("Commander").foregroundStyle(CommanderDesignTokens.Colors.primaryPurple))")
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        .commanderFont(.brand)
        .lineLimit(1)
        .minimumScaleFactor(0.94)
        .layoutPriority(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      tabPill
    }
    .padding(.horizontal, 6)
    .padding(.vertical, CommanderDesignTokens.Spacing.tiny)
    .commanderCard(surface: .header)
    .accessibilityElement(children: .combine)
  }

  private var logo: some View {
    CommanderBrandAssets.circularMark
      .resizable()
      .scaledToFit()
      .frame(width: 44, height: 44)
      .accessibilityHidden(true)
  }

  private var tabPill: some View {
    Text(tab)
      .font(.system(size: 14, weight: .medium))
      .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
      .fixedSize()
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(CommanderDesignTokens.Colors.panel, in: Capsule())
      .overlay { Capsule().strokeBorder(CommanderDesignTokens.Stroke.strong, lineWidth: 1) }
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
  let content: Content

  init(
    tab: String,
    title: String,
    subtitle: String,
    @ViewBuilder content: () -> Content
  ) {
    self.tab = tab
    self.title = title
    self.subtitle = subtitle
    self.content = content()
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.medium) {
        CommanderGlassHeader(tab: tab)
        CommanderScreenHeading(title: title, subtitle: subtitle)
        content
      }
      .padding(.horizontal, CommanderDesignTokens.Spacing.page)
      .padding(.top, CommanderDesignTokens.Spacing.tiny)
      .padding(.bottom, CommanderDesignTokens.Spacing.bottom)
    }
    .scrollIndicators(.hidden)
    .background(CommanderDesignTokens.Colors.background.ignoresSafeArea())
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
    .commanderCard()
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
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(CommanderDesignTokens.Colors.panel.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset))
    .overlay {
      RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset)
        .strokeBorder(CommanderDesignTokens.Stroke.normal, lineWidth: CommanderDesignTokens.Stroke.width)
    }
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
            .fill(accent)
            .frame(width: proxy.size.width * min(max(fraction, 0), 1))
        }
      }
      .frame(height: 8)
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
    .background(CommanderDesignTokens.Colors.panel.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset))
    .overlay {
      RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset)
        .strokeBorder(CommanderDesignTokens.Stroke.normal, lineWidth: CommanderDesignTokens.Stroke.width)
    }
  }
}

enum CommanderEventAppearance {
  static func accent(for event: ScheduleEvent) -> Color {
    if event.kind == .meal { return CommanderDesignTokens.Colors.mealGreen }
    switch CommanderVisualAssets.icon(for: event)?.key {
    case "iodobrom", "peat_wrap": return CommanderDesignTokens.Colors.amber
    case "electro_therapy", "hydrojet", "whirlpool", "pool":
      return CommanderDesignTokens.Colors.procedureCyan
    default: return CommanderDesignTokens.Colors.primaryPurple
    }
  }

  static func symbol(for event: ScheduleEvent) -> String {
    if event.kind == .meal { return "fork.knife" }
    switch CommanderVisualAssets.icon(for: event)?.key {
    case "electro_therapy": return "atom"
    case "iodobrom", "whirlpool": return "bathtub.fill"
    case "massage", "peat_wrap": return "figure.mind.and.body"
    case "pool", "hydrojet": return "water.waves"
    case "individual_rehab", "imoove": return "figure.walk"
    default: return "calendar"
    }
  }
}

struct CommanderSymbolBadge: View {
  let symbol: String
  let color: Color
  var size: CGFloat = 36

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.5, weight: .medium))
      .foregroundStyle(color)
      .frame(width: size, height: size)
      .background(color.opacity(0.14), in: Circle())
      .overlay { Circle().strokeBorder(color.opacity(0.35), lineWidth: 1) }
      .accessibilityHidden(true)
  }
}

enum CommanderDashboardPalette {
  static let background = Color(red: 0.055, green: 0.11, blue: 0.235)
  static let backgroundDeep = Color(red: 0.025, green: 0.035, blue: 0.13)
  static let backgroundLift = Color(red: 0.08, green: 0.18, blue: 0.34)
  static let surface = Color(commanderHex: CommanderBrandAssets.Colors.brandSurfaceDark)
  static let elevatedSurface = Color(red: 0.09, green: 0.12, blue: 0.24)
  static let glass = Color.white.opacity(0.105)
  static let glassStrong = Color.white.opacity(0.15)
  static let glassBorder = Color.white.opacity(0.22)
  static let commanderPurple = Color(commanderHex: CommanderBrandAssets.Colors.commanderPurple)
  static let commanderPurpleLight = Color(commanderHex: CommanderBrandAssets.Colors.commanderPurpleLight)
  static let waterBlue = Color(commanderHex: CommanderBrandAssets.Colors.waterBlue)
  static let timeGold = Color(commanderHex: CommanderBrandAssets.Colors.timeGold)
  static let inProgress = Color(commanderHex: CommanderVisualAssets.colors?.state.inProgress ?? "#22C55E")
  static let mealGreen = Color(red: 0.32, green: 0.88, blue: 0.42)
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
    if event.kind == .meal { return mealGreen }
    return Color(commanderHex: CommanderVisualAssets.accent(for: CommanderVisualAssets.icon(for: event)))
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

struct CommanderEventIconView: View {
  let event: ScheduleEvent
  var size: CGFloat = 52

  private var icon: CommanderIconMap.Icon? {
    CommanderVisualAssets.icon(for: event)
  }

  private var accent: Color {
    CommanderDashboardPalette.eventAccent(for: event)
  }

  @ViewBuilder
  var body: some View {
    if let icon, let image = CommanderVisualAssets.image(for: icon.key) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(accent.opacity(0.9), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
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

import LazenskyCommanderCore
import SwiftUI

struct CommanderInfoView: View {
  @ObservedObject var model: CommanderViewModel

  private let labels = [
    "spa": "Lázně", "dateFrom": "Pobyt od", "dateTo": "Pobyt do",
    "room": "Pokoj", "doctor": "Lékař", "diagnosis": "Diagnóza", "mealShift": "Stravovací směna"
  ]

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      CommanderTabScaffold(
        tab: "Info",
        title: "Info",
        subtitle: "Informace o vašem pobytu",
        schedule: model.latestSchedule
      ) {
        if let schedule = model.latestSchedule {
          let fields = CommanderInfoPresentation.fields(stay: schedule.stay)
          if fields.isEmpty {
            unavailableCard("Informace o pobytu nejsou uvedeny")
          } else {
            CommanderSectionCard(
              title: "Údaje o pobytu",
              symbol: "info.circle.fill",
              accent: CommanderDesignTokens.Colors.locationBlue
            ) {
              if let period = CommanderStayPresentation.period(stay: schedule.stay, now: context.date) {
                stayDayRow(period)
              }
              VStack(spacing: CommanderDesignTokens.Spacing.eventRows) {
                ForEach(fields, id: \.key) { field in
                  CommanderDetailRow(
                    title: labels[field.key] ?? field.key,
                    value: field.value,
                    symbol: symbol(for: field.key),
                    accent: accent(for: field.key)
                  )
                }
              }
            }

          }
        } else {
          unavailableCard("Rozpis ještě není načten")
        }

        helpCard
      }
    }
  }

  private var helpCard: some View {
    CommanderSectionCard(
      title: "Pomoc a podmínky",
      symbol: "questionmark.circle.fill",
      accent: CommanderDesignTokens.Colors.primaryPurple
    ) {
      VStack(spacing: CommanderDesignTokens.Spacing.eventRows) {
        NavigationLink {
          CommanderUserGuideView()
        } label: {
          helpRow(
            title: "Jak Commander funguje",
            subtitle: "Krátký návod k rozpisu, alarmům a kalendáři",
            symbol: "book.fill"
          )
        }
        .buttonStyle(.plain)

        NavigationLink {
          CommanderTermsView()
        } label: {
          helpRow(
            title: "Podmínky používání",
            subtitle: "Základní pravidla služby",
            symbol: "doc.text.fill"
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func helpRow(title: String, subtitle: String, symbol: String) -> some View {
    HStack(spacing: CommanderDesignTokens.Spacing.medium) {
      CommanderSymbolBadge(
        symbol: symbol,
        color: CommanderDesignTokens.Colors.primaryPurple,
        size: CommanderDesignTokens.Size.sectionBadge
      )
      VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.tiny) {
        Text(title)
          .commanderFont(.eventTitle)
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        Text(subtitle)
          .font(.footnote)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      }
      Spacer(minLength: CommanderDesignTokens.Spacing.small)
      Image(systemName: "chevron.right")
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
    }
    .padding(CommanderDesignTokens.Spacing.small)
    .commanderCard(accent: CommanderDesignTokens.Colors.primaryPurple, surface: .depthInset)
  }

  @ViewBuilder
  private func stayDayRow(_ period: CommanderStayPeriod) -> some View {
    switch period.phase {
    case .active:
      if let currentDay = period.currentDay {
        CommanderDetailRow(
          title: "Aktuální den pobytu",
          value: "\(currentDay) / \(period.totalDays)",
          symbol: "calendar.circle.fill",
          accent: CommanderDesignTokens.Colors.locationBlue
        )
      }
    case .upcoming:
      CommanderDetailRow(
        title: "Stav pobytu",
        value: "Pobyt ještě nezačal",
        symbol: "calendar.badge.clock",
        accent: CommanderDesignTokens.Colors.freeBlue
      )
    case .finished:
      CommanderDetailRow(
        title: "Stav pobytu",
        value: "Pobyt skončil",
        symbol: "calendar.badge.checkmark",
        accent: CommanderDesignTokens.Colors.textSecondary
      )
    }
  }

  private func symbol(for key: String) -> String {
    switch key {
    case "spa": return "building.2.fill"
    case "dateFrom": return "calendar.badge.plus"
    case "dateTo": return "calendar.badge.checkmark"
    case "room": return "bed.double.fill"
    case "doctor": return "stethoscope"
    case "diagnosis": return "cross.case.fill"
    case "mealShift": return "fork.knife"
    default: return "info.circle"
    }
  }

  private func accent(for key: String) -> Color {
    switch key {
    case "diagnosis":
      return CommanderDesignTokens.Colors.primaryPurple
    case "spa", "dateFrom", "dateTo", "room", "doctor", "mealShift":
      return CommanderDesignTokens.Colors.locationBlue
    default:
      return CommanderDesignTokens.Colors.textSecondary
    }
  }

  private func unavailableCard(_ message: String) -> some View {
    HStack(spacing: CommanderDesignTokens.Spacing.medium) {
      CommanderSymbolBadge(
        symbol: "info.circle",
        color: CommanderDesignTokens.Colors.textSecondary,
        size: CommanderDesignTokens.Size.sectionBadge
      )
      Text(message)
        .commanderFont(.eventTitle)
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
    }
    .padding(CommanderDesignTokens.Spacing.page)
    .frame(maxWidth: .infinity, alignment: .leading)
    .commanderCard(accent: CommanderDesignTokens.Colors.locationBlue, surface: .depthCard)
  }
}


private struct CommanderUserGuideView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.section) {
        CommanderSectionCard(
          title: "Základní použití",
          symbol: "book.fill",
          accent: CommanderDesignTokens.Colors.locationBlue
        ) {
          VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.medium) {
            guideStep("1", "Přijměte rozpis", "Commander načte váš konkrétní pobyt a uloží poslední platnou verzi i pro použití bez internetu.")
            guideStep("2", "Povolte alarmy", "Bez oprávnění k alarmům vás aplikace nemůže spolehlivě upozornit, kdy máte vyrazit.")
            guideStep("3", "Používejte Dnes, Týden a Pobyt", "Dnes ukazuje nejbližší události, Týden další dny a Pobyt celý časový plán.")
            guideStep("4", "Nastavte předstih", "Alarm může zazvonit před začátkem procedury tak, abyste měli čas dojít na místo.")
            guideStep("5", "Přijímejte změny", "Novější verze stejného rozpisu nahradí starší a Commander přepočítá alarmy.")
            guideStep("6", "Kalendář je volitelný", "Celý pobyt lze exportovat do kalendářového souboru .ics.")
          }
        }

        CommanderSectionCard(
          title: "Důležité",
          symbol: "exclamationmark.triangle.fill",
          accent: CommanderDesignTokens.Colors.urgentOrange
        ) {
          Text("Commander je organizační pomůcka. Pokud se údaj v aplikaci liší od aktuálního pokynu lázní nebo zdravotnického personálu, řiďte se aktuálním oficiálním pokynem.")
            .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        }
      }
      .padding(.horizontal, CommanderDesignTokens.Spacing.page)
      .padding(.vertical, CommanderDesignTokens.Spacing.medium)
    }
    .background(CommanderDepthBackground().ignoresSafeArea())
    .navigationTitle("Jak Commander funguje")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func guideStep(_ number: String, _ title: String, _ text: String) -> some View {
    HStack(alignment: .top, spacing: CommanderDesignTokens.Spacing.medium) {
      Text(number)
        .font(.subheadline.bold())
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        .frame(width: 30, height: 30)
        .background(CommanderDesignTokens.Colors.locationBlue.opacity(0.22), in: Circle())
      VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.tiny) {
        Text(title)
          .font(.subheadline.bold())
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        Text(text)
          .font(.footnote)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      }
    }
  }
}

private struct CommanderTermsView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.section) {
        termsCard(
          "Služba",
          "Lázeňský Commander zobrazuje časový rozpis pobytu, počítá čas odchodu a upozorňuje na události. Nenahrazuje zdravotnickou dokumentaci ani aktuální pokyny lázeňského zařízení."
        )
        termsCard(
          "Rozpis",
          "Rozpis může pocházet z partnerských lázní nebo z podkladu dodaného klientem. Při rozporu má přednost aktuální pokyn lázeňského zařízení."
        )
        termsCard(
          "Aktivace a cena",
          "Aktivace se vztahuje ke konkrétnímu pobytu. U placené aktivace musí být cena zobrazena před potvrzením. Cena se odvíjí od počtu dní, které při první aktivaci zbývají do konce pobytu."
        )
        termsCard(
          "Alarmy a připojení",
          "Alarmy vyžadují podporované zařízení a potřebná oprávnění. Poslední platný rozpis zůstává uložený offline, nové změny mohou vyžadovat připojení."
        )
        termsCard(
          "Soukromí",
          "Commander má používat pouze údaje potřebné pro doručení a provoz konkrétního pobytu. Podrobné zásady ochrany soukromí a identifikační údaje provozovatele budou doplněny před veřejným vydáním."
        )
      }
      .padding(.horizontal, CommanderDesignTokens.Spacing.page)
      .padding(.vertical, CommanderDesignTokens.Spacing.medium)
    }
    .background(CommanderDepthBackground().ignoresSafeArea())
    .navigationTitle("Podmínky používání")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func termsCard(_ title: String, _ text: String) -> some View {
    CommanderSectionCard(
      title: title,
      symbol: "doc.text.fill",
      accent: CommanderDesignTokens.Colors.primaryPurple
    ) {
      Text(text)
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
    }
  }
}

import LazenskyCommanderCore
import SwiftUI

struct CommanderDashboardView: View {
  @ObservedObject var model: CommanderViewModel

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      CommanderDashboardContent(
        schedule: model.latestSchedule,
        now: context.date,
        isSynchronizing: model.isSynchronizing,
        synchronize: model.synchronize
      )
    }
    .background(CommanderDashboardPalette.background.ignoresSafeArea())
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(CommanderDashboardPalette.background, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          CommanderSystemStatusView(model: model)
        } label: {
          Image(systemName: "gearshape")
            .overlay(alignment: .topTrailing) {
              if model.requiresUserAction {
                Circle()
                  .fill(.red)
                  .frame(width: 7, height: 7)
                  .offset(x: 2, y: -2)
              }
            }
        }
        .accessibilityLabel("Stav systému")
      }
    }
  }
}

struct CommanderDashboardContent: View {
  let schedule: Schedule?
  let now: Date
  let isSynchronizing: Bool
  let synchronize: () -> Void

  private var presentation: CommanderDashboardPresentation {
    CommanderDashboardPresentation.make(schedule: schedule, now: now)
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        CommanderDashboardHeader(now: now)

        if presentation.mode == .unsynchronized {
          CommanderUnsynchronizedView(
            isSynchronizing: isSynchronizing,
            synchronize: synchronize
          )
        } else {
          CommanderHeroView(presentation: presentation)
          if let next = presentation.nextEvent {
            CommanderNextEventView(item: next, now: now)
          }
          if !presentation.meals.isEmpty {
            CommanderMealSummaryView(meals: presentation.meals)
          }
          if !presentation.timeline.isEmpty {
            CommanderDayTimelineView(items: presentation.timeline)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 28)
    }
    .scrollIndicators(.hidden)
  }
}

private struct CommanderDashboardHeader: View {
  let now: Date

  var body: some View {
    HStack(spacing: 12) {
      CommanderBrandAssets.circularMark
        .resizable()
        .scaledToFit()
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text("Lázeňský")
          .font(.title3.bold())
          .foregroundStyle(.white.opacity(0.96))
        Text("Commander")
          .font(.title3.bold())
          .foregroundStyle(
            LinearGradient(
              colors: [
                CommanderDashboardPalette.commanderPurpleLight,
                CommanderDashboardPalette.commanderPurple
              ],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
        Text(
          now.formatted(
            .dateTime
              .weekday(.wide)
              .day()
              .month(.wide)
              .locale(Locale(identifier: "cs_CZ"))
          )
        )
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.66))
      }
      Spacer(minLength: 0)
    }
    .padding(.top, 4)
    .accessibilityElement(children: .combine)
  }
}

private struct CommanderUnsynchronizedView: View {
  let isSynchronizing: Bool
  let synchronize: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        CommanderNeutralStateVisual(size: 44)
        Text("Rozpis ještě není načten")
          .font(.title3.weight(.semibold))
          .foregroundStyle(.white)
      }

      Button(action: synchronize) {
        HStack {
          Label(
            isSynchronizing ? "Synchronizuji…" : "Synchronizovat rozpis",
            systemImage: "arrow.triangle.2.circlepath"
          )
          Spacer()
          if isSynchronizing {
            ProgressView()
              .tint(.white)
          }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .frame(minHeight: 44)
        .padding(.horizontal, 14)
        .background(CommanderDashboardPalette.commanderPurple)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)
      .disabled(isSynchronizing)
    }
    .padding(18)
    .background(CommanderDashboardPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}

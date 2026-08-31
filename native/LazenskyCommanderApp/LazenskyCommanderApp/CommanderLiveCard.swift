import LazenskyCommanderCore
import SwiftUI

struct CommanderLiveCard: View {
  let schedule: Schedule?
  let now: Date

  private var presentation: CommanderDashboardPresentation {
    CommanderDashboardPresentation.make(schedule: schedule, now: now)
  }

  var body: some View {
    CommanderHeroView(presentation: presentation)
  }
}

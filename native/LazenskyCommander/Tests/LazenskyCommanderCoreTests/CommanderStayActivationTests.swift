import Foundation
import Testing
@testable import LazenskyCommanderCore

@Suite("CommanderStayActivation")
struct CommanderStayActivationTests {
  @Test func spaContractAndAppleIAPBothGrantSameAccess() throws {
    let policy = CommanderStayAccessPolicy(requiresActivation: true)

    let spa = try policy.resolve(active(source: .spaContract))
    let apple = try policy.resolve(active(source: .appleIAP))

    #expect(spa == .active(.spaContract))
    #expect(apple == .active(.appleIAP))
    #expect(spa.permitsScheduleUse)
    #expect(apple.permitsScheduleUse)
  }

  @Test func futureWebChannelUsesSameAccessContract() throws {
    let resolution = try CommanderStayAccessPolicy(requiresActivation: true)
      .resolve(active(source: .web))

    #expect(resolution == .active(.web))
    #expect(resolution.permitsScheduleUse)
  }

  @Test func paymentRequiredDoesNotPermitScheduleUse() throws {
    let activation = CommanderStayActivation(
      activationID: "a-1",
      stayID: "stay-1",
      state: .paymentRequired,
      updatedAt: "2026-10-31T21:00:00+01:00"
    )

    let resolution = try CommanderStayAccessPolicy(requiresActivation: true).resolve(activation)
    #expect(resolution == .paymentRequired)
    #expect(!resolution.permitsScheduleUse)
    #expect(resolution.requiresCustomerPayment)
  }

  @Test func missingActivationCanBeRolledOutWithoutBreakingPilot() throws {
    #expect(
      try CommanderStayAccessPolicy(requiresActivation: false).resolve(nil) == .legacyUnmanaged
    )
    #expect(
      try CommanderStayAccessPolicy(requiresActivation: true).resolve(nil) == .activationMissing
    )
  }

  @Test func activeActivationRequiresSource() {
    let activation = CommanderStayActivation(
      activationID: "a-1",
      stayID: "stay-1",
      state: .active,
      updatedAt: "2026-10-31T21:00:00+01:00"
    )

    #expect(throws: CommanderStayActivationValidationError.activeWithoutSource) {
      try activation.validate()
    }
  }

  @Test func invalidValidityRangeIsRejected() {
    let activation = CommanderStayActivation(
      activationID: "a-1",
      stayID: "stay-1",
      state: .active,
      source: .spaContract,
      updatedAt: "2026-10-31T21:00:00+01:00",
      validFrom: "2026-11-10T00:00:00+01:00",
      validUntil: "2026-11-01T00:00:00+01:00"
    )

    #expect(throws: CommanderStayActivationValidationError.invalidValidityRange) {
      try activation.validate()
    }
  }

  @Test func contractRoundTripsThroughJSON() throws {
    let activation = active(source: .appleIAP)
    let data = try JSONEncoder().encode(activation)
    let decoded = try JSONDecoder().decode(CommanderStayActivation.self, from: data)

    #expect(decoded == activation)
    try decoded.validate()
  }

  private func active(source: CommanderStayActivationSource) -> CommanderStayActivation {
    CommanderStayActivation(
      activationID: "activation-001",
      stayID: "stay-001",
      state: .active,
      source: source,
      updatedAt: "2026-10-31T21:00:00+01:00",
      validFrom: "2026-10-31T00:00:00+01:00",
      validUntil: "2026-11-30T23:59:59+01:00"
    )
  }
}

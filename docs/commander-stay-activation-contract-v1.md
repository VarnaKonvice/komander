# Commander stay activation contract v1

## Decision

Commander activation is stay-level, not app-install-level.

The iOS app does not decide whether money was collected correctly. The backend is authoritative and returns a stay activation record. The app only evaluates whether that record grants access.

## Activation sources

- spaContract — a partner spa/provider covers the stay under a B2B contract.
- appleIAP — a direct customer purchases the stay activation using Apple In-App Purchase.
- web — reserved for a future eligible web-distribution/payment channel.
- complimentary — administrative/test grant.

All paid sources produce the same application capability once the state is active.

## States

- processing — source material/schedule is still being prepared.
- paymentRequired — direct-customer schedule is ready but not yet purchased.
- active — Commander may operate the stay normally.
- expired — the entitlement ended normally.
- revoked — the entitlement was explicitly withdrawn.

An active record must identify its activation source.

## Rollout

The current pilot predates the activation backend. CommanderStayAccessPolicy with requiresActivation=false therefore treats a missing activation record as legacyUnmanaged and preserves current behavior.

When the backend and StoreKit flow are ready, production can switch to requiresActivation=true. Missing activation then resolves to activationMissing and does not grant schedule use.

This keeps the payment channel replaceable without changing schedule, alarm, spa-profile, or presentation contracts.

## Commercial direction — 2026-10-31

Initial public distribution: App Store, direct-customer activation via Apple IAP.

Partner spas: B2B contractual activation through spaContract.

Future: if Commander qualifies for EU web distribution, the backend may issue web activations. The iOS schedule/alarm runtime must not need a payment-specific rewrite.

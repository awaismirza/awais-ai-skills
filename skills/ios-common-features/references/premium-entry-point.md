# Premium Entry Point: Upgrade Pill + Paywall Sheet

Reference for Feature 6. See `templates/PremiumUpgradeBadge.swift` and `templates/PaywallSheet.swift` for the ready-to-use components.

## Why this exists alongside Feature 4's triggered paywall

Feature 4 (Smart Usage-Based Paywall) is *interruptive* — the app decides, based on usage frequency, when to show it, rate-limited to once per 14 days. That's good for conversion but bad for the user who decides on their own, on day one, that they want to upgrade — they'd have to wait for the app to notice them.

The upgrade pill is *self-serve* — always available, never interruptive, never rate-limited. A free user can tap it the moment they're convinced, instead of waiting to be asked. Both patterns should drive the exact same `PaywallSheet`, via one shared `isPaywallPresented` flag on the entitlement manager, so the sheet itself only needs to be built once.

## Placement rules

- Top-right of the primary/home screen's header. If the app has multiple top-level tabs, keep it visible from as many of them as make sense — at minimum the tab the user lands on most.
- Never inside a scroll view where it can scroll out of view — it belongs in the fixed header/toolbar area.
- Outline style (1pt border, accent-colored label, no solid fill) — a solid-filled button in the header competes visually with the screen's actual primary action (e.g. "Start Fast", "New alarm"). Reserve solid fill for the sheet's own CTA.

## Visibility

Gate on the **live** entitlement check, not a cached tier flag alone. A user who just purchased should never see the pill flash back into view after a stale-cache read — reconcile against `Transaction.currentEntitlements` (or your non-consumable's purchase record) before deciding to render it, the same way the rest of the app's premium gating already does.

## Paywall sheet anatomy

In order, top to bottom:

1. Dismiss `✕`, top-right of the sheet.
2. Small-caps product-name eyebrow label, accent color (e.g. `VOICEALARM PRO`).
3. Bold, benefit-led headline — states the *outcome* ("Keep every routine on track with unlimited alarms"), not a feature list. Two lines max.
4. A card containing 2–4 checkmarked feature bullets. Keep each bullet to one short line.
5. Price card(s) — see below.
6. Primary CTA, solid accent fill.
7. `"Not Now"` — dismiss only. Never guilt-trip copy ("Are you sure you don't want to save time?").
8. `"Restore Purchases"` — always present, even for a one-time-purchase model (a user who reinstalled needs it just as much as a lapsed-subscription user does).
9. One-line legal fine print stating the actual terms plainly — e.g. `"Voice Alarm Pro is a one-time purchase of $9.99. It never expires and never renews."` for a lifetime unlock, or the standard auto-renewing-subscription disclosure for a subscription.

## Monetization model: detect first, ask once, never assume

Two patterns are both legitimate and both appear in real shipped apps:

| | Auto-renewable subscription | One-time non-consumable |
|---|---|---|
| StoreKit product type | `.autoRenewable` | `.nonConsumable` |
| Entitlement source | `Transaction.currentEntitlements`, reconciled continuously | "Was this ever purchased and not revoked" |
| Price cards in the sheet | 2+ selectable tiers (monthly/yearly) | Exactly 1, pre-selected |
| Fine print | Renewal terms, cancel-anytime disclosure | "Never expires, never renews" |
| Trial support | Often yes (free trial before first charge) | No — it's a single purchase |

**Before writing any new code**, check whether the app already has an entitlement/premium manager and what product type it uses (`grep` for `Product.products`, `.autoRenewable`, `.nonConsumable`, `SubscriptionInfo`, an existing `PremiumManager`/`EntitlementManager` class). If one exists, match it — don't introduce a second monetization model into an app that already picked one.

If neither exists yet, **ask the developer once** which model this app uses, and persist that choice (a status/config file, or just the resulting code itself) so future runs don't re-ask. This is a real App Store Connect product-configuration decision — the app's actual in-app-purchase products were set up as one type or the other — not something a later code change can silently flip.

## Common mistake this reference exists to prevent

Copying `PaywallTriggerManager.swift` (Feature 4's usage-triggered modal, which this repo's original version assumed a subscription) verbatim into an app that's actually configured for a one-time lifetime unlock. The result compiles and looks fine until a real purchase attempt fails against App Store Connect because the product type doesn't match what the code expects.

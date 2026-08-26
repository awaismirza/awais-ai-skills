# Optional Permissions & the Permission Nudge Banner

Reference for Feature 7. See `templates/OptionalPermissionManager.swift` and `templates/PermissionNudgeBanner.swift`.

## The one rule everything else follows

**Every OS permission is optional.** Camera, microphone, location, notifications — none of them ever gates whether a feature *exists*. A denied permission degrades a feature to a working fallback; it never disables a whole app section or blanks a screen.

Concretely:

| Permission | Feature it usually gates | Working fallback when denied |
|---|---|---|
| Camera | Receipt/document scanning | "Choose from Library" stays available |
| Microphone | Voice input/dictation | Manual text entry stays available |
| Location (When-In-Use) | Auto-tracking a trip/shift | Manual entry of distance/duration stays available |
| Notifications | Reminders, scheduled alarms | The reminder still gets created and shown in-app; it just won't push |

Design and build the fallback path **before** writing the permission-request code — if you can't describe what the denied state looks like, the feature isn't ready to gate on a permission at all.

## When to ask

Ask at the exact point the user takes an action that needs the permission — tapping "Scan Receipt", tapping "Start Tracking", scheduling their first alarm. Never in a batch on cold launch. A batch of upfront prompts reads as the app being presumptuous, and measurably lowers grant rates versus asking in context, one at a time, when the need is self-evident.

## The permission nudge banner

When a user lands on a screen whose primary action needs a permission that's currently denied or not-determined, show a **full-width banner near the top of that screen** — not a corner icon, not a tab badge. The real-world reference pattern:

> 🔕 Notifications are off, so alarms can't arrive. ›

Structure:
- Leading SF Symbol matching the specific permission (`bell.slash.fill`, `location.slash.fill`, `mic.slash.fill`, a slashed camera glyph), in a muted warning tint (not full-saturation red/alert — this is informational, not an error state).
- One plain-language line stating *why* the app needs it, phrased as a consequence the user will notice ("so alarms can't arrive"), not a permission-system term ("notification authorization required").
- Trailing chevron.
- Tapping it: if the permission has never been requested (`.notDetermined`), trigger the native OS prompt directly. If it's already been explicitly denied, the OS prompt is a silent no-op — deep-link to Settings instead via `UIApplication.openSettingsURLString`.

## Don't nag

Once a permission has been explicitly declined in the current session, don't re-show the banner for it again that session. One nudge is a nudge; a banner that reappears every time the user revisits the screen reads as nagging and trains users to ignore your banners generally, including the ones that matter.

## Audit signal

If you find a feature that's `.disabled()`, hidden, or replaced with an empty state purely because a permission is `.denied` — with no working alternative underneath — that's the specific anti-pattern this feature exists to catch.

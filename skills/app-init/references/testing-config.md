# Persisted Config & Verification Mode

`app-init` stores its decisions in one file in the target repo: `.claude/app-init-status.json`. This is what makes every run after the first an incremental audit instead of a full re-interview.

## Schema

```json
{
  "stack": "ios-swiftui",
  "detectedAt": "2026-08-27",
  "verificationMode": "simulator",
  "monetizationModel": "subscription",
  "privacyTermsPattern": "sibling-repo",
  "phase1": {
    "agentsAndClaudeMd": "done",
    "versionedSpec": "done",
    "changelogs": "done",
    "roadmap": "done",
    "releaseDocs": "done",
    "privacyTerms": "done",
    "statusLog": "done"
  },
  "phase2": {
    "playbook": "ios-common-features",
    "items": {
      "settingsSupportLinks": "done",
      "versionUpdateCard": "done",
      "updateCheckerAndAlerts": "done",
      "usagePaywall": "not-started",
      "upgradePillAndSheet": "not-started",
      "ratingPrompt": "done",
      "optionalPermissions": "in-progress",
      "permissionBanner": "not-started",
      "adaptiveAppearance": "done",
      "onboarding": "done"
    }
  }
}
```

`stack` values: `ios-swiftui` today; a future web/Android playbook adds its own value and its own `phase2.playbook` here without changing this schema.

## Verification modes

| Mode | Behavior after implementing/auditing a Phase 2 checklist item |
|---|---|
| `manual` | Print a short checklist of what to check by hand. No tool is driven. |
| `simulator` | Use the iOS Simulator tool: attach, build, launch, screenshot the relevant screen, confirm visually. |
| `browser` | Use the browser tool against the project's dev server (start it via the project's own launch config if not already running). |
| `e2e` | Run the project's existing Playwright/XCTest suite if one exists for the relevant area; fall back to `manual` with a note if no test covers it yet — don't silently skip verification because no test exists. |

## First run

If `.claude/app-init-status.json` doesn't exist, ask once which verification mode to use before starting Phase 2 (skip the question entirely if `--verification=` was passed on this invocation). Persist the answer immediately, before doing any Phase 2 work, so an interrupted first run still leaves the choice recorded.

## Changing it later

`/app-init --verification=<mode>` on any later run overwrites just that one field and proceeds — it does not re-ask anything else, and does not reset `phase1`/`phase2` progress. This is the explicit "switch later by passing a flag" mechanism.

## `--reset`

Deletes `.claude/app-init-status.json` entirely and treats the run as a genuine first run — full re-detection, all questions re-asked. Use this when the repo's actual state has diverged enough from the recorded status that an incremental audit isn't trustworthy (e.g. the file was hand-edited, or a large chunk of scaffolded content was manually removed outside of `app-init`).

## Don't hand-edit this file casually

It's a legitimate JSON file a human can edit directly if needed, but prefer changing it through `/app-init` flags where one exists — hand-edits that don't match the repo's actual state are exactly what `--reset` exists to recover from.

# work-e2e — design

Personal skill (lives in ~/.claude, not the work repo). Claude drives the LOCAL
browser to run/verify MOHR workflows. Inverse of test-start (user-driven).

## Decisions
- Environment: localhost only. Attach to the already-running IDE dev server
  (yarn serve); NEVER build/start (mohr-web no-build rule).
- Engine: Preview tools (preview_*) by default (deterministic replay); optional
  Claude_in_Chrome when the user wants to watch real Chrome.
- Portals: auth :4200 (login) · provider :4202 · tenant :4201. User names the
  portal + goal at trigger time.
- Workflow model: hybrid record-then-save. First run freeform → save successful
  steps as a named recipe (recipes/*.json). login.json is the reusable auth step.
- Reporting: terminal + screenshots (runs/<ts>/) by default; opt-in Azure DevOps
  logging reusing test-start's upload/post scripts.
- Credentials: gitignored .credentials.json (chmod 600), per-env keys. Password
  read at fill-time only; never printed/stored in recipes/logs/comments.

## Guardrails
localhost only · attach-not-build · never print password · confirm data-writing
steps on first pass · no AI mentions in ADO comments.

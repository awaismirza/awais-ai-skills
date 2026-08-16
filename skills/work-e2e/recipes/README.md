# work-e2e recipes

One JSON file per saved workflow. `login.json` is the reusable auth recipe;
workflow recipes are named per task (e.g. `create-booking.json`).

Recipes are created by `/work-e2e` via record-then-save after a successful
freeform run — you don't hand-author them (but you can edit one).

Schema: see the "Recipe schema" section in ../SKILL.md.
Rules: targets are human-readable descriptions (resolved live); URLs use
{auth}/{provider}/{tenant} placeholders; NEVER store credentials here.

# Ticket Plan Template

Use this template when picking up a new ticket. Copy and fill in.

## Ticket: ab#XXXX — [Ticket title]

### 1. Analysis

- **Scope:** [ ] FE-only  [ ] BE-only  [ ] FE+BE
- **Affected FE apps:** [ ] auth  [ ] tenant  [ ] provider  [ ] employee  [ ] booking
- **Affected BE projects:** (list MOHR.* project names)
- **API shape changes?** [ ] Yes → need `yarn nswag`  [ ] No
- **DB changes?** [ ] Yes → need migration  [ ] No
- **Data seed changes?** [ ] Yes → need Seeding class  [ ] No

### 2. Code search before implementing

```
# Find existing patterns before writing new code
graphify query "<feature concept>"
graphify explain "<entity name>"
```

Or grep:
```
# FE: find existing component
Grep pattern in libs/designs/src

# BE: find existing handler
Grep pattern in mohr-api/src/MOHR.Core
```

### 3. Implementation Plan

#### BE (if needed)
- [ ] AppService method in `MOHR.Application` (reads)
- [ ] Command + Handler in `MOHR.Core` (writes)
- [ ] Entity change in `MOHR.EntityFrameworkCore`
- [ ] Migration in `MOHR.EntityFrameworkCore.Migrations`
- [ ] Seeding (if data needed)
- [ ] Build verify: `msbuild src/<Project>/<Project>.csproj -t:rebuild -v:minimal`

#### Proxy regeneration (if API shape changed)
- [ ] `cd mohr-web && yarn nswag`

#### FE (if needed)
- [ ] Check `libs/designs`, `libs/store`, `libs/utils` first
- [ ] Implement with `mo-*` components, reactive forms, services
- [ ] Build verify: `nx build <project> --configuration development`

### 4. PR Checklist

- [ ] Branch: `ab#XXXX-short-description`
- [ ] PR title: `ab#XXXX Short description`
- [ ] Merge from latest `main`
- [ ] PR description: ticket ref, summary, validation, migration status, seeding status
- [ ] `/code-review` before creating PR

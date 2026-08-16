# Cross-Repo Feature Plan — ab#XXXX

> Backend is the contract source. Execution order always flows
> BE → build → `yarn nswag` → FE.

## Ticket: ab#XXXX — [title]

## 1. Scope analysis
- **Scope:** [ ] FE-only  [ ] BE-only  [x] FE+BE
- **BE projects:** (list `MOHR.*` project names)
- **FE apps:** [ ] auth  [ ] tenant  [ ] provider  [ ] employee  [ ] booking
- **FE libs:** [ ] designs  [ ] store  [ ] utils  [ ] service-proxies
- **API contract change?** [ ] Yes → `yarn nswag` required  [ ] No
- **DB migration?** [ ] Yes → `MOHR.EntityFrameworkCore.Migrations`  [ ] No
- **Seeding?** [ ] Yes → `RunOnceSeed` / `Seed` in `MOHR.Seeding`  [ ] No

## 2. Existing patterns to reuse (from semantic search)
- BE: `path/to/file` — why (found via `mcp__mcp-code-search__*`)
- FE: `path/to/file` — why (found via `mcp__mcp-code-search-web__*`)

## 3. Execution order (the contract flow)
1. [ ] BE: `src/MOHR.Core/...` — command/handler (writes) or AppService (reads)
2. [ ] BE: `src/MOHR.EntityFrameworkCore/...` — entity change (if any)
3. [ ] BE: migration in `MOHR.EntityFrameworkCore.Migrations` (if entity changed)
4. [ ] BE: seeding in `MOHR.Seeding` (if data needed)
5. [ ] Build BE: `msbuild src/<Project>/<Project>.csproj -t:rebuild -v:minimal`
6. [ ] Proxies (if API changed): backend up on `:22742`, then
       `cd C:\Source\mohr-web && yarn nswag`
7. [ ] FE: `apps/<app>/...` and `libs/...` — components (`mo-*`), services, reactive forms
8. [ ] Build/test FE: `nx build <app> --configuration development`; `nx test <app>`

## 4. Impact / potential breakage
- BE callers of changed signatures/DTOs/entities
- FE consumers of changed `@Input`/`@Output`/services/routes/types

## 5. Verification
- BE: build 0 errors; `dotnet test` (affected project)
- FE: `nx build` + `nx test`; `libs/service-proxies` compiles after `yarn nswag`
- Smoke: `smoke.ps1 -Apps <apps>` against the running stack

## 6. Gates
- **Gate 1 (now):** plan approval — reply **go**.
- **Gate 2 (after impl):** pre-git — reply **commit**. PRs only on explicit confirm.

## 7. Questions / ambiguities
- ...

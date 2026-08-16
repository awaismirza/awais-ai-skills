---
name: work-patterns
description: "MOHR .NET/CQRS pattern enforcement — validates CQRS split, handler patterns, AppService rules, SmartEnum, Mapperly, migrations, seeding, async rules, and build commands for the mohr-api platform. Use before writing or reviewing any .NET code in mohr-api."
trigger: /work-patterns
---

# /work-patterns

Enforces MOHR platform .NET coding patterns before and during implementation. Covers CQRS split, handler/AppService conventions, SmartEnum, Mapperly, migrations, seeding, async rules, and build.

## Usage

```
/work-patterns              — review all patterns relevant to current task
/work-patterns cqrs         — CQRS split rules only
/work-patterns handlers     — command handler patterns only
/work-patterns appservice   — AppService read patterns only
/work-patterns smartenum    — SmartEnum usage rules only
/work-patterns migrations   — EF Core migration and seeding rules only
/work-patterns async        — async/await rules only
/work-patterns build        — build and compilation rules only
```

---

## What You Must Do When Invoked

Identify which part of the codebase is being modified and apply the relevant pattern rules below. Always check ALL applicable sections — do not skip sections just because the user didn't ask about them explicitly.

---

## Section 1 — CQRS Split (Strictly Enforced)

The MOHR platform enforces a hard CQRS boundary:

| Operation | Location | Base Class |
|---|---|---|
| **Reads** | `MOHR.Application` | `MOHRAppServiceBase` or `MOHRClientAppServiceBase` |
| **Writes** | `MOHR.Core` | `IHandler<TCommand>` registered in `HandlersRegistrar` |

### Read rules (AppService)
- Inherit `MOHRAppServiceBase` or `MOHRClientAppServiceBase`
- Inject `IRepository<TEntity, TKey>` via constructor
- Always use `GetAll().AsNoTracking()` for read-only queries
- Project to DTOs using `.Select(e => new MyDto { ... })`
- **NEVER** call `InsertAsync`, `UpdateAsync`, or `DeleteAsync` from an AppService
- **NEVER** use a command handler for a read-only query

```csharp
// CORRECT
public class MyAppService : MOHRAppServiceBase
{
    private readonly IRepository<MyEntity, Guid> _repo;
    public MyAppService(IRepository<MyEntity, Guid> repo) => _repo = repo;

    public async Task<MyDto> Get(Guid id)
        => await _repo.GetAll().AsNoTracking()
               .Where(e => e.Id == id)
               .Select(e => new MyDto { Id = e.Id, Name = e.Name })
               .FirstOrDefaultAsync();
}
```

### Write rules (Command Handler)
- Define a **record** command with `ICommand` marker: `public record MyCommand(...) : ICommand;`
- Implement `IHandler<TCommand>` (void) or `IHandler<TCommand, TResult>` (returning value)
- Name handler: `{CommandName}Handler` or `{CommandName}CommandHandler`
- Register in `HandlersRegistrar`
- Dispatch via `IDispatcher<TCommand>` — never call handler directly
- Load entities from repositories, apply business rules via domain managers
- Do NOT call `SaveChanges` — unit-of-work commits automatically

```csharp
// CORRECT
public record UpdateAssessmentFrequenciesCommand(Guid AssessmentId, List<AssessmentFrequencyDto> Frequencies) : ICommand;

public class UpdateAssessmentFrequenciesCommandHandler : IHandler<UpdateAssessmentFrequenciesCommand>
{
    private readonly IRepository<Assessment, Guid> _assessmentRepository;
    private readonly IAssessmentFrequencyManager _assessmentFrequencyManager;

    public UpdateAssessmentFrequenciesCommandHandler(
        IRepository<Assessment, Guid> assessmentRepository,
        IAssessmentFrequencyManager assessmentFrequencyManager)
    {
        _assessmentRepository = assessmentRepository;
        _assessmentFrequencyManager = assessmentFrequencyManager;
    }

    public async Task Handle(UpdateAssessmentFrequenciesCommand command)
    {
        var assessment = await _assessmentRepository.GetAsync(command.AssessmentId);
        await _assessmentFrequencyManager.UpdateFrequencies(assessment, command.Frequencies);
    }
}
```

### Anti-patterns — block these immediately:
- ❌ `InsertAsync`/`UpdateAsync`/`DeleteAsync` inside an AppService
- ❌ Query handler that belongs in AppService
- ❌ Direct handler instantiation instead of `IDispatcher<TCommand>`
- ❌ Business logic in the AppService layer

---

## Section 2 — AppService API Routing

ABP auto-generates API routes from `IApplicationService` methods:

- Pattern: `api/services/app/{ServiceName}/{MethodName}`
- Example: `MyFeatureAppService.GetDetails()` → `GET /api/services/app/myFeature/getDetails`
- Do NOT add manual `[Route]` attributes unless absolutely necessary

---

## Section 3 — SmartEnum (Required)

Use `Ardalis.SmartEnum` everywhere traditional enums would be used.

```csharp
// CORRECT — SmartEnum with behavior
public abstract class DocumentType : SmartEnum<DocumentType>
{
    public static readonly DocumentType Assessment = new AssessmentDocumentType();
    public static readonly DocumentType NsWaiverOutcome = new NsWaiverOutcomeDocumentType();

    protected DocumentType(string name, int value) : base(name, value) { }
    public abstract string TemplateName { get; }
}

// Usage
var type = DocumentType.Assessment;
var name = type.AsNameValueDto(); // built-in serialization helper
```

### Anti-patterns:
- ❌ `public enum DocumentType { Assessment, NsWaiverOutcome }` — plain C# enums for extensible values
- ❌ `public const string Assessment = "Assessment"` — magic string constants
- ❌ string-switch on type names

---

## Section 4 — Mapperly (Required, Not AutoMapper)

Use `Abp.Mapperly` (compile-time source-generated mapping). AutoMapper is NOT used.

```csharp
// One-off mapping
var dto = ObjectMapper.Map<MyDto>(entity);

// Injected mapper in services
public class MyService
{
    private readonly IObjectMapper _objectMapper;
    public MyService(IObjectMapper objectMapper) => _objectMapper = objectMapper;

    public MyDto MapToDto(MyEntity entity) => _objectMapper.Map<MyDto>(entity);
}
```

- Mapperly auto-discovers mappings — no manual profile configuration needed
- Never reference `AutoMapper`, `CreateMap`, `MapperConfiguration`, or `Profile`

---

## Section 5 — Multi-Tenancy

All entities must implement one of:
- `IMustHaveTenant` — entity always belongs to a tenant (has `TenantId`, never null)
- `IMayHaveTenant` — entity may be host-level or tenant-level (nullable `TenantId`)
- `ICanShareToSameDbTenants` — allows selective cross-tenant sharing within same DB

ABP applies global query filters automatically — no manual `Where(e => e.TenantId == ...)` needed.

---

## Section 6 — Domain Events

```csharp
// Publishing an event
await _eventBus.TriggerAsync(new EntityCreatedEventData<MyEntity>(entity));

// Handling an event
public class MyEntityEventHandler : MohrEntityChangedEvent<MyEntity>, ITransientDependency
{
    protected override async Task HandleCreatedEventAsync(EntityCreatedEventData<MyEntity> eventData)
    {
        // React to creation
    }

    protected override async Task HandleUpdatedEventAsync(EntityChangedEventData<MyEntity> eventData)
    {
        // React to update
    }

    protected override async Task HandleDeletedEventAsync(EntityDeletedEventData<MyEntity> eventData)
    {
        // React to deletion
    }
}
```

---

## Section 7 — Async / Await Rules

**No exceptions to these rules:**

| Rule | Correct | Wrong |
|---|---|---|
| Always await | `await repo.GetAsync(id)` | `repo.GetAsync(id).Result` |
| No blocking | `await task` | `task.Wait()` |
| No sync-over-async | `await task` | `task.GetAwaiter().GetResult()` |
| Library code | `await x.ConfigureAwait(false)` | `await x` (in library) |
| Return type | `async Task` or `async Task<T>` | `async void` (only for event handlers) |

The `.Result` / `.Wait()` pattern **causes deadlocks** in ASP.NET contexts. Block immediately if seen.

---

## Section 8 — EF Core Migrations

Any change to an entity class in `MOHR.EntityFrameworkCore` **requires** a migration:

```bash
# Generate migration (run from MOHR.EntityFrameworkCore project root)
dotnet ef migrations add {DescriptiveMigrationName} --project MOHR.EntityFrameworkCore.Migrations
```

Migration naming: `{DescriptiveNameInPascalCase}` — no timestamps in name (EF adds snapshot automatically).

**Check:** If entity changed but no file added to `MOHR.EntityFrameworkCore.Migrations`, the PR is incomplete.

---

## Section 9 — Seeding Patterns

| Pattern | Use When | Base Class |
|---|---|---|
| `RunOnceSeed` | One-time corrective data fix | `RunOnceSeed` |
| `Seed` | Repeatable reference/bootstrap data | `Seed` |

Both live in `MOHR.Seeding`. Never use ad-hoc SQL scripts.

```csharp
// One-time fix
public class CorrectBrokenEmployeeData_20240315 : RunOnceSeed
{
    public override async Task<bool> CanExecute()
        => await _repo.CountAsync(e => e.IsBroken) > 0;

    public override async Task Execute()
    {
        var broken = await _repo.GetAll().Where(e => e.IsBroken).ToListAsync();
        foreach (var e in broken) e.IsBroken = false;
    }
}

// Repeatable reference data
public class DocumentTypesSeed : Seed
{
    public override async Task Execute()
    {
        if (!await _repo.AnyAsync(x => x.Code == "REF001"))
            await _repo.InsertAsync(new RefEntity { Code = "REF001" });
    }
}
```

---

## Section 10 — Build & Compilation Rules

**Always use `msbuild`, not `dotnet build`:**

```bash
# Narrowest project first
msbuild src/MOHR.Core/MOHR.Core.csproj -t:rebuild -v:minimal

# Full solutions (use sparingly)
msbuild MOHR.Api.sln -t:rebuild -v:minimal
msbuild MOHR.All.sln -t:rebuild -v:minimal
```

Use `-` not `/` for switches in bash (Git Bash strips leading `/`).

**New source files:**
- SDK-style projects (modern .NET): files are implicitly included — do NOT add `<Compile Include="..." />` to the `.csproj`
- Legacy non-SDK projects (rare): must explicitly add `<Compile Include="Path\To\File.cs" />`
- Check the `.csproj` format before adding files

**NuGet packages:**
- Never install or update via CLI
- Always ask the user to use Visual Studio's NuGet Package Manager

---

## Section 11 — Plugin Patterns

New plugins require changes in 4 places:

1. **SmartEnum registration** in `MOHR.Plugin.Model/Plugins/Plugin.cs`:
```csharp
public static readonly Plugin MyNewPlugin = new MyNewPluginDefinition();
```

2. **Implementation** in a dedicated `MOHR.Plugin.{Name}` project implementing `IPlugin`

3. **Pipeline registration** in `deploy/azure-pipelines-plugins.yaml`

4. **CDK stack registration** in `deploy/MOHR.Deployment.Plugins/lib/mohr-plugins-stack.ts` → `PLUGIN_NAMES` array

**Anti-patterns:**
- ❌ Inject one plugin into another
- ❌ Call plugin implementations directly — use message bus only
- ❌ Add plugin to runtime project instead of `MOHR.Plugin.Model`

---

## Section 12 — Webhook Patterns

**Pattern A — Entity lifecycle webhook** (follows Create/Update/Delete automatically):
1. Add name to `AppWebHookNames`
2. Register definition in `MohrWebhookDefinitionProvider`
3. Handle in `MohrEntityChangedEvent<TEntity>` subclass
4. Publisher enqueues a background job

**Pattern B — Workflow-triggered webhook** (specific business logic step):
1. Add name to `AppWebHookNames`
2. Register definition
3. Call publisher method directly from the manager/handler at the right workflow step

Never publish a webhook name not defined in `AppWebHookNames`.

---

## Quick Reference Card

```
Reads           → MOHR.Application / AppService / AsNoTracking
Writes          → MOHR.Core / IHandler<TCommand> / HandlersRegistrar
Enums           → SmartEnum (Ardalis.SmartEnum), never plain enum/string
Mapping         → Mapperly / ObjectMapper.Map<T>(), never AutoMapper
Multi-tenancy   → IMustHaveTenant or IMayHaveTenant on all entities
Async           → always await, never .Result/.Wait()
Build           → msbuild -t:rebuild, never dotnet build
Entity changed  → migration required in MOHR.EntityFrameworkCore.Migrations
Data fix        → RunOnceSeed; reference data → Seed (both in MOHR.Seeding)
New plugin      → SmartEnum + IPlugin + pipeline YAML + CDK stack
New .cs file    → do NOT add <Compile Include> to SDK-style .csproj
NuGet           → Visual Studio Package Manager only, never CLI
```

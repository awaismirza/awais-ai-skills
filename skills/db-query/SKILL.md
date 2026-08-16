---
name: db-query
description: Write and execute MOHR SQL queries with full schema awareness. Use this whenever you need to query the MOHR database (asking about users, assessments, bookings, claims, etc.) or when explicitly asked to "write a query". Automatically handles multi-tenancy, soft deletes, ABP conventions, and provides both executable results and copy-paste SQL code. Covers Host database (management), tenant databases, and cross-tenant analysis.
---

# MOHR SQL Query Skill

Write, execute, and explain MOHR-specific SQL queries with automatic schema awareness and best practices.

## Live Schema Awareness ⚡

This skill automatically loads the **live database schema** from `~/.claude/mohr-schema/SCHEMA_MASTER.json`. This means:

✅ **Always up-to-date**: Schema fetched directly from running SQL Server  
✅ **No manual learning needed**: Table structures are auto-loaded  
✅ **Timestamp tracked**: Last updated timestamp included (see `/schema-check` to verify)  
✅ **Cross-session**: Persistent across all sessions in `.claude` folder  

If schema changes (migrations, new tables), refresh with:
```bash
python3 ~/.claude/mohr-schema/refresh-schema.py
```

Or use `/schema-check` skill for easy status and refresh.

---

## When to Use This Skill

Use `/db-query` when:
- **Explicit requests**: "Write a query to find...", "Show me SQL that...", "Get a list of..."
- **Implicit data questions**: "Who has language set to en-MS?", "How many assessments are there?", "Which tenants have...", "Show me users where...", "Count X by Y"
- **Investigation work**: Exploring data, verifying assumptions, debugging state
- **Data extraction**: Exporting data for analysis, reporting, or validation

## Workflow

### OUTPUT FORMAT IS CRITICAL
**Always follow this order:**
1. **Results** - Actual data/output from the query
2. **Explanation** - Simple, Technical, Business Logic, Step-by-step
3. **SQL Code** - Copy-paste ready at the bottom

Never put SQL code at the top. Never skip any explanation sections. Never use vague explanations.

---

### 1. Clarify Intent & Scope

When the user asks a data question:

**Ask about scope** (if ambiguous):
- "Which database? (Host for management data, specific tenant like AdeccoTenant, or all tenants?)"
- "Single tenant, specific list of tenants, or all tenants?"
- "What time range?" (if relevant to CreationTime, CompletedDate, etc.)

**If the question is clear**, skip this step and proceed.

**Common databases:**
- `Host`: Central management DB (AbpUsers, AbpTenants, AbpSettings, all feature management data)
- `Provider`: Provider portal DB (separate from tenant DBs)
- Tenant DBs (e.g., `AdeccoTenant`, `DemoTenant`): Each tenant's assessment, booking, claim data

### 2. Write the Query

Follow these principles:

**Structure:**
- Use CTEs (WITH clauses) for readability; name descriptively
- Filter early: push WHERE clauses close to base tables
- Never use `SELECT *` — specify only needed columns

**Multi-Tenancy Patterns:**
- If querying a single tenant: `WHERE TenantId = @tenantId`
- If querying all tenants: join to `AbpTenants` to show tenant names
- For cross-database: note that you need separate queries or linked servers (not typical in dev)

**Soft Deletes:**
- Always include `WHERE IsDeleted = 0` unless you specifically want deleted records
- ABP marks deleted records with `IsDeleted = 1`, `DeletionTime`, `DeleterUserId`

**Common MOHR Tables:**

**ABP Core:**
- `AbpUsers` - Users (Id, TenantId, EmailAddress, UserName, IsActive, IsDeleted, CreationTime)
- `AbpSettings` - Settings/preferences (Name, Value, TenantId, UserId) — language stored here
- `AbpTenants` - Tenants (Id, Name, TenancyName, IsActive, IsProvider, ConnectionString)
- `AbpLanguages` - Languages (Id, Name, DisplayName, TenantId)
- `AbpRoles` - Roles (Id, Name, DisplayName, TenantId, IsClinicalRole, IsMedicalRole, IsPsychologyRole)

**Assessment & Booking:**
- `AssessmentBookingRequests` - Main booking entity (Id, TenantId, EmployeeId, JobTypeId, Status, CompletedDate)
- `AssessmentFlows` - Assessment workflow definitions
- `AssessmentFlowVersions` - Versioned workflow templates
- `AssessmentBookingProgressBlocks` - In-progress assessment blocks
- `AssessmentBookingOutcomes` - Assessment results
- `AssessmentBookingTests` - Test administration records
- `AssessmentBookingNotes` - Clinical/admin notes
- `AssessmentBookingHistory` - State change audit trail

**Claims:**
- `Claims` - Insurance claims (Id, TenantId, Status, CreationTime)
- `ClaimCompensations` - Compensation amounts
- `ClaimDocuments` - Supporting documents
- `ClaimNotes` - Notes with audit

**Booking Appointments:**
- `BookingRequestAppointments` - Scheduled appointments
- `BookingRequestAppointmentAssignments` - Provider assignments

**Key Columns:**
- `Id` (uniqueidentifier or bigint): Primary key
- `TenantId` (int): Multi-tenancy — filter this unless doing cross-tenant analysis
- `CreationTime, LastModificationTime` (datetime2): Audit timestamps (UTC)
- `CreatorUserId, LastModifierUserId` (bigint): Audit user references
- `IsDeleted` (bit): Soft delete flag — filter `WHERE IsDeleted = 0`
- `Status` (int): SmartEnum — check the enum definition in C# for values

**Example CTE Pattern:**
```sql
WITH user_settings AS (
  SELECT u.Id, u.EmailAddress, u.TenantId, s.Name, s.Value
  FROM AbpUsers u
  LEFT JOIN AbpSettings s ON u.Id = s.UserId
  WHERE u.IsDeleted = 0
),
filtered_by_language AS (
  SELECT Id, EmailAddress, TenantId, Value
  FROM user_settings
  WHERE Value = 'en-MS'
)
SELECT * FROM filtered_by_language
ORDER BY TenantId, EmailAddress
```

**Performance Notes:**
- Partition by TenantId first if querying all tenants
- Use EXISTS instead of IN for subqueries with large result sets
- Avoid correlated subqueries when a JOIN works
- Add indexes hint if needed: consider what columns are filtered/joined

### 3. Execute the Query (With Safety Checks)

**BEFORE execution, check the query type:**

**IF SELECT/GET Query (Safe to execute):**
- Execute via docker: `docker exec sql-<container> /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123' -C -d <database> -Q "..."`
- Show actual results in the output
- Proceed to step 4 with results displayed

**IF UPDATE/DELETE Query (Write operation - DO NOT AUTO-EXECUTE):**
- ⚠️ **DO NOT execute the query automatically**
- Provide the SQL code for user to run manually in DataGrip
- Provide the docker command they can copy and run if they want
- Ask user for confirmation before executing
- Example docker command for manual execution:
  ```bash
  docker exec sql-<container-id> /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123' -C -d <database> -Q "UPDATE ... SET ..."
  ```

**Connection Details:**
- Server: `localhost` (Aspire-managed SQL Server via Docker)
- User: `sa`
- Password: `Password123`
- Databases: Host, Provider, or specific tenant databases
- Docker container: Found via `docker ps --filter "name=sql"`

**Always provide both:**
1. DataGrip copy-paste SQL (for user to run manually)
2. Docker command (as alternative execution method)

### 4. Show Results & Provide Full Explanation & SQL

**REQUIRED Output structure (in this exact order):**

```markdown
## Results

[Formatted results table, summary statistics, or data visualization]
[Include row count, date range if applicable, any summary metrics]

## Explanation

### Simple Explanation (Plain English)
[Explain what the query finds in one sentence a non-technical person can understand]
Example: "This query finds all users who have chosen en-MS as their language preference and shows which organization they belong to."

### Technical Explanation (How It Works)
[Explain the query structure, joins, filters, and logic in technical terms]
- What tables are involved and why
- What each JOIN does and the relationship
- What WHERE conditions filter and why
- How the data flows through CTEs (if used)
- Which columns are selected and their meaning
Example: "The query uses a LEFT JOIN between AbpUsers and AbpSettings tables, matching users with their language settings. It filters WHERE s.Value = 'en-MS' to find only those with the custom DFR language, then LEFT JOINs to AbpTenants to show the tenant name each user belongs to."

### Business Logic Explanation (Why This Matters)
[Explain the business purpose and value of this data]
- Why would someone need this information
- What business decisions depend on this data
- What insights does this provide
Example: "This helps identify which users have opted into the DFR (Defence Force Recruiting) localization. This is important for understanding user preferences and ensuring localized content is being used correctly. It also helps validate that the language settings feature is working as intended."

### Query Walkthrough (Step-by-Step Execution)
[Show the logical flow of how the query executes]
1. Start with AbpUsers table (X total users)
2. LEFT JOIN to AbpSettings to get user preferences
3. Filter for Value = 'en-MS' (reduces to Y rows)
4. LEFT JOIN to AbpTenants to get organization names
5. ORDER BY for consistent results
6. Final result: Z users found

### Performance Notes
- [Indexes used or recommended]
- [Potential bottlenecks and how to optimize]
- [Row count impact]
- [Execution time if available]

### How to Modify This Query
- **Different language**: Change `'en-MS'` to `'en-US'`, `'es-ES'`, etc.
- **Specific tenant only**: Add `AND u.TenantId = 736`
- **Recent changes**: Add `AND u.LastModificationTime >= '2025-06-01'`
- **Active users only**: Add `AND u.IsActive = 1`

## SQL Code (Copy & Paste for DataGrip)

\`\`\`sql
[The exact SQL query, ready to copy and run in DataGrip]
\`\`\`

## Execution Methods

### For SELECT/GET Queries (Already Executed Above):
Results are shown above. Query was executed and results displayed.

### For UPDATE/DELETE Queries (Manual Execution Required):
⚠️ **This query modifies data — requires manual execution for safety**

**Option 1: Run in DataGrip**
- Copy the SQL code above
- Paste into DataGrip query editor
- Execute and verify results before committing

**Option 2: Run via Docker/Command Line**
\`\`\`bash
docker exec <container-id> /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123' -C -d <database> -Q "..."
\`\`\`

⚠️ Always test on a non-production environment first

## Summary

[2-3 sentence summary of findings or intended changes]
[Key metrics: rows affected/returned, notable patterns, any validation notes]
```

## Key MOHR Patterns

### Query Users with Language en-MS
```sql
SELECT u.Id, u.EmailAddress, u.UserName, u.TenantId, t.Name AS TenantName, s.Value AS Language
FROM AbpUsers u
LEFT JOIN AbpSettings s ON u.Id = s.UserId
LEFT JOIN AbpTenants t ON u.TenantId = t.Id
WHERE s.Value = 'en-MS'
  AND u.IsDeleted = 0
ORDER BY u.TenantId, u.UserName
```

### Count Assessments by Tenant & Status
```sql
WITH assessment_counts AS (
  SELECT TenantId, Status, COUNT(*) AS CountByStatus
  FROM AssessmentBookingRequests
  WHERE IsDeleted = 0
  GROUP BY TenantId, Status
)
SELECT t.Name AS TenantName, ac.Status, ac.CountByStatus
FROM assessment_counts ac
INNER JOIN AbpTenants t ON ac.TenantId = t.Id
WHERE t.IsDeleted = 0
ORDER BY t.Name, ac.Status
```

### Users with Multiple Bookings
```sql
WITH booking_counts AS (
  SELECT EmployeeId, COUNT(*) AS BookingCount
  FROM AssessmentBookingRequests
  WHERE IsDeleted = 0
  GROUP BY EmployeeId
  HAVING COUNT(*) > 1
)
SELECT bc.EmployeeId, bc.BookingCount, u.EmailAddress, u.TenantId
FROM booking_counts bc
LEFT JOIN AbpUsers u ON bc.EmployeeId = CAST(u.Id AS uniqueidentifier)
ORDER BY bc.BookingCount DESC
```

## Important Notes

### 🔒 Safety & Execution Rules
- **SELECT queries**: ✅ Automatically executed, results shown immediately
- **UPDATE/DELETE queries**: ⚠️ NOT auto-executed, provided for manual review
- **Write operations**: Always test on non-prod first
- **Always provide**: DataGrip SQL + docker command for manual execution

### Data & Schema Rules

**Soft Deletes:** Always filter `IsDeleted = 0` unless you specifically want deleted records. ABP marks deletions logically, not physically.

**Multi-Tenancy:** Every MOHR entity has a `TenantId` column. Filtering by tenant is critical for data isolation. When in doubt, ask which tenant or show results grouped by tenant.

**UTC Timestamps:** All `CreationTime`, `LastModificationTime`, etc. are UTC. No conversion needed if your timezone is UTC.

**Database Connection:** Docker-managed SQL Server at localhost:52942. Individual tenant databases are separate (`AdeccoTenant`, `DemoTenant`, etc.). Get container ID dynamically via `docker ps --filter "name=sql"`.

**SmartEnum Status Values:** Status fields (like `AssessmentBookingRequests.Status`) are stored as integers representing SmartEnum values. Check the C# enum definition in the codebase for the exact mapping (e.g., 1 = Pending, 2 = InProgress, 3 = Completed).

**Audit Columns:** Every table has `CreationTime`, `CreatorUserId`, `LastModificationTime`, `LastModifierUserId` for compliance and debugging. Use these to trace who changed what and when.

### Output Format Reminder
**Always use this order:**
1. Results (for SELECT queries only)
2. Explanation (Simple, Technical, Business Logic, Walkthrough)
3. SQL Code (Copy-paste ready)
4. Execution Methods (docker command for writes)

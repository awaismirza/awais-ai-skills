---
name: schema-check
description: Check MOHR database schema status and refresh live schema from SQL Server. Shows last update timestamp, which databases are tracked, table counts, and provides one-command refresh. Use when you want to verify schema is up-to-date or refresh after migrations.
---

# MOHR Schema Status Checker

Check and refresh the live database schema from the running Aspire SQL Server.

## When to Use This Skill

Use `/schema-check` when:
- **Before heavy querying**: Verify schema is current before writing queries
- **After migrations**: Refresh schema after EF Core migrations or schema changes
- **Troubleshooting**: "Table not found" errors or unexpected column names
- **Routine maintenance**: Weekly/daily status check of schema version
- **Quick reference**: See what tables are tracked and available

## Workflow

### 1. Check Current Status

Simply run `/schema-check` to see:
- ✅ Last updated timestamp
- 📊 Databases currently tracked
- 📋 Table counts per database
- 🔗 Key tables by category
- 🔄 How to refresh if needed

### 2. Refresh Schema (If Needed)

If schema is stale or you just ran migrations, refresh with:

**Option A: Interactive refresh**
```bash
# Refresh Host and Provider databases (main databases)
python3 ~/.claude/mohr-schema/refresh-schema.py
```

**Option B: Refresh all tenant databases (one-time)**
```bash
# After first setup, fetch all 27 tenant databases for complete coverage
for db in AdeccoTenant DemoTenant DJCSTenant DTPTenant \
  EssentialEnergyTenant FedexTenant HealthworksTenant \
  JamesHardieTenant OricaTenant PHITenant \
  StJohnofGodTenant TruHealthTenant VeoliaTenant WACHSTenant; do
  python3 ~/.claude/mohr-schema/refresh-schema.py $db
done
```

### 3. Verify Refresh Completed

Run `/schema-check` again to confirm:
- 🕐 New timestamp (should be current)
- ✅ All expected tables present
- 📊 Accurate table counts

## Schema Details

### Current Schema Sources

**Live Schema Master** (`SCHEMA_MASTER.json`)
- Fetched from: Aspire SQL Server (`localhost:52942`)
- Container: `sql-d7dadc1e`
- User: `sa`
- Updated: Auto-loaded from live connection

**Database Coverage**
- ✅ **Host**: Central management DB (users, tenants, settings)
- ✅ **Provider**: Provider portal DB (schedules, assignments)
- ⏳ **Tenant Databases**: 27 customer-specific databases (optional, bulk refresh available)

### Key Tables Tracked

**By Category:**
- **Assessment**: AssessmentFlows, AssessmentFlowVersions, AssessmentBookingRequests, AssessmentBookingTests, AssessmentBookingOutcomes
- **Booking**: BookingRequestAppointments, BookingRequestAppointmentAssignments
- **Employee**: Employees, EmployeeJobTypes, EmployeeDocuments
- **Claims**: Claims, ClaimCompensations, ClaimDocuments
- **Health**: EhmActivities, EhmReminders, EhmHealthPlans
- **Occupational**: OccHygieneExposures, OccHygieneSamples, OccHygieneAgents
- **Scheduling**: Schedules, ScheduleBookedSlots, ScheduleWaitLists
- **ABP**: AbpUsers, AbpRoles, AbpTenants, AbpOrganizationUnits, AbpSettings

### Standard MOHR Columns

Every table follows these conventions:

**Soft Deletes (ABP)**
- `IsDeleted` (bit): Logical deletion flag
- `DeletionTime` (datetime2): When deleted
- `DeleterUserId` (bigint): Who deleted it

**Audit Trail**
- `CreationTime` (datetime2): Creation timestamp (UTC)
- `CreatorUserId` (bigint): User who created
- `LastModificationTime` (datetime2): Last change timestamp
- `LastModifierUserId` (bigint): User who last modified

**Multi-Tenancy**
- `TenantId` (int): Tenant identifier (filter required in all queries)

**Status Codes (SmartEnum)**
- `Status` (int): Stored as integer, maps to C# enums
- Example: Status 1=Pending, 15=Completed, 24=ReportGenerated

## Automation (Optional)

### Set Up Auto-Refresh Cron

For automatic daily refresh:

```bash
# Create refresh script
cat > ~/.claude/mohr-schema/cron-refresh.sh << 'EOF'
#!/bin/bash
python3 ~/.claude/mohr-schema/refresh-schema.py >> ~/.claude/mohr-schema/refresh.log 2>&1
EOF

chmod +x ~/.claude/mohr-schema/cron-refresh.sh
```

Add to crontab:
```bash
crontab -e
# Add this line to run daily at 8 AM:
0 8 * * * /Users/mohr/.claude/mohr-schema/cron-refresh.sh
```

## Integration with /db-query

The `/db-query` skill automatically uses `SCHEMA_MASTER.json`:

1. When you run `/db-query`, it loads the live schema
2. Understands all table structures automatically
3. Suggests correct table and column names
4. Validates relationships before writing queries

**No manual setup needed** — just ensure schema is current with `/schema-check`.

## Troubleshooting

### "Table not found" error
→ Run `/schema-check` and refresh if schema is stale

### Schema doesn't match code
→ After running migrations, refresh immediately:
```bash
python3 ~/.claude/mohr-schema/refresh-schema.py
```

### New column not recognized
→ Refresh to pick up latest schema changes

### Can't connect to SQL Server
→ Verify Aspire is running:
```bash
docker ps --filter "name=sql"
```

## Files Reference

**Schema Files** (`~/.claude/mohr-schema/`)
- `SCHEMA_MASTER.json` ← Live schema (auto-generated with timestamp)
- `SCHEMA_REFERENCE.md` ← Human-readable conventions and patterns
- `refresh-schema.py` ← Python script to fetch from SQL Server
- `README.md` ← Full documentation

## Commands Summary

```bash
# Check schema status (this is what /schema-check does)
python3 -c "import json; data=json.load(open(Path.home() / '.claude/mohr-schema/SCHEMA_MASTER.json')); print(f'Updated: {data[\"timestamp\"]}'); print(f'Databases: {list(data[\"databases\"].keys())}')"

# Refresh schema from SQL Server
python3 ~/.claude/mohr-schema/refresh-schema.py

# Refresh all tenant databases
for db in AdeccoTenant DemoTenant ...; do python3 ~/.claude/mohr-schema/refresh-schema.py $db; done

# View schema file location
ls -lh ~/.claude/mohr-schema/SCHEMA_MASTER.json
```

## What's Tracked

✅ All tables in Host and Provider databases  
✅ Column names and data types  
✅ Key table relationships  
✅ Standard audit columns  
✅ Multi-tenancy structure  
✅ Update timestamp for validation  

🔄 Not tracked (on-demand):  
- Exact column constraints  
- Trigger definitions  
- Stored procedure logic  
- Index details  

For those, query SQL Server directly via `/db-query`.

## Summary

**Schema Status**: Use `/schema-check` before heavy querying to verify freshness  
**Refresh**: One-line command after migrations  
**Auto-Sync**: Optional cron setup for daily refresh  
**Always Current**: `/db-query` automatically uses latest schema  

If schema seems wrong, **refresh first** — most issues resolve with an up-to-date schema.

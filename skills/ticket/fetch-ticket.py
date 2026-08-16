#!/usr/bin/env python3
"""
Fetch an Azure DevOps ticket and scaffold a local workspace folder.

Creates:
  <repo>/.claude/tickets/<id>-<slug>/   (or ~/.claude/tickets/ if no .claude/ in repo)
    ticket.md       — full ticket content
    prs.md          — linked pull requests
    comments.md     — discussion thread
    images/         — downloaded inline images
    linked/         — parent, child, related ticket summaries
"""
import sys, json, subprocess, re, html as html_module, os, shutil
from urllib.parse import unquote
from pathlib import Path
import urllib.request, urllib.error

AZDO_ORG     = "occhealth"
AZDO_PROJECT = "MOHR"

_AZ_FALLBACK = r"C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
_token_cache: dict = {}


# ── Path resolution ───────────────────────────────────────────────────────────

def find_az() -> str:
    """Return az CLI path: prefer PATH, fall back to known Windows location."""
    found = shutil.which("az")
    if found:
        return found
    if os.path.exists(_AZ_FALLBACK):
        return _AZ_FALLBACK
    # On Windows the CLI launcher is sometimes just 'az.cmd'
    found_cmd = shutil.which("az.cmd")
    if found_cmd:
        return found_cmd
    raise FileNotFoundError(
        "Azure CLI (az) not found on PATH. Install it or add it to PATH."
    )


def find_tickets_dir() -> Path:
    """
    Return the directory where ticket workspaces should be created.
    Prefers <git-repo-root>/.claude/tickets/ when inside a repo that has a
    .claude/ folder. Falls back to ~/.claude/tickets/.
    """
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        repo_root = Path(result.stdout.strip())
        claude_dir = repo_root / ".claude"
        if claude_dir.exists():
            return claude_dir / "tickets"
    return Path.home() / ".claude" / "tickets"


AZ      = find_az()
TICKETS = find_tickets_dir()

CUSTOM_FIELDS = [
    ("Custom.Scenario",          "Context / Problem Space"),
    ("Custom.UserStory",         "User Story"),
    ("Custom.Location",          "Location"),
    ("Custom.Navigation",        "Flow of Events"),
    ("Custom.Diagram",           "Diagram"),
    ("Custom.BusinessRules",     "Business Rules"),
    ("Custom.UseCases",          "Use Cases"),
    ("Custom.Mockups",           "Mockups"),
    ("Custom.NotesforDevTeam",   "Notes for Dev Team"),
    ("Custom.DevTeamNotes",      "Dev Team Notes"),
    ("Custom.NotesfromBusiness", "Notes from Business"),
    ("Custom.ProductTeamNotes",  "Product Team Notes"),
    ("Custom.DeploymentPlan",    "Deployment Plan"),
]


# ── Auth ──────────────────────────────────────────────────────────────────────

def get_azdo_token() -> str:
    if _token_cache.get("token"):
        return _token_cache["token"]
    r = subprocess.run([AZ, "account", "get-access-token",
                        "--resource", "499b84ac-1321-427f-aa17-267ca6975798", "-o", "json"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode == 0 and r.stdout:
        _token_cache["token"] = json.loads(r.stdout)["accessToken"]
    return _token_cache.get("token", "")


def azdo_get(path: str) -> tuple[dict | list | None, int]:
    token = get_azdo_token()
    url   = f"https://dev.azure.com/{AZDO_ORG}/{AZDO_PROJECT}/_apis/{path}"
    hdrs  = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    try:
        req = urllib.request.Request(url, headers=hdrs)
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read()), resp.status
    except urllib.error.HTTPError as e:
        return None, e.code
    except Exception:
        return None, 0


# ── Helpers ───────────────────────────────────────────────────────────────────

def az_run(*args, timeout=30):
    r = subprocess.run([AZ, *args], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout)
    return r.stdout.strip(), r.returncode


def slugify(text: str, max_len=45) -> str:
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    text = text.strip("-")
    return text[:max_len].rstrip("-")


def extract_figma_url(html_text: str) -> str:
    if not html_text:
        return ""
    urls = re.findall(r'https://www\.figma\.com/[^\s"\'<>&]+', html_text)
    return urls[0] if urls else ""


def download_images(html_fields: list[str], img_dir: Path,
                    prefix: str = "", counter_start: int = 1) -> dict[str, Path]:
    """Download all <img src=...> URLs. Uses AzDO token for attachment URLs."""
    seen, mapping = set(), {}
    counter = [counter_start]
    azdo_token = get_azdo_token()

    for html_text in html_fields:
        for url in re.findall(r'<img[^>]*src=["\']([^"\']+)["\']', html_text, re.I):
            if url in seen:
                continue
            seen.add(url)
            qs_name = re.search(r'[?&]fileName=([^&]+)', url)
            filename = unquote(qs_name.group(1)) if qs_name else \
                       unquote(url.rsplit("/", 1)[-1].split("?")[0]) or "image.png"
            if not filename.lower().endswith(('.png','.jpg','.jpeg','.gif','.webp')):
                filename += ".png"
            local = img_dir / f"{counter[0]:02d}_{prefix}{filename}"
            counter[0] += 1
            if local.exists():
                mapping[url] = local
                continue
            is_azdo = "dev.azure.com" in url and "_apis/wit/attachments" in url
            hdrs = {"Authorization": f"Bearer {azdo_token}"} if is_azdo else \
                   {"User-Agent": "Mozilla/5.0"}
            try:
                req = urllib.request.Request(url, headers=hdrs)
                with urllib.request.urlopen(req, timeout=15) as resp:
                    local.write_bytes(resp.read())
                mapping[url] = local
            except Exception:
                mapping[url] = None
    return mapping


def strip_html(text: str, img_map: dict | None = None) -> str:
    if not text:
        return ""
    if img_map is not None:
        def replace_img(m):
            src = m.group(1)
            local = img_map.get(src)
            if local:
                return f"\n> 📷 **[Image]** — `{local}`\n"
            filename = unquote(src.rsplit("/", 1)[-1].split("?")[0]) or "image"
            return f"\n> 📷 **[Image: {filename}]** — download failed\n"
        text = re.sub(r'<img[^>]*src=["\']([^"\']+)["\'][^>]*/?>',
                      replace_img, text, flags=re.I)
    else:
        text = re.sub(r'<img[^>]*src=["\']([^"\']+)["\'][^>]*/?>',
                      lambda m: f"\n> 📷 [{unquote(m.group(1).rsplit('/',1)[-1].split('?')[0])}]\n",
                      text, flags=re.I)
    text = re.sub(r'<br\s*/?>', '\n', text, flags=re.I)
    text = re.sub(r'</(?:p|div|tr|li)>', '\n', text, flags=re.I)
    text = re.sub(r'<h[1-6][^>]*>(.*?)</h[1-6]>', r'**\1**', text, flags=re.I | re.S)
    text = re.sub(r'<li[^>]*>', '- ', text, flags=re.I)
    text = re.sub(r'<a[^>]*href=["\']([^"\']+)["\'][^>]*>(.*?)</a>',
                  lambda m: m.group(2).strip() or m.group(1), text, flags=re.I | re.S)
    text = re.sub(r'<[^>]+>', '', text)
    text = html_module.unescape(text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


# ── Ticket fetching ───────────────────────────────────────────────────────────

def fetch_wi(ticket_id: str) -> dict | None:
    raw, code = az_run("boards", "work-item", "show",
                       "--id", ticket_id, "--expand", "relations", "-o", "json")
    if code != 0 or not raw:
        return None
    return json.loads(raw)


def build_ticket_md(wi: dict, img_map: dict) -> str:
    f    = wi.get("fields", {})
    rels = wi.get("relations") or []
    tid  = f.get("System.Id", "?")

    title        = f.get("System.Title", "")
    state        = f.get("System.State", "")
    wi_type      = f.get("System.WorkItemType", "")
    priority     = f.get("Custom.MOHR_Priority") or str(f.get("Microsoft.VSTS.Common.Priority", ""))
    story_pts    = f.get("Microsoft.VSTS.Scheduling.StoryPoints", "")
    assigned     = (f.get("System.AssignedTo") or {}).get("displayName", "Unassigned")
    iteration    = f.get("System.IterationPath", "")
    app_name     = f.get("Custom.ApplicationName", "")
    module_name  = f.get("Custom.ModuleName", "")
    tags         = f.get("System.Tags", "")
    clickup      = f.get("Custom.ClickUpID", "")
    ticket_owner = f.get("Custom.TicketOwner", "")
    parent_id    = f.get("System.Parent", "")
    figma_url    = extract_figma_url(f.get("Custom.Figma", ""))

    acceptance = strip_html(f.get("Microsoft.VSTS.Common.AcceptanceCriteria", ""), img_map)
    repro      = strip_html(f.get("Microsoft.VSTS.TCM.ReproSteps", ""), img_map)
    desc       = strip_html(f.get("System.Description", ""), img_map)

    children = []
    related  = []
    for rel in rels:
        rel_type = rel.get("rel", "")
        rel_id   = rel.get("url", "").rsplit("/", 1)[-1]
        if rel_type == "System.LinkTypes.Hierarchy-Forward":
            children.append(rel_id)
        elif rel_type == "System.LinkTypes.Related":
            related.append(rel_id)

    out = []
    out.append(f"# ab#{tid} — {title}")
    out.append("")
    out.append(f"**Type:** {wi_type}  |  **State:** {state}  |  **Priority:** {priority}" +
               (f"  |  **Points:** {story_pts}" if story_pts else ""))
    out.append(f"**Assigned:** {assigned}  |  **Sprint:** {iteration}")
    if app_name:
        out.append(f"**App:** {app_name}" + (f"  |  **Module:** {module_name}" if module_name else ""))
    if ticket_owner:
        out.append(f"**Ticket Owner:** {ticket_owner}")
    if tags:
        out.append(f"**Tags:** {tags}")
    if clickup:
        out.append(f"**ClickUp:** {clickup}")
    if figma_url:
        out.append(f"**Figma:** {figma_url}")
    if parent_id:
        out.append(f"**Parent:** ab#{parent_id}")
    if children:
        out.append("**Children:** " + ", ".join(f"ab#{c}" for c in children))
    if related:
        out.append("**Related:** " + ", ".join(f"ab#{r}" for r in related))
    out.append("")

    for field_key, label in CUSTOM_FIELDS:
        raw_html = f.get(field_key, "")
        if not raw_html or not str(raw_html).strip():
            continue
        content = strip_html(raw_html, img_map)
        if content:
            out.append(f"## {label}")
            out.append("")
            out.append(content)
            out.append("")

    for content, label in [(desc, "Description"), (repro, "Steps / Requirements"),
                           (acceptance, "Acceptance Criteria")]:
        if content:
            out.append(f"## {label}")
            out.append("")
            out.append(content)
            out.append("")

    return "\n".join(out)


def build_linked_md(wi: dict, relation_type: str) -> str:
    f   = wi.get("fields", {})
    tid = f.get("System.Id", "?")
    out = []
    out.append(f"# ab#{tid} — {f.get('System.Title','')} [{relation_type}]")
    out.append("")
    out.append(f"**Type:** {f.get('System.WorkItemType','')}  |  **State:** {f.get('System.State','')}  |  **Priority:** {f.get('Custom.MOHR_Priority') or f.get('Microsoft.VSTS.Common.Priority','')}")
    out.append(f"**Sprint:** {f.get('System.IterationPath','')}  |  **Assigned:** {(f.get('System.AssignedTo') or {}).get('displayName','?')}")
    out.append("")

    for field_key, label in [
        ("Custom.Scenario",   "Context / Problem Space"),
        ("Custom.UserStory",  "User Story"),
        ("Custom.Navigation", "Flow of Events"),
        ("System.Description", "Description"),
        ("Microsoft.VSTS.TCM.ReproSteps", "Steps / Requirements"),
        ("Microsoft.VSTS.Common.AcceptanceCriteria", "Acceptance Criteria"),
    ]:
        raw = f.get(field_key, "")
        if raw and str(raw).strip():
            content = strip_html(raw)
            if content:
                out.append(f"## {label}")
                out.append("")
                out.append(content)
                out.append("")

    return "\n".join(out)


def fetch_comments(ticket_id: str, img_dir: Path,
                   existing_img_count: int) -> tuple[str, dict]:
    data, status = azdo_get(
        f"wit/workItems/{ticket_id}/comments?api-version=7.0-preview.3&$top=100"
    )
    if status != 200 or not data:
        return "", {}

    comments = data.get("comments", [])
    if not comments:
        return "", {}

    html_texts = [c.get("text", "") or "" for c in comments]
    img_map = download_images(html_texts, img_dir,
                              prefix="comment-", counter_start=existing_img_count + 1)

    out = ["# Discussion", ""]
    for c in comments:
        author  = (c.get("createdBy") or {}).get("displayName", "?")
        date    = c.get("createdDate", "")[:10]
        edited  = c.get("modifiedDate", "")[:10]
        version = c.get("version", 1)
        out.append(f"### {author} — {date}" +
                   (f" *(edited {edited})*" if edited != date and version > 1 else ""))
        out.append("")
        content = strip_html(c.get("text", ""), img_map)
        if content:
            out.append(content)
        out.append("")

    return "\n".join(out), img_map


def fetch_prs(ticket_id: str, rels: list) -> str:
    prs_found = {}

    for rel in rels:
        if rel.get("rel") != "ArtifactLink":
            continue
        url = rel.get("url", "")
        if "PullRequestId" in url:
            parts = url.rstrip("/").split("/")
            pr_id = parts[-1]
            try:
                raw, _ = az_run("repos", "pr", "show", "--id", pr_id, "-o", "json")
                if raw:
                    pr = json.loads(raw)
                    prs_found[pr_id] = pr
            except Exception:
                pass

    try:
        raw, _ = az_run("repos", "pr", "list", "--status", "all",
                        "--query", f"[?contains(sourceRefName, '{ticket_id}')]",
                        "-o", "json", timeout=20)
        if raw:
            for pr in json.loads(raw):
                pid = str(pr.get("pullRequestId", ""))
                if pid and pid not in prs_found:
                    prs_found[pid] = pr
    except Exception:
        pass

    if not prs_found:
        return ""

    out = ["# Pull Requests", ""]
    for pid, pr in sorted(prs_found.items(), key=lambda x: int(x[0]) if x[0].isdigit() else 0, reverse=True):
        out.append(f"## PR #{pid} — {pr.get('title','')}")
        out.append("")
        out.append(f"**Status:** {pr.get('status','')}  |  **Created by:** {(pr.get('createdBy') or {}).get('displayName','?')}")
        source = pr.get("sourceRefName", "").replace("refs/heads/", "")
        target = pr.get("targetRefName", "").replace("refs/heads/", "")
        out.append(f"**Branch:** `{source}` → `{target}`")
        created = (pr.get("creationDate") or "")[:10]
        closed  = (pr.get("closedDate") or "")[:10]
        if created:
            out.append(f"**Created:** {created}" + (f"  |  **Closed:** {closed}" if closed else ""))
        desc = (pr.get("description") or "").strip()
        if desc:
            out.append("")
            out.append(desc[:600])
        out.append("")

        reviewers = pr.get("reviewers") or []
        if reviewers:
            out.append("**Reviewers:**")
            for rv in reviewers:
                vote_map = {10: "✅ Approved", 5: "✅ Approved (suggestions)", 0: "⏳ Pending",
                            -5: "⏳ Waiting", -10: "❌ Rejected"}
                vote = vote_map.get(rv.get("vote", 0), "⏳")
                out.append(f"- {rv.get('displayName','?')} — {vote}")
            out.append("")

        out.append("---")
        out.append("")

    return "\n".join(out)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("Usage: fetch-ticket.py <ticket-id>", file=sys.stderr)
        sys.exit(1)

    ticket_id = sys.argv[1].lstrip("#").strip()
    print(f"[ticket] Fetching ab#{ticket_id}...", file=sys.stderr)

    wi = fetch_wi(ticket_id)
    if not wi:
        print(f"ERROR: Could not fetch work item {ticket_id}", file=sys.stderr)
        sys.exit(1)

    f    = wi.get("fields", {})
    rels = wi.get("relations") or []
    title = f.get("System.Title", "no-title")

    folder_name = f"{ticket_id}-{slugify(title)}"
    ticket_dir  = TICKETS / folder_name
    img_dir     = ticket_dir / "images"
    linked_dir  = ticket_dir / "linked"
    ticket_dir.mkdir(parents=True, exist_ok=True)
    img_dir.mkdir(exist_ok=True)
    linked_dir.mkdir(exist_ok=True)

    print("[ticket] Downloading images...", file=sys.stderr)
    all_html = [f.get(k, "") or "" for k, _ in CUSTOM_FIELDS]
    all_html += [f.get("System.Description","") or "",
                 f.get("Microsoft.VSTS.TCM.ReproSteps","") or "",
                 f.get("Microsoft.VSTS.Common.AcceptanceCriteria","") or ""]
    img_map = download_images(all_html, img_dir)
    n_imgs  = sum(1 for v in img_map.values() if v)
    print(f"[ticket] {n_imgs} image(s) downloaded.", file=sys.stderr)

    ticket_md = build_ticket_md(wi, img_map)
    (ticket_dir / "ticket.md").write_text(ticket_md, encoding="utf-8")

    parent_id = f.get("System.Parent", "")
    children  = []
    related   = []
    for rel in rels:
        rel_type = rel.get("rel", "")
        rel_id   = rel.get("url", "").rsplit("/", 1)[-1]
        if rel_type == "System.LinkTypes.Hierarchy-Forward":
            children.append(rel_id)
        elif rel_type == "System.LinkTypes.Related":
            related.append(rel_id)

    linked_ids = {}
    if parent_id:
        linked_ids[str(parent_id)] = "parent"
    for cid in children:
        linked_ids[cid] = "child"
    for rid in related:
        linked_ids[rid] = "related"

    written_linked = []
    for lid, ltype in linked_ids.items():
        print(f"[ticket] Fetching linked ab#{lid} ({ltype})...", file=sys.stderr)
        lwi = fetch_wi(lid)
        if not lwi:
            continue
        lf        = lwi.get("fields", {})
        ltitle    = lf.get("System.Title", "no-title")
        lfilename = f"{lid}-{ltype}-{slugify(ltitle)}.md"
        lmd       = build_linked_md(lwi, ltype)
        (linked_dir / lfilename).write_text(lmd, encoding="utf-8")
        written_linked.append((lid, ltype, ltitle, linked_dir / lfilename))

    print("[ticket] Searching for PRs...", file=sys.stderr)
    prs_md = fetch_prs(ticket_id, rels)
    if prs_md:
        (ticket_dir / "prs.md").write_text(prs_md, encoding="utf-8")

    print("[ticket] Fetching discussion comments...", file=sys.stderr)
    comments_md, comment_img_map = fetch_comments(ticket_id, img_dir, n_imgs)
    if comments_md:
        (ticket_dir / "comments.md").write_text(comments_md, encoding="utf-8")
    n_comment_imgs = sum(1 for v in comment_img_map.values() if v)
    if n_comment_imgs:
        print(f"[ticket] {n_comment_imgs} comment image(s) downloaded.", file=sys.stderr)

    all_img_map = {**img_map, **{k: v for k, v in comment_img_map.items() if v}}
    total_imgs  = sum(1 for v in all_img_map.values() if v)

    out = []
    out.append(f"# Ticket workspace created: ab#{ticket_id}")
    out.append("")
    out.append(f"**Folder:** `{ticket_dir}`")
    out.append("")
    out.append("## Files to read")
    out.append("")
    idx = 1
    out.append(f"{idx}. `{ticket_dir / 'ticket.md'}` — full ticket details")
    for lid, ltype, ltitle, lpath in written_linked:
        idx += 1
        out.append(f"{idx}. `{lpath}` — ab#{lid} ({ltype}): {ltitle}")
    if prs_md:
        idx += 1
        out.append(f"{idx}. `{ticket_dir / 'prs.md'}` — pull requests")
    if comments_md:
        idx += 1
        out.append(f"{idx}. `{ticket_dir / 'comments.md'}` — discussion comments")

    if total_imgs > 0:
        out.append("")
        out.append(f"## Images ({total_imgs} total — read each to see mockups/screenshots)")
        out.append("")
        for url, path in all_img_map.items():
            if path:
                label = "comment" if "comment-" in path.name else "ticket"
                out.append(f"- `{path}` [{label}]")

    out.append("")
    out.append("---")
    out.append("")
    out.append("Read ALL files listed above before building the implementation plan.")

    print("\n".join(out))


if __name__ == "__main__":
    main()

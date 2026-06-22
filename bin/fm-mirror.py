#!/usr/bin/env python3
"""Mirror a person-assigned fmw work item out to the project's external tracker.

The fmw store is firstmate-internal. When a work item is assigned to a real team member
(not the captain, not a crewmate), it must also appear where that person works — Azure
DevOps Boards for `+ado` projects, GitHub Issues for GitHub projects — so the assignee can
actually see it (captain preference, data/captain.md).

Idempotent: records the created item's URL in the fmw issue's `external` field and skips if
already set. Captain-assigned and unassigned items stay local. Best-effort identity from
people.yaml (ADO uses the netcompany email; GitHub uses a `github` alias if present).

Usage: fm-mirror.py <issue-id> <repo-path> [--dry-run] [--type <ADO work-item type>]
"""
import argparse
import json
import os
import re
import subprocess
import sys
from typing import NoReturn

import yaml

FM_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PEOPLE = os.environ.get("FM_PEOPLE", os.path.expanduser("~/workspace/people.yaml"))
FMW = os.path.join(FM_ROOT, "bin", "fm-work.sh")


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def die(msg, code=1) -> NoReturn:
    print(f"fm-mirror: {msg}", file=sys.stderr)
    sys.exit(code)


def store_for(repo_path):
    d = os.path.abspath(repo_path)
    while True:
        cand = os.path.join(d, ".work", "issues.jsonl")
        if os.path.exists(cand):
            return cand
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def load_people():
    if not os.path.exists(PEOPLE):
        die(f"no people.yaml at {PEOPLE}")
    return yaml.safe_load(open(PEOPLE)) or {}


def captain_id(people):
    email = sh(["git", "config", "user.email"]).stdout.strip().lower()
    for e in people.get("engineers", []):
        emails = [x.lower() for x in (e.get("aliases", {}).get("git_emails") or [])]
        if email and email in emails:
            return e["id"]
    return "estavrop"


def find_person(people, pid):
    for e in people.get("engineers", []):
        if e.get("id") == pid:
            return e
    return None


def ado_candidates(p):
    """Identity values to try for ADO --assigned-to, best first. Client ADO orgs (e.g. IPTO)
    are picky and use client-tenant accounts that may differ from the Netcompany email, and
    the exact email casing / display-name ordering matters — so try each until one resolves,
    then fall back to unassigned. Add an explicit `ado:` alias in people.yaml to pin it."""
    al = p.get("aliases", {}) or {}
    out = list(al.get("ado") or [])
    out += list(al.get("git_emails") or [])
    if p.get("name"):
        out.append(p["name"])
    seen, uniq = set(), []
    for c in out:
        if c and c not in seen:
            seen.add(c)
            uniq.append(c)
    return uniq


def github_handle(p):
    al = p.get("aliases", {}) or {}
    if al.get("github"):
        return al["github"][0]
    for e in al.get("git_emails") or []:
        m = re.match(r"\d+\+([^@]+)@users\.noreply\.github\.com", e)
        if m:
            return m.group(1)
    return None


def origin_url(repo):
    return sh(["git", "-C", repo, "remote", "get-url", "origin"]).stdout.strip()


def ado_org_project(repo):
    url = origin_url(repo)
    m = re.search(r"dev\.azure\.com/([^/]+)/([^/]+)/_git/", url)
    if m:
        return f"https://dev.azure.com/{m.group(1)}", m.group(1), m.group(2)
    die(f"cannot parse ADO org/project from origin: {url}")


def gh_owner_repo(repo):
    url = origin_url(repo)
    m = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$", url)
    return m.group(1) if m else None


def read_pat(org_url):
    out = sh(["git", "credential", "fill"], input=f"url={org_url}\n\n")
    for line in out.stdout.splitlines():
        if line.startswith("password="):
            return line[len("password="):].strip()
    return os.environ.get("AZURE_DEVOPS_EXT_PAT")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("issue_id")
    ap.add_argument("repo_path")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true",
                    help="mirror even a captain-assigned item (captain.md's 'unless asked' exception)")
    ap.add_argument("--type", default="Task", help="ADO work-item type (default Task)")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo_path)
    if not os.path.isdir(repo):
        die(f"repo path not found: {repo}")
    store = store_for(repo)
    if not store:
        die(f"no .work store found from {repo}")

    out = sh([FMW, "show", args.issue_id, "--store", store, "--json"])
    if out.returncode != 0:
        die(f"no work item '{args.issue_id}' in {store}")
    issue = json.loads(out.stdout)

    assignee = issue.get("assignee")
    people = load_people()
    cap = captain_id(people)

    # --- guards: only person-assigned, not-yet-mirrored work mirrors out ---
    if not assignee:
        print(f"{args.issue_id}: no assignee — nothing to mirror")
        return
    if assignee == cap and not args.force:
        print(f"{args.issue_id}: assigned to the captain ({cap}) — stays local (use --force to mirror anyway)")
        return
    person = find_person(people, assignee)
    if person is None:
        print(f"fm-mirror: assignee '{assignee}' is not in people.yaml — not mirroring "
              f"(add them, or it may be a crewmate/bot)", file=sys.stderr)
        return
    if issue.get("external"):
        print(f"{args.issue_id}: already mirrored -> {issue['external']}")
        return

    forge = sh([os.path.join(FM_ROOT, "bin", "fm-forge.sh"), os.path.basename(repo)]).stdout.strip()
    title = issue.get("title", "")
    body = (issue.get("body") or "") + f"\n\n(firstmate work item {args.issue_id}; assignee {assignee})"

    url = None
    if forge == "ado":
        org_url, org, project = ado_org_project(repo)
        candidates = ado_candidates(person)
        base = ["az", "boards", "work-item", "create", "--type", args.type,
                "--title", title, "--org", org_url, "--project", project,
                "--description", body, "-o", "json"]
        if args.dry_run:
            print(f"DRY-RUN [ado] would create in {org}/{project}; try assignee {candidates or '<unassigned>'}:")
            print("  " + " ".join(f'"{c}"' if " " in c else c for c in base))
            return
        pat = read_pat(org_url)
        if not pat:
            die(f"no PAT in git credential helper for {org_url}")
        env = dict(os.environ, AZURE_DEVOPS_EXT_PAT=pat)
        # Try each identity candidate until ADO accepts one (a rejected --assigned-to fails the
        # create without making anything, so retrying is safe); fall back to unassigned.
        r, assigned = None, None
        for ident in candidates:
            r = sh(base + ["--assigned-to", ident], env=env)
            if r.returncode == 0:
                assigned = ident
                break
            if not re.search(r"unknown identity|Assigned To", r.stderr or ""):
                die(f"az boards create failed: {r.stderr.strip()[:300]}")  # a real error, not identity
        if assigned is None:
            if candidates:
                print(f"fm-mirror: ADO recognized none of {candidates} in {org} — creating unassigned; "
                      f"set the assignee in ADO or add an `ado:` alias to people.yaml", file=sys.stderr)
            r = sh(base, env=env)
            if r.returncode != 0:
                die(f"az boards create failed: {r.stderr.strip()[:300]}")
        assert r is not None  # set by the candidate loop or the unassigned fallback above
        wid = json.loads(r.stdout).get("id")
        url = f"{org_url}/{project}/_workitems/edit/{wid}"
        if assigned:
            print(f"  (assigned in ADO to: {assigned})")
    else:  # github
        ownerrepo = gh_owner_repo(repo)
        if not ownerrepo:
            die(f"cannot parse GitHub owner/repo from origin of {repo}")
        handle = github_handle(person)
        cmd = ["gh", "issue", "create", "--repo", ownerrepo, "--title", title, "--body", body]
        if handle:
            cmd += ["--assignee", handle]
        else:
            print(f"fm-mirror: no GitHub handle for {assignee} — creating unassigned", file=sys.stderr)
        if args.dry_run:
            print(f"DRY-RUN [github] would create in {ownerrepo}, assignee={handle}:")
            print("  " + " ".join(f'"{c}"' if " " in c else c for c in cmd))
            return
        r = sh(cmd)
        if r.returncode != 0:
            die(f"gh issue create failed: {r.stderr.strip()[:300]}")
        url = r.stdout.strip().splitlines()[-1]

    sh([FMW, "update", args.issue_id, "--store", store, "--external", url])
    print(f"mirrored {args.issue_id} -> {url}  (assignee {assignee}, forge {forge})")


if __name__ == "__main__":
    main()

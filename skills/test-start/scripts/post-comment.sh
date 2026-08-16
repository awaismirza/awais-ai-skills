#!/usr/bin/env bash
# Post (or edit) a comment on an Azure DevOps work item (occhealth/MOHR).
# The comment body is read from a file and sent as-is (HTML supported).
# Comments are authored by the AZURE_DEVOPS_PAT owner (the user).
#
# Usage:
#   post-comment.sh <workItemId> <htmlFile>              # create new comment
#   post-comment.sh <workItemId> <htmlFile> <commentId>  # edit existing comment
set -euo pipefail
ID="${1:?workItemId required}"
HTMLFILE="${2:?html/body file required}"
COMMENT_ID="${3:-}"
ORG="${ADO_ORG:-occhealth}"; PROJECT="${ADO_PROJECT:-MOHR}"
: "${AZURE_DEVOPS_PAT:?AZURE_DEVOPS_PAT not set}"
BASE="https://dev.azure.com/${ORG}/${PROJECT}/_apis/wit"

PAYLOAD=$(python3 -c "import sys,json;print(json.dumps({'text':open(sys.argv[1]).read()}))" "$HTMLFILE")

if [[ -n "$COMMENT_ID" ]]; then
  curl -fsS -u ":$AZURE_DEVOPS_PAT" -X PATCH \
    "${BASE}/workItems/${ID}/comments/${COMMENT_ID}?api-version=7.1-preview.4" \
    -H "Content-Type: application/json" -d "$PAYLOAD" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print('updated comment',d.get('id'),'on work item',$ID)"
else
  curl -fsS -u ":$AZURE_DEVOPS_PAT" -X POST \
    "${BASE}/workItems/${ID}/comments?api-version=7.1-preview.4" \
    -H "Content-Type: application/json" -d "$PAYLOAD" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print('posted comment',d.get('id'),'on work item',$ID)"
fi

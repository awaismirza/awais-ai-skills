#!/usr/bin/env bash
# Upload a file to Azure DevOps (occhealth/MOHR) as a work-item attachment and
# print the attachment URL (for embedding in a comment via <img src="...">).
# Usage: upload-attachment.sh <imagePath>
set -euo pipefail
IMG="${1:?usage: upload-attachment.sh <imagePath>}"
[[ -s "$IMG" ]] || { echo "image not found/empty: $IMG" >&2; exit 1; }
ORG="${ADO_ORG:-occhealth}"; PROJECT="${ADO_PROJECT:-MOHR}"
: "${AZURE_DEVOPS_PAT:?AZURE_DEVOPS_PAT not set}"
FNAME=$(basename "$IMG")
curl -fsS -u ":$AZURE_DEVOPS_PAT" -X POST \
  "https://dev.azure.com/${ORG}/${PROJECT}/_apis/wit/attachments?fileName=${FNAME}&api-version=7.1" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$IMG" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['url'])"

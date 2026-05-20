#!/bin/bash
# ---------------------------------------------------------------------
# sharepoint-sync.sh
# Pulls files from a SharePoint folder via Microsoft Graph and commits
# them to this GitLab project via the Repository Files API.
#
# All configuration comes from environment variables (GitLab CI/CD vars).
#
# Required (set in Settings > CI/CD > Variables — mask + protect secrets,
# leave "Expand variable reference" enabled):
#   AzureAppTentantName       Entra tenant ID
#   AzureAppClientId       App registration client ID
#   AzureAppClientSecret   App registration secret    (masked, protected)
#   SharepointSitePath       e.g. contoso.sharepoint.com:/sites/MySite
#   GitlabToken    PAT or project access token with api+write_repository
#                   (masked, protected)
#
# Supplied by .gitlab-ci.yml (with reference expansion):
#   TARGET_FOLDER, GITLAB_TARGET_DIR, BRANCH,
#   GITLAB_API, PROJECT_ID,
#   GRAPH_TOKEN_URL, GRAPH_DRIVE_URL
# ---------------------------------------------------------------------

set -euo pipefail

# Fail fast if any required secret is missing
: "${AzureAppTentantName:?Missing AzureAppTentantName}"
: "${AzureAppClientId:?Missing AzureAppClientId}"
: "${AzureAppClientSecret:?Missing AzureAppClientSecret}"
: "${SharepointSitePath:?Missing SharepointSitePath}"
: "${GitlabToken:?Missing GitlabToken}"

# --- 1. Auth with Microsoft Graph ---
echo "Authenticating with Microsoft Graph..."
TOKEN_RESPONSE=$(curl -s -X POST "$GRAPH_TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=$AzureAppClientId" \
  -d "client_secret=$AzureAppClientSecret" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "grant_type=client_credentials")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
if [ "$ACCESS_TOKEN" = "null" ] || [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ Graph API Authentication failed."
    echo "$TOKEN_RESPONSE" | jq -r '.error_description // .error // .'
    exit 1
fi

# --- 2. Get Drive ID ---
DRIVE_ID=$(curl -s -X GET "$GRAPH_DRIVE_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" | jq -r '.id')

if [ "$DRIVE_ID" = "null" ] || [ -z "$DRIVE_ID" ]; then
    echo "❌ Could not resolve drive ID for site: $SharepointSitePath"
    exit 1
fi

# --- 3. Get Folder Contents ---
echo "Fetching contents of SharePoint folder: $TARGET_FOLDER..."
CHILDREN_ENDPOINT="https://graph.microsoft.com/v1.0/drives/$DRIVE_ID/root:/$TARGET_FOLDER:/children"
CHILDREN_RESPONSE=$(curl -s -X GET "$CHILDREN_ENDPOINT" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
echo "---------------------------------------------------"

# --- 4. Loop and commit every file to GitLab ---
# select(.folder == null) → files only, skip subfolders
echo "$CHILDREN_RESPONSE" | jq -c '.value[] | select(.folder == null)' | while read -r item; do

    ITEM_NAME=$(echo "$item" | jq -r '.name')
    DOWNLOAD_URL=$(echo "$item" | jq -r '."@microsoft.graph.downloadUrl"')
    echo "🚀 Processing: $ITEM_NAME"

    # Always strip HTML and rewrite the name to <basename>.txt
    COMMIT_NAME="${ITEM_NAME%.*}.txt"
    echo "   📝 Stripping HTML → $COMMIT_NAME"
    CONTENT_BASE64=$(curl -sL "$DOWNLOAD_URL" \
        | pandoc -f html -t plain \
        | base64 -w0)

    RAW_PATH="${GITLAB_TARGET_DIR}/${COMMIT_NAME}"
    ENCODED_FILE_PATH=$(jq -nr --arg v "$RAW_PATH" '$v|@uri')
    COMMIT_MSG="Auto-commit: Syncing $COMMIT_NAME from SharePoint"

    PAYLOAD=$(jq -n \
        --arg branch  "$BRANCH" \
        --arg content "$CONTENT_BASE64" \
        --arg msg     "$COMMIT_MSG" \
        '{branch: $branch, content: $content, commit_message: $msg, encoding: "base64"}')

    # Try to CREATE the file
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
      "${GITLAB_API}/projects/${PROJECT_ID}/repository/files/${ENCODED_FILE_PATH}" \
      -H "PRIVATE-TOKEN: ${GitlabToken}" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD")

    if [ "$response" -eq 201 ]; then
        echo "   ✅ File created in GitLab."
    elif [ "$response" -eq 400 ] || [ "$response" -eq 422 ]; then
        # File likely exists — fall back to PUT (update)
        put_response=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
          "${GITLAB_API}/projects/${PROJECT_ID}/repository/files/${ENCODED_FILE_PATH}" \
          -H "PRIVATE-TOKEN: ${GitlabToken}" \
          -H "Content-Type: application/json" \
          -d "$PAYLOAD")

        if [ "$put_response" -eq 200 ]; then
            echo "   🔄 File updated in GitLab."
        else
            echo "   ❌ Failed to update file. HTTP Code: $put_response"
        fi
    else
        echo "   ❌ Unexpected response creating file: $response"
    fi
done

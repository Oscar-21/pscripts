#!/bin/bash

echo "--- Failing call (children) ---"
curl -v -o /dev/null \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "$CHILDREN_ENDPOINT" 2>&1 | grep -E '^(\*|<|>)' | head -25
# ---------------------------------------------------------------------
# sharepoint-sync.sh
# Pulls files from a SharePoint folder via Microsoft Graph and commits
# them to this GitLab project via the Repository Files API.
#
# All configuration comes from environment variables (GitLab CI/CD vars).
#
# Required (set in Settings > CI/CD > Variables — mask + protect secrets,
# leave "Expand variable reference" enabled):
#   AzureAppTentantName       Entra tenant ID# 0.
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
: "${AzureCertPFX:?Missing AzureCertPFX}"
: "${AzureCertPFXPassword:?Missing AzureCertPFXPassword}"

# 0.

TENANT_ID="${AzureAppTentantName}"
CLIENT_ID="${AzureAppClientId}"

AUTHORITY="https://login.microsoftonline.com"   # was login.microsoftonline.us
GRAPH_HOST="https://graph.microsoft.com"        # was graph.microsoft.us
SCOPE="${GRAPH_HOST}/.default"                  # resolves to https://graph.microsoft.com/.default


# ===== Helper: base64url (no padding) =====
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

cat "$AzureCertPFX" | base64 -d > cert.pfx
openssl pkcs12 -in cert.pfx -clcerts -nokeys -passin "pass:$AzureCertPFXPassword" -out cert.pem
openssl pkcs12 -in cert.pfx -nocerts -nodes  -passin "pass:$AzureCertPFXPassword" -out key.pem

CERT_FILE="./cert.pem"   # or "$GRAPH_CERT" in CI
KEY_FILE="./key.pem"    # or "$GRAPH_KEY"  in CI


# SHA1 thumbprint of the cert, raw bytes, base64url-encoded -> x5t header value
THUMBPRINT_B64URL=$(openssl x509 -in "$CERT_FILE" -fingerprint -sha1 -noout \
  | sed 's/^.*=//; s/://g' \
  | xxd -r -p \
  | b64url)


NOW=$(date +%s)
EXP=$((NOW + 600))   # 10-minute lifetime; max allowed is 24h
JTI=$(uuidgen)

HEADER=$(printf '{"alg":"RS256","typ":"JWT","x5t":"%s"}' "$THUMBPRINT_B64URL")
PAYLOAD=$(printf '{"aud":"%s/%s/oauth2/v2.0/token","iss":"%s","sub":"%s","jti":"%s","nbf":%d,"exp":%d}' \
  "$AUTHORITY" "$TENANT_ID" "$CLIENT_ID" "$CLIENT_ID" "$JTI" "$NOW" "$EXP")

HEADER_B64=$(printf '%s' "$HEADER"  | b64url)
PAYLOAD_B64=$(printf '%s' "$PAYLOAD" | b64url)

SIGNING_INPUT="${HEADER_B64}.${PAYLOAD_B64}"
SIGNATURE=$(printf '%s' "$SIGNING_INPUT" \
  | openssl dgst -sha256 -sign "$KEY_FILE" \
  | b64url)

CLIENT_ASSERTION="${SIGNING_INPUT}.${SIGNATURE}"


# --- 1. Auth with Microsoft Graph ---
echo "Authenticating with Microsoft Graph..."
TOKEN_RESPONSE=$(curl -sS -X POST \
  "${AUTHORITY}/${TENANT_ID}/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "client_id=$AzureAppClientId" \
  --data-urlencode "scope=${SCOPE}" \
  --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  --data-urlencode "client_assertion=${CLIENT_ASSERTION}" \
  --data-urlencode "grant_type=client_credentials")

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

##### New
# Capture body and HTTP status separately
HTTP_CODE=$(curl -sS -X GET "$CHILDREN_ENDPOINT" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Accept: application/json" \
    -o /tmp/children.json \
    -w "%{http_code}")

CURL_EXIT=$?

# 1. Did curl itself fail (DNS, TLS, connection refused, etc.)?
if [[ $CURL_EXIT -ne 0 ]]; then
    echo "ERROR: curl failed with exit code $CURL_EXIT calling $CHILDREN_ENDPOINT" >&2
    exit 1
fi

# 2. Did the server return a non-2xx status?
if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
    echo "ERROR: Graph returned HTTP $HTTP_CODE for $CHILDREN_ENDPOINT" >&2
    # Graph error bodies are JSON like {"error":{"code":"...","message":"..."}}
    jq -r '.error | "  code:    \(.code)\n  message: \(.message)"' /tmp/children.json 2>/dev/null \
        || cat /tmp/children.json >&2
    exit 1
fi

CHILDREN_RESPONSE=$(cat /tmp/children.json)
rm -f /tmp/children.json

# 3. Sanity check that the body has the shape we expect
if ! echo "$CHILDREN_RESPONSE" | jq -e 'has("value")' >/dev/null; then
    echo "ERROR: response missing '.value' array" >&2
    echo "$CHILDREN_RESPONSE" >&2
    exit 1
fi

##### New

### Old
CHILDREN_RESPONSE=$(curl -s -X GET "$CHILDREN_ENDPOINT" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
### Old
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

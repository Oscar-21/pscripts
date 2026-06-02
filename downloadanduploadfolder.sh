#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
GITLAB_API_URL="https://gitlab.com/api/v4" # Change if using self-hosted GitLab
PROJECT_ID="12345678"                      # Your project ID (or use $CI_PROJECT_ID in a runner)
TOKEN="your_access_token"                  # Use a variable like $GIT_PUSH_TOKEN in CI
SOURCE_BRANCH="main"
NEW_BRANCH="feature/upload-new-folder"
SOURCE_FOLDER="path/to/source/folder"      # The folder you want to download
DEST_FOLDER="path/to/destination/folder"   # Where it should go on the new branch

# --- 2. DOWNLOAD THE FOLDER ---
echo "Downloading '$SOURCE_FOLDER' from '$SOURCE_BRANCH'..."
# The archive endpoint lets us download specific paths.
curl --silent --show-error --fail --header "PRIVATE-TOKEN: $TOKEN" \
  "${GITLAB_API_URL}/projects/${PROJECT_ID}/repository/archive.tar.gz?sha=${SOURCE_BRANCH}&path=${SOURCE_FOLDER}" \
  --output archive.tar.gz

# Extract the archive. 
# GitLab archives have a root folder named after the project/commit. We strip it so we just get the files.
mkdir -p extracted_files
tar -xzf archive.tar.gz -C extracted_files --strip-components=1


# --- 3. CHECK AND CREATE THE NEW BRANCH ---
echo "Checking if branch '$NEW_BRANCH' exists..."

# GitLab API requires branch names with slashes (e.g., feature/upload) to be URL-encoded.
# This pure bash string manipulation replaces all '/' with '%2F'.
ENCODED_BRANCH="${NEW_BRANCH//\//%2F}"

# Check the branch endpoint and capture ONLY the HTTP status code
HTTP_STATUS=$(curl --silent --output /dev/null --write-out "%{http_code}" \
  --header "PRIVATE-TOKEN: $TOKEN" \
  "${GITLAB_API_URL}/projects/${PROJECT_ID}/repository/branches/${ENCODED_BRANCH}")

if [ "$HTTP_STATUS" -eq 200 ]; then
  echo "Branch '$NEW_BRANCH' already exists. We will commit to the existing branch."
  
elif [ "$HTTP_STATUS" -eq 404 ]; then
  echo "Branch '$NEW_BRANCH' does not exist. Creating it from '$SOURCE_BRANCH'..."
  
  curl --silent --show-error --fail --request POST --header "PRIVATE-TOKEN: $TOKEN" \
    "${GITLAB_API_URL}/projects/${PROJECT_ID}/repository/branches?branch=${NEW_BRANCH}&ref=${SOURCE_BRANCH}" > /dev/null
    
else
  echo "Failed to check branch status. GitLab API returned HTTP $HTTP_STATUS."
  exit 1
fi


# --- 4. PREPARE THE COMMIT PAYLOAD USING JQ ---
echo "Preparing commit payload..."
# We start with an empty JSON array for our commit actions
ACTIONS_JSON="[]"

# Loop through every file in the extracted folder
find extracted_files -type f | while read -r FILE_PATH; do
  
  # Remove the 'extracted_files/path/to/source/folder/' prefix to get the relative filename
  # and append it to our new destination folder path
  RELATIVE_FILE_PATH="${FILE_PATH#extracted_files/${SOURCE_FOLDER}/}"
  NEW_FILE_PATH="${DEST_FOLDER}/${RELATIVE_FILE_PATH}"

  # Read the file and encode it in base64. 
  # Base64 is highly recommended via the API to prevent JSON formatting breaks with special characters.
  FILE_CONTENT=$(base64 -w 0 "$FILE_PATH")

  # Use jq to append a new action object to our array
  ACTIONS_JSON=$(echo "$ACTIONS_JSON" | jq --arg path "$NEW_FILE_PATH" --arg content "$FILE_CONTENT" \
    '. += [{
      "action": "create", 
      "file_path": $path, 
      "content": $content, 
      "encoding": "base64"
    }]')
    
  # Export it so the outer script can read the updated variable from the while loop subshell
  export ACTIONS_JSON
done

# Build the final JSON payload wrapper for the Commits API
PAYLOAD=$(jq --null-input \
  --arg branch "$NEW_BRANCH" \
  --arg msg "feat: add folder via API" \
  --argjson actions "$ACTIONS_JSON" \
  '{
    "branch": $branch,
    "commit_message": $msg,
    "actions": $actions
  }')

# --- 5. UPLOAD (COMMIT) THE FILES ---
echo "Committing files to the new branch..."
curl --silent --show-error --fail --request POST --header "PRIVATE-TOKEN: $TOKEN" \
  --header "Content-Type: application/json" \
  --data "$PAYLOAD" \
  "${GITLAB_API_URL}/projects/${PROJECT_ID}/repository/commits" > /dev/null

echo "Success! Folder uploaded to $NEW_BRANCH."

# Cleanup
rm -rf archive.tar.gz extracted_files

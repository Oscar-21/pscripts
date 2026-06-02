param(
  [Parameter(Mandatory=$true, HelpMessage="Entra App Client Id")]
  [String]$AppId,

  [Parameter(Mandatory=$true, HelpMessage="Entra App Name (used for naming the scope group and policy)")]
  [String]$AppName,

  [Parameter(Mandatory=$true, HelpMessage="Email address of the shared mailbox to restrict access to")]
  [String]$SharedMailboxEmailAddress
)
# Note: ObjId is not needed for Application Access Policies — AAPs reference the app
# by AppId only. New-ServicePrincipal has no AAP equivalent.

Connect-ExchangeOnline

$Shared = Get-Mailbox $SharedMailboxEmailAddress
if (-not $Shared) { throw "Shared mailbox $SharedMailboxEmailAddress not found" }

# 1. Create a mail-enabled security group that defines the policy scope.
#    The shared mailbox is added as a member; the AAP will restrict the app
#    to only mailboxes in this group.
$SafeName    = ($AppName -replace '[^A-Za-z0-9]','')
$GroupName   = "AAP-Scope-$SafeName"
$GroupAlias  = "aap-scope-$($SafeName.ToLower())"
$Domain      = $Shared.PrimarySmtpAddress.Split('@')[1]
$GroupEmail  = "$GroupAlias@$Domain"

$Group = New-DistributionGroup `
    -Name $GroupName `
    -DisplayName $GroupName `
    -Alias $GroupAlias `
    -PrimarySmtpAddress $GroupEmail `
    -Type "Security" `
    -Members @($Shared.PrimarySmtpAddress)

# 2. Hide it from the GAL — it's a control-plane object, not a real DL
Set-DistributionGroup -Identity $Group.Identity -HiddenFromAddressListsEnabled $true

# 3. Create the Application Access Policy (RestrictAccess = allow only this group)
New-ApplicationAccessPolicy `
    -AppId $AppId `
    -PolicyScopeGroupId $GroupEmail `
    -AccessRight RestrictAccess `
    -Description "Restrict $AppName access to members of $GroupName"

# 4. Verify the policy applies as expected
Test-ApplicationAccessPolicy -Identity $SharedMailboxEmailAddress -AppId $AppId
# Output should show AccessCheckResult : Granted

# Sanity check the inverse — another mailbox should be denied
# Test-ApplicationAccessPolicy -Identity another.user@contoso.com -AppId $AppId
# AccessCheckResult should be Denied


### NEW
#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
GITLAB_API_URL="https://gitlab.com/api/v4" # Change if using self-hosted GitLab
PROJECT_ID="12345678"                      # Your project ID
TOKEN="your_access_token"                  # Your project access token
SOURCE_BRANCH="main"
SOURCE_FOLDER="path/to/source/folder"      # The folder you want to download
ISSUE_TITLE="Automated Folder Extraction: $SOURCE_FOLDER"

# --- 2. DOWNLOAD THE FOLDER ---
echo "Downloading '$SOURCE_FOLDER' from '$SOURCE_BRANCH'..."

# Download the specific folder as a tar.gz archive
curl --silent --show-error --fail --header "PRIVATE-TOKEN: $TOKEN" \
  "${GITLAB_API_URL}/projects/${PROJECT_ID}/repository/archive.tar.gz?sha=${SOURCE_BRANCH}&path=${SOURCE_FOLDER}" \
  --output archive.tar.gz

# --- 3. UPLOAD THE ARCHIVE TO GITLAB ---
echo "Uploading archive to project..."

# The Uploads API accepts multipart/form-data. 
# It responds with a JSON object containing a pre-formatted 'markdown' string.
UPLOAD_RESPONSE=$(curl --silent --show-error --fail --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --form "file=@archive.tar.gz" \
  "${GITLAB_API_URL}/projects/${PROJECT_ID}/uploads")

# Extract the markdown string (e.g., "[archive.tar.gz](/uploads/12345/archive.tar.gz)")
MARKDOWN_LINK=$(echo "$UPLOAD_RESPONSE" | jq -r '.markdown')

# --- 4. CREATE THE ISSUE WITH THE ATTACHMENT ---
echo "Creating issue..."

# Draft the issue description, injecting the markdown link we just generated
ISSUE_DESCRIPTION="An automated process has packaged the \`${SOURCE_FOLDER}\` folder from the \`${SOURCE_BRANCH}\` branch.

**Download the archive here:** ${MARKDOWN_LINK}

_This issue was generated automatically by a script._"

# Build the JSON payload safely using jq to prevent quotes/newlines from breaking the JSON
PAYLOAD=$(jq --null-input \
  --arg title "$ISSUE_TITLE" \
  --arg desc "$ISSUE_DESCRIPTION" \
  '{
    "title": $title,
    "description": $desc,
    "labels": "automated, archive"
  }')

# Send the POST request to the Issues API
ISSUE_RESPONSE=$(curl --silent --show-error --fail --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --header "Content-Type: application/json" \
  --data "$PAYLOAD" \
  "${GITLAB_API_URL}/projects/${PROJECT_ID}/issues")

# Extract the web URL of the new issue so we can print it to the terminal
ISSUE_URL=$(echo "$ISSUE_RESPONSE" | jq -r '.web_url')

echo "Success! Issue created with the attached folder."
echo "View it here: $ISSUE_URL"

# Cleanup
rm archive.tar.gz

### NEW

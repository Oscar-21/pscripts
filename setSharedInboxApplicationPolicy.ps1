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
TARGET_BRANCH="feature/expected-branch"    # The branch you want to check for

# --- 2. CHECK IF THE BRANCH EXISTS ---
echo "Checking if branch '$TARGET_BRANCH' exists..."

# URL-encode the branch name (safely converts '/' to '%2F' for the API path)
ENCODED_BRANCH="${TARGET_BRANCH//\//%2F}"

# Fetch ONLY the HTTP status code from the branch endpoint
HTTP_STATUS=$(curl --silent --output /dev/null --write-out "%{http_code}" \
  --header "PRIVATE-TOKEN: $TOKEN" \
  "${GITLAB_API_URL}/projects/${PROJECT_ID}/repository/branches/${ENCODED_BRANCH}")

# --- 3. CONDITIONAL LOGIC ---
if [ "$HTTP_STATUS" -eq 200 ]; then
  echo "✅ Branch '$TARGET_BRANCH' exists. Proceeding with normal operations..."
  # You can add the rest of your folder download/commit logic here if needed.
  
elif [ "$HTTP_STATUS" -eq 404 ]; then
  echo "❌ Branch '$TARGET_BRANCH' does NOT exist. Creating an issue to report this..."
  
  # Draft the issue title and description
  ISSUE_TITLE="Action Required: Missing Branch '$TARGET_BRANCH'"
  ISSUE_DESCRIPTION="An automated pipeline attempted to interact with the branch \`${TARGET_BRANCH}\`, but it could not be found in the repository. 

Please verify if the branch was deleted or renamed."

  # Build the JSON payload safely using jq
  PAYLOAD=$(jq --null-input \
    --arg title "$ISSUE_TITLE" \
    --arg desc "$ISSUE_DESCRIPTION" \
    '{
      "title": $title,
      "description": $desc,
      "labels": "automated, missing-branch, pipeline-alert"
    }')

  # Send the POST request to the Issues API
  ISSUE_RESPONSE=$(curl --silent --show-error --fail --request POST \
    --header "PRIVATE-TOKEN: $TOKEN" \
    --header "Content-Type: application/json" \
    --data "$PAYLOAD" \
    "${GITLAB_API_URL}/projects/${PROJECT_ID}/issues")

  # Extract the web URL of the new issue
  ISSUE_URL=$(echo "$ISSUE_RESPONSE" | jq -r '.web_url')
  
  echo "Success! Alert issue created."
  echo "View it here: $ISSUE_URL"
  
  # Optional: Exit with an error code to fail the CI/CD job since the required branch is missing
  # exit 1
  
else
  # Catch-all for API outages, bad tokens (401), or bad requests (400)
  echo "⚠️ Failed to check branch status. GitLab API returned HTTP $HTTP_STATUS."
  exit 1
fi

### NEW

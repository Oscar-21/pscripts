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

param(
  [Parameter(Mandatory=$true,
  HelpMessage="Entra App Client Id")]
  [String]
  $AppId,

  [Parameter(Mandatory=$true,
  HelpMessage="Entra App Name")]
  [String]
  $AppName,

[Parameter(Mandatory=$true,
  HelpMessage="Object ID of the Enterprise Application / service principal, not the app registration")]
  [String]
  $ObjId,

[Parameter(Mandatory=$true,
  HelpMessage="Object ID of the Enterprise Application / service principal, not the app registration")]
  [String]
  $SharedMailboxEmailAddress
)

Connect-ExchangeOnline

$Shared  = Get-Mailbox $SharedMailboxEmailAddress

# 1. Register the app's service principal in Exchange Online
New-ServicePrincipal -AppId $AppId -ObjectId $ObjId -DisplayName "$AppName EXO SP"

$NewMgmtScope = "Scope-$AppName-SharedMbx"
# 2. Scope to exactly one mailbox (filter by GUID — most reliable)
New-ManagementScope `
    -Name $NewMgmtScope `
    -RecipientRestrictionFilter "GUID -eq '$($Shared.GUID)'"

# 3. Grant the role, scoped to that mailbox
New-ManagementRoleAssignment `
    -App $AppId `
    -Role "Application Mail.Read" `
    -CustomResourceScope $NewMgmtScope

param(
  [Parameter(Mandatory=$true, HelpMessage="Entra App Name used in the previous script")]
  [String] $AppName,

  [Parameter(Mandatory=$true, HelpMessage="Object ID of the Enterprise Application / service principal")]
  [String] $ObjId
)

Connect-ExchangeOnline

$ScopeName = "Scope-$AppName-SharedMbx"

# 1. Check and Remove Role Assignments tied to the Custom Scope
Write-Host "Checking for existing Role Assignments tied to scope '$ScopeName'..." -ForegroundColor Cyan
$assignments = Get-ManagementRoleAssignment | Where-Object { $_.CustomResourceScope -eq $ScopeName }

if ($null -ne $assignments) {
    foreach ($assignment in $assignments) {
        Write-Host " -> Deleting Role Assignment: $($assignment.Identity)" -ForegroundColor Yellow
        #Remove-ManagementRoleAssignment -Identity $assignment.Identity -Confirm:$false
    }
} else {
    Write-Host " -> No Role Assignments found using this scope." -ForegroundColor Green
}

# 2. Check and Remove Management Scope
Write-Host "`nChecking for Management Scope '$ScopeName'..." -ForegroundColor Cyan
$scope = Get-ManagementScope -Identity $ScopeName -ErrorAction SilentlyContinue

if ($null -ne $scope) {
    Write-Host " -> Deleting Management Scope: $ScopeName" -ForegroundColor Yellow
    Remove-ManagementScope -Identity $ScopeName -Confirm:$false
} else {
    Write-Host " -> Management Scope '$ScopeName' does not exist." -ForegroundColor Green
}

# 3. Check and Remove Service Principal
Write-Host "`nChecking for Service Principal with Object ID '$ObjId'..." -ForegroundColor Cyan
$sp = Get-ServicePrincipal -Identity $ObjId -ErrorAction SilentlyContinue

if ($null -ne $sp) {
    Write-Host " -> Deleting Service Principal: $ObjId" -ForegroundColor Yellow
    Remove-ServicePrincipal -Identity $ObjId -Confirm:$false
} else {
    Write-Host " -> Service Principal '$ObjId' does not exist." -ForegroundColor Green
}

Write-Host "`nCleanup Complete!" -ForegroundColor Green

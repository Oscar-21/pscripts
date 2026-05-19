function global:GetFilesWithText {
  param(
    [Parameter(Mandatory=$true,
    HelpMessage="Text to Search")]
    [String]
    $MatchText
  )
  Get-ChildItem -Recurse -Filter *.xml |
    Select-String $MatchText |
    Select-Object Path, LineNumber
}

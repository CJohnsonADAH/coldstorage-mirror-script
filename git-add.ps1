$global:MyCmd = $MyInvocation.MyCommand
$global:ScriptPath = ( Split-Path -Parent $global:MyCmd.Source )

Push-Location $global:ScriptPath

& git status
& git add --patch

$sCommitMessage = ( Read-Host -Prompt "Commit Message [blank to avoid commitment]: " )

If ( $sCommitMessage ) {
    & git commit --message "$sCommitMessage"
}

Pop-Location

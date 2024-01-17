Param(
    $Prompt,
    $Timeout=-1.0,
    $DefaultInput="Y",
    $DefaultAction="",
    $DefaultTimeout=5.0
)

$global:gColdStorageReadYesFromHostCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gColdStorageReadYesFromHostCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageInteraction.psm1" )

Read-YesFromHost -Prompt:$Prompt -Timeout:$Timeout -DefaultInput:$DefaultInput -DefaultAction:$DefaultAction -DefaultTimeout:$DefaultTimeout

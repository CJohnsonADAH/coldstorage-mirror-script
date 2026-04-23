Param(
    $Prompt,
    $OtherOptions=@( ),
    $Timeout=-1.0,
    $DefaultInput="Y",
    $DefaultAction="",
    $DefaultTimeout=5.0,
    $PromptColor="Yellow"
)

$global:gColdStorageReadYesFromHostCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gColdStorageReadYesFromHostCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageInteraction.psm1" )

Read-YesFromHost -Prompt:$Prompt -OtherOptions:$OtherOptions -Timeout:$Timeout -DefaultInput:$DefaultInput -DefaultAction:$DefaultAction -DefaultTimeout:$DefaultTimeout -PromptColor:$PromptColor

Param(
    [string] $Name="",
    [switch] $Global=$false,
    $Context=$null,
    $Output=$null  
)

#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################

$global:gColdStorageSettingsModuleCmd = $MyInvocation.MyCommand
    
    $modSource = ( $global:gColdStorageSettingsModuleCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )

Function Get-ScriptPath {
Param ( $Command, $File=$null )

    $Source = ( $Command.Source | Get-Item -Force )
    $Path = ( $Source.Directory | Get-Item -Force )

    If ( $File -ne $null ) {
        $Path = ($Path.FullName | Join-Path -ChildPath $File)
    }

    $Path
}

#############################################################################################################
## EXECUTION ################################################################################################
#############################################################################################################

Get-ColdStorageSettings -Name:$Name -Output:$Output
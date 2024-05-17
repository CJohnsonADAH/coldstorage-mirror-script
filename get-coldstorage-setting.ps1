Param(
    [string] $Name="",
    [switch] $Global=$false,
    $Context=$null,
    $Default=$null,
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

If ( $Global -or ( $Context -eq $null ) ) {
    Get-ColdStorageSettings -Name:$Name -Output:$Output
}
Else {

    $Props = ( $Context | Get-ItemColdStorageProps )
    
    If ( $Name.Length -gt 0 ) {
        $Value = $Default
        If ( $Props | Get-Member -Name:$Name -ErrorAction SilentlyContinue ) {
            $Value = $Props.$Name
        }

        If ( $Value -ne $null ) {
            $Value
        }

    }
    Else {
        $Props
    }
}
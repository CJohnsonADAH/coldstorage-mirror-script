Param( [switch] $Batch=$false, [switch] $WhatIf=$false, $Repository="ER" )

$ScriptPath = ( Split-Path -Parent $PSCommandPath )
$ScriptParent = ( Split-Path -Parent $ScriptPath )

$bin="${ScriptParent}"

$Prefix="coldstorage-validate"
$LogFiles = @{
    "stdout"="${Prefix}-${Repository}-log.txt"
    "stderr"="${Prefix}-${Repository}-err-log.txt"
    "stdwarn"="${Prefix}-${Repository}-warn-log.txt"
}
$LogPaths = "${bin}", "${HOME}\Desktop"

$StdOutLogFile = $LogPaths[0] + "\" + $LogFiles["stdout"]
$StdErrLogFile = $LogPaths[0] + "\" + $LogFiles["stderr"]
$StdWarnLogFile = $LogPaths[0] + "\" + $LogFiles["stdwarn"]

Function Do-Replicate-Log {
Param ( $From, $To )
    $To | ForEach {
        $Parent = $_
        $Leaf = Split-Path -Leaf $From
        $Dest = "${Parent}\${Leaf}"

        If ($From -ne $Dest) {
            Copy-Item "${From}" "${Dest}"
        }
    }
}

If ( $Batch ) {
    $Date = ( Date )
    Write-Output "Launched ${Repository}: ${Date}" >> "${StdOutLogFile}"
    Write-Output "Launched ${Repository}: ${Date}" >> "${StdErrLogFile}"
    Write-Output "Launched ${Repository}: ${Date}" >> "${StdWarnLogFile}"
    Do-Replicate-Log -From $StdOutLogFile -To $LogPaths
    Do-Replicate-Log -From $StdErrLogFile -To $LogPaths
    Do-Replicate-Log -From $StdWarnLogFile -To $LogPaths
}

If ( $Batch ) {
    If ( $WhatIf ) {
        Write-Host "${bin}\coldstorage-mirror-script\coldstorage.ps1" validate ${Repository} -Batch ">>" "${StdOutLogFile}" "2>>" "${StdErrLogFile}" "3>>" "${StdWarnLogFile}"
    }
    Else {
        & "${bin}\coldstorage-mirror-script\coldstorage.ps1" validate ${Repository} -Batch >> "${StdOutLogFile}" 2>>"${StdErrLogFile}" 3>>"${StdWarnLogFile}"
    }
    Do-Replicate-Log -From $StdOutLogFile -To $LogPaths
    Do-Replicate-Log -From $StdErrLogFile -To $LogPaths
    Do-Replicate-Log -From $StdWarnLogFile -To $LogPaths
}
Else {
    If ( $WhatIf ) {
        Write-Host "${bin}\coldstorage-mirror-script\coldstorage.ps1" validate ${Repository}
    }
    Else {
        & "${bin}\coldstorage-mirror-script\coldstorage.ps1" validate ${Repository}
    }
}

If ( $Batch ) {
    $Date = ( Date )
    "Completed ${Repository}: ${Date}" >> "${StdOutLogFile}"
    "Completed ${Repository}: ${Date}" >> "${StdErrLogFile}"
    "Completed ${Repository}: ${Date}" >> "${StdWarnLogFile}"
    Do-Replicate-Log -From $StdOutLogFile -To $LogPaths
    Do-Replicate-Log -From $StdErrLogFile -To $LogPaths
    Do-Replicate-Log -From $StdWarnLogFile -To $LogPaths
}
ElseIf ($psISE) {
	Add-Type -AssemblyName System.Windows.Forms
	$null = [System.Windows.Forms.MessageBox]::Show("Completed.")
}
Else {
	Write-Host "Press any key to continue..."
	$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

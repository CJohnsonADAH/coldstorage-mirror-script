Param(
    [switch] $Batch=$false,
    [switch] $WhatIf=$false,
    $Repository="",
    $Output="CSV",
    [switch] $NoZipped=$false,
    [switch] $Quiet=$false
)


If ( $Repository.Length -gt 0 ) {
    $RepositorySlug = ( "-${Repository}" -replace "[^0-9A-Za-z_]+","-" )
}
Else {
    $RepositorySlug = "-All"
}

$ScriptPath = ( Split-Path -Parent $PSCommandPath )
$ScriptParent = ( Split-Path -Parent $ScriptPath )
$ColdStorageScript = "${ScriptPath}\coldstorage.ps1"
$bin="${ScriptParent}"

$LogFile = "${HOME}\Desktop\coldstorage-timed-updates${RepositorySlug}-log.txt"
$ShareLogFile = "${bin}\coldstorage-timed-updates${RepositorySlug}-log.txt"

If ( $Batch ) {
    $Date = ( Date )
    Write-Output "Launched${RepositorySlug}: ${Date}" >> "${ShareLogFile}"
    Copy-Item "${ShareLogFile}" "${LogFile}"
}

$WIT = $( If ($WhatIf) { "(WhatIf) " } Else { "" } )
If ( -Not $Quiet ) {
    $sCommand = ( "{0}& {1} {2} {3}" -f "${WIT}","${ColdStorageScript}","update","clamav")
    If ( $Batch ) {
        Write-Output $sCommand  >> "${ShareLogFile}"
    }
    Else {
        Write-Output $sCommand
    }
}

If ( $Batch ) {
    
    If ( -Not $WhatIf ) {
        & "${ColdStorageScript}" update clamav -Batch *>>"${ShareLogFile}"
    }
    
    Copy-Item "${ShareLogFile}" "${LogFile}"

}
Else {
    If ( -Not $WhatIf ) {
        & "${ColdStorageScript}" update clamav
    }
}

If ( $Batch ) {
    $Date = ( Date )
    Write-Host "Completed${RepositorySlug}: ${Date}" >> "${ShareLogFile}"
    Copy-Item "${ShareLogFile}" "${LogFile}"
}
ElseIf ($psISE) {
	Add-Type -AssemblyName System.Windows.Forms
	$null = [System.Windows.Forms.MessageBox]::Show("Completed.")
}
Else {
	Write-Host "Press any key to continue..."
	$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

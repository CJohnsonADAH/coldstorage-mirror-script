Param( [switch] $Batch=$false, [switch] $WhatIf=$false, $Repository="" )

If ( $Repository.Length -gt 0 ) {
    $RepositorySlug = ( "-${Repository}" -replace "[^0-9A-Za-z_]+","-" )
}
Else {
    $RepositorySlug = "-All"
}

$ScriptPath = ( Split-Path -Parent $PSCommandPath )
$ScriptParent = ( Split-Path -Parent $ScriptPath )

$bin="${ScriptParent}"

$LogFile = "${HOME}\Desktop\coldstorage-mirror${RepositorySlug}-log.txt"
$ShareLogFile = "${bin}\coldstorage-mirror${RepositorySlug}-log.txt"

If ( $Batch ) {
    $Date = ( Date )
    Write-Output "Launched${RepositorySlug}: ${Date}" > "${ShareLogFile}"
    Copy-Item "${ShareLogFile}" "${LogFile}"
}

If ( $Batch ) {
    If ( $WhatIf ) {
        Write-Host "${bin}\coldstorage-mirror-script\coldstorage.ps1" mirror ${Repository} -Batch >> "${ShareLogFile}"
    }
    Else {
        & "${bin}\coldstorage-mirror-script\coldstorage.ps1" mirror ${Repository} -Batch >> "${ShareLogFile}"
    }
    Copy-Item "${ShareLogFile}" "${LogFile}"
}
Else {
    If ( $WhatIf ) {
        Write-Host "${bin}\coldstorage-mirror-script\coldstorage.ps1" mirror ${Repository}
    }
    Else {
        & "${bin}\coldstorage-mirror-script\coldstorage.ps1" mirror ${Repository}
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

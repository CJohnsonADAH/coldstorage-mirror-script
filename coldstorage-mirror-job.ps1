﻿Param( [switch] $Batch=$false, [switch] $WhatIf=$false, [switch] $SizesOnly, [switch] $Diff, $Repository="" )

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

$MyLogDir = "${HOME}\Desktop\ColdStorage-Logs"
$LogFile = ( $MyLogDir | Join-Path -ChildPath "coldstorage-mirror${RepositorySlug}-log.txt" )
$ShareLogFile = "${bin}\coldstorage-mirror${RepositorySlug}-log.txt"

If ( $Batch ) {
    $Date = ( Date )
    Write-Output "Launched${RepositorySlug}: ${Date}" > "${ShareLogFile}"
    Copy-Item "${ShareLogFile}" "${LogFile}"
}

If ( $Batch ) {
    If ( $WhatIf ) {
        Write-Host "${ColdStorageScript}" mirror ${Repository} -Batch -Diff:$Diff -SizesOnly:$SizesOnly >> "${ShareLogFile}"
    }
    Else {
        & "${ColdStorageScript}" mirror ${Repository} -Batch -Diff:$Diff -SizesOnly:$SizesOnly >> "${ShareLogFile}"
    }
    Copy-Item "${ShareLogFile}" "${LogFile}"
}
Else {
    If ( $WhatIf ) {
        Write-Host "${ColdStorageScript}" mirror ${Repository} -Diff:$Diff -SizesOnly:$SizesOnly 
    }
    Else {
        & "${ColdStorageScript}" mirror ${Repository} -Diff:$Diff -SizesOnly:$SizesOnly 
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

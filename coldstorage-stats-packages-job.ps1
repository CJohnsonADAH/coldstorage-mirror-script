Param(
    [switch] $Batch=$false,
    [switch] $WhatIf=$false,
    $Repository="",
    $Output="CSV",
    [switch] $NoZipped=$false,
    $OutputFile=$null )


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

$LogFile = "${HOME}\Desktop\coldstorage-packages${RepositorySlug}-log.txt"
$ShareLogFile = "${bin}\coldstorage-packages${RepositorySlug}-log.txt"

If ( $OutputFile -eq $null ) {
    $Timestamp = ( Date -Format "yyyyMMdd" )
    $OutputFile = "${bin}\logs\coldstorage-packages${RepositorySlug}-${Timestamp}.csv"
}

If ( $Batch ) {
    $Date = ( Date )
    Write-Output "Launched${RepositorySlug}: ${Date}" >> "${ShareLogFile}"
    Copy-Item "${ShareLogFile}" "${LogFile}"
}

# Example:
# & coldstorage packages -Items . -Output:CSV -Batch -Recurse -Report -Zipped |Tee-Object "F:\Share\Scripts\logs\coldstorage-digitization-masters-packages-20210305.csv"
If ( $Batch ) {
    
    $t0 = ( Get-Date )
    
    Write-Output ( "& {0} {1} {2} {3} {4} {5} {6} {7} {8} >> {9}" -f "${ColdStorageScript}","packages","${Repository}","-Output:CSV","-Batch","-Quiet","-Recurse","-Report","-Zipped","${OutputFile}") >> "${ShareLogFile}"
    & "${ColdStorageScript}" packages ${Repository} -Output:CSV -Batch -Quiet -Recurse -Report -Zipped >>"${OutputFile}" *>>"${ShareLogFile}"

    $tN = ( Get-Date )

    ( "Completed: {0}" -f $tN ) >> "${ShareLogFile}" 
    ( New-Timespan -Start:$t0 -End:$tN ) >> "${ShareLogFile}"
    
    Copy-Item "${ShareLogFile}" "${LogFile}"

}
Else {
    If ( $WhatIf ) {
        Write-Host "${ColdStorageScript}" packages ${Repository} -Output:CSV -Recurse -Report -Zipped "|" "Tee-Object" "${OutputFile}"
    }
    Else {
        & "${ColdStorageScript}" packages ${Repository} -Output:CSV -Recurse -Report -Zipped | Tee-Object "${OutputFile}"
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

Param(
    [switch] $Batch=$false,
    [switch] $WhatIf=$false,
    [Int] $Next=0,
    $Items="",
    $Repository="",
    $Output="CSV",
    [switch] $NoZipped=$false,
    $OutputFile=$null
)

If ( $Items.Length -gt 0 ) {
    $aItems = ( $Items -split "," )
    $ItemsSlug = ( "-${Items}" -replace "[^0-9A-Za-z_]+","-" )
}
Else {
    $ItemsSlug = ""
    $aItems = @( )
}

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
$LogFile = ( $MyLogDir | Join-Path -ChildPath "coldstorage-packages${RepositorySlug}${ItemsSlug}-log.txt" )
$ShareLogFile = "${bin}\coldstorage-packages${RepositorySlug}${ItemsSlug}-log.txt"

If ( $OutputFile -eq $null ) {
    $Timestamp = ( Date -Format "yyyyMMdd" )
    $OutputFile = "${bin}\logs\coldstorage-packages${RepositorySlug}${ItemsSlug}-${Timestamp}.csv"
}


# Example:
# & coldstorage packages -Items . -Output:CSV -Batch -Recurse -Report -Zipped |Tee-Object "F:\Share\Scripts\logs\coldstorage-digitization-masters-packages-20210305.csv"

If ( $aItems.Count -gt 0 ) {
    $bItems = $true
    $sLocationSwitch = ($aItems -join " ")
    $aRepositoryLocation = $( & coldstorage repository -Repository "${Repository}" )
    Set-Location $aRepositoryLocation["FILE"]
}
ElseIf ( $Next -gt 0 ) {

    $aRepositoryLocation = ( & "${ColdStorageScript}" repository "${Repository}" )
    $aNextLocations = @( )
    If ( $aRepositoryLocation ) {
        $StateFile = "${HOME}\Desktop\coldstorage-packages${RepositorySlug}-JobItem.txt"
        
        $RepositoryPath = $aRepositoryLocation["FILE"]
        If ( Test-Path -LiteralPath "${RepositoryPath}" -PathType Container ) {

            $PreviousSection = $( If ( Test-Path -LiteralPath "${StateFile}" -PathType Leaf ) { Get-Content "${StateFile}" } Else { $null } )
            $Subsections = ( Get-ChildItem -Directory "${RepositoryPath}" | Where { ( $_.Name -ne ".coldstorage" ) -And ( $_.Name -ne "ZIP" ) } )

            $pastIt = $false; $afterLocations = ( $Subsections |% { If ( $_.FullName -ieq $PreviousSection ) { $pastIt = $true } ElseIf ( $pastIt ) { $_ } } )
            $pastIt = $false; $beforeLocations = ( $Subsections |% { If ( $_.FullName -ieq $PreviousSection ) { $pastIt = $true } ElseIf ( -Not $pastIt ) { $_ } } )
            $afterBefore = @( $afterLocations ) + @( $beforeLocations )
            
            $aNextLocations = ( $afterBefore | Select-Object -First ${Next} ).FullName

        }

    }

    If ( $aNextLocations.Count -gt 0 ) {
        $aNextLocations | Select-Object -First 1 |% { "[coldstorage-stats-packages-job] Next location: {0}" -f $_ } | Write-Warning

        If ( "${StateFile}" ) {
            ($aNextLocations | Select-Object -Last 1) > "${StateFile}"
        }

        $bItems = $true
        $sLocationSwitch = ($aNextLocations -join " ")
        Set-Location $RepositoryPath

        $ItemsSlug = ( "-${sLocationSwitch}" -replace "[^0-9A-Za-z_]+","-" )
        $LogFile = "${HOME}\Desktop\coldstorage-packages${RepositorySlug}${ItemsSlug}-log.txt"
        $ShareLogFile = "${bin}\coldstorage-packages${RepositorySlug}${ItemsSlug}-log.txt"

    }
    Else {
        ( "[coldstorage-stats-packages-job] Could not locate repository {0} or list for items." -f "${Repository}" )
        Exit
    }

}
Else {
    $bItems = $false
    $sLocationSwitch = "${Repository}"
}

If ( $Batch ) {

    $Date = ( Date )
    Write-Output "Launched${RepositorySlug}: ${Date}" >> "${ShareLogFile}"
    Copy-Item "${ShareLogFile}" "${LogFile}"
    
    $t0 = ( Get-Date )
    
    Write-Output ( "& {0} {1} -Items:{2} {3} {4} {5} {6} {7} {8} {9} >> {10}" -f "${ColdStorageScript}","packages","${bItems}","${sLocationSwitch}","-Output:CSV","-Batch","-Quiet","-Recurse","-Report","-Zipped","${OutputFile}") >> "${ShareLogFile}"
    & "${ColdStorageScript}" packages -Items:${bItems} ${sLocationSwitch} -Output:CSV -Batch -Quiet -Recurse -Report -Zipped >>"${OutputFile}" *>>"${ShareLogFile}"

    $tN = ( Get-Date )

    ( "Completed: {0}" -f $tN ) >> "${ShareLogFile}" 
    ( New-Timespan -Start:$t0 -End:$tN ) >> "${ShareLogFile}"
    
    Copy-Item "${ShareLogFile}" "${LogFile}"

}
Else {
    If ( $WhatIf ) {
        Write-Host "${ColdStorageScript}" packages -Items:$bItems ${sLocationSwitch} -Output:CSV -Recurse -Report -Zipped "|" "Tee-Object" "${OutputFile}"
    }
    Else {
        & "${ColdStorageScript}" packages -Items:${bItems} ${sLocationSwitch} -Output:CSV -Recurse -Report -Zipped | Tee-Object "${OutputFile}"
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

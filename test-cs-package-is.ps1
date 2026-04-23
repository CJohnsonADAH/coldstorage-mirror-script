Param(
    [Parameter(ValueFromPipeline=$true)] $Package,
    [string] $Output="",
    [switch] $Not,
    [switch] $Bagged,
    [switch] $BagItFormatted,
    [switch] $Sidecars,
    [switch] $Unbagged,
    [switch] $Mirrored,
    [switch] $Unmirrored,
    [switch] $Zipped,
    [switch] $Unzipped,
    [switch] $InCloud,
    [switch] $NotInCloud,
    [switch] $FullName=$false,
    $Timestamp=$null,
    $Context=$null
)

Begin {

    $Verbose = ( $MyInvocation.BoundParameters["Verbose"].IsPresent )
    $Verbose = $( If ( $Verbose -eq $null ) { $false } Else { $Verbose } )
    $Debug = ( $MyInvocation.BoundParameters["Debug"].IsPresent )
    $Debug = $( If ( $Debug -eq $null ) { $false } Else { $Debug } )

    # Internal Dependencies - Modules
    $global:gWritePackagesReportCSCmd = $MyInvocation.MyCommand

        $modSource = ( $global:gWritePackagesReportCSCmd.Source | Get-Item -Force )
        $modPath = ( $modSource.Directory | Get-Item -Force )

    $ExitCode = 0
}

Process {
    $o = ( $Package | & select-cs-package-where.ps1 -Output:$Output -Not:$Not -Bagged:$Bagged -BagItFormatted:$BagItFormatted -Sidecars:$Sidecars -Unbagged:$Unbagged -Mirrored:$Mirrored -Unmirrored:$Unmirrored -Zipped:$Zipped -Unzipped:$Unzipped -InCloud:$InCloud -NotInCloud:$NotInCloud -FullName:$FullName -Timestamp:$Timestamp -Context:$Context )

    $bResult = ( $o -ne $null )

    $bResult | Write-Output
    If ( -Not $bResult ) {
        $ExitCode = 1
    }
}

End {
    Exit $ExitCode
}

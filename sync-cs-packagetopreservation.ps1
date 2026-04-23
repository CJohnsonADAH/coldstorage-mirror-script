Param(
    [Parameter(ValueFromPipeline=$true)] $Package,
    [switch] $Batch=$false,
    [switch] $NoMirror=$false,
    [int] $InputTimeout=60,
    $Automatically=@( ),
    $InputDefault="N",
    $Context=$null,
    [switch] $Quiet=$false
)

Begin {
    $global:gColdStorageSyncToPreservationCmd = $MyInvocation.MyCommand

        $modSource = ( $global:gColdStorageSyncToPreservationCmd.Source | Get-Item -Force )
        $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" ) -Force
    Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageUserPrivileges.psm1" ) -Force

    $Interactive = ( -Not $Batch )

    $TimeoutBase = $InputTimeout
    If ( $InputTimeout -lt 0 ) {
        $TimeoutBase = $null
    }

    Function Write-HostSectionHeader {
    Param ( [Parameter(ValueFromPipeline=$true)] $Line, $ForegroundColor="DarkGreen" )

        Begin {
            "" | Write-Host -ForegroundColor:$ForegroundColor
        }

        Process {
            $Line | Write-Host -ForegroundColor:$ForegroundColor
        }

        End { }
    }

    Function Write-OutputWithLogMaybe {
    Param ( [Parameter(ValueFromPipeline=$true)] $Line, $Package, $Command=$null, $Log )

        Begin {
            If ( $Log -ne $null ) {
                If ( -Not ( Test-Path -LiteralPath $Log ) ) {
                    $StartMessage = @{ "Location"=$Package.FullName; "Time"=( Get-Date ).ToString() }
                    ( "! JSON[Start]: {0}" -f ( $StartMessage | ConvertTo-Json -Compress ) ) | Out-File -LiteralPath:$Log -Append
                }
            }
            If ( $Command -ne $null ) {
                If ( $Log -ne $null ) {
                    $StartMessage = @{ "Command"=( $Command -f ( "Get-Item -LiteralPath '{0}' -Force" -f $Package.FullName ) ); "Time"=( Get-Date ).ToString() }
                    ( "! JSON[Command]: {0}" -f ( $StartMessage | ConvertTo-Json -Compress ) ) | Out-File -LiteralPath:$Log -A
                }
            }
        }

        Process {
            If ( $Line -ne $null ) {
                $Line | Write-Output
                If ( $Log -ne $null ) {
                    "$Line" | Out-File -LiteralPath:$Log -Append
                }
            }
        }

        End { }

    }

}

Process {
    $sConfirm = "CONFIRM"
    $sContext = $global:gColdStorageSyncToPreservationCmd.Name

    If ( $Context -ne $null ) {
        If ( ( "${Context}" ).Length -gt 0 ) {
            $sContext = $Context
            $sConfirm = ( "[{0}] {1}" -f "${Context}", $sConfirm )
        }
    }

    $DeferredFile = ( & get-deferred-preservation-jobs-cs.ps1 | Select-Object -First 1 )
    If ( $Package | test-cs-package-is ) {

        $sPackageRepositoryLocation = ( $Package | Get-FileRepositoryLocation )
        $sPackageRelPath = ( $Package.FullName | Resolve-PathRelativeTo -Base:$sPackageRepositoryLocation )

        $PassThru = $false
        $SkipOver = $false

		$LogFile = $null
        If ( -Not ( $Package | Test-LooseFile ) -and ( $Package | test-cs-package-is.ps1 -Bagged ) ) {
			$LogFile = ( $Package | & get-itempackageeventlog-cs.ps1 -Event:"preservation-sync" -Timestamp:( Get-Date ) -Force )
			"LOG: {0}" -f $LogFile | Write-Verbose
        }

        If ( $Package | test-cs-package-is -Unbagged ) {
            $DefaultYN = $( If ( $PassThru ) { "Y" } Else { $InputDefault } )
            $DefaultLeaveDo = $( If ( $DefaultYN -eq "Y" ) { "bag package" } Else { "leave unbagged" } )
            $TimeoutYN = $( If ( $PassThru ) { 10 } Else { $TimeoutBase } )

            $PassThru = $false
            $SkipOver = $true
        
            $DoIt = ( $Batch -or ( "bag" -iin $Automatically ) )
            If ( ( -Not $DoIt ) -and $Interactive ) {
                $DoIt = ( read-yesfromhost-cs.ps1 -Prompt ( "{0}: Bag up package {1}?" -f $sConfirm, $Package.Name ) -Timeout:$TimeoutYN -DefaultInput:$DefaultYN -DefaultTimeout:10 -DefaultAction:$DefaultLeaveDo )
            }
            If ( $DoIt ) {
                If ( ( -Not $Quiet ) -and ( $Context -ne $null ) ) { "* {0}: PACKAGING Copy-1 and MIRRORING Copy-2 local preservation copy" -f $Context | Write-HostSectionHeader }

                $Package | & coldstorage bag -Mirrored
                $Package = ( $Package | & coldstorage packages -Items -Bagged -Mirrored -Zipped -InCloud )
                $PassThru = $true
                $SkipOver = $false
            }
            Else {
                ( "{0} | & coldstorage bag -Items" -f ( "Get-Item -LiteralPath '{0}'" -f $Package.FullName ) ) | Out-File -LiteralPath:$DeferredFile -Append
            }
        }
 
        If ( ( -Not $NoMirror ) -and ( $Package | test-cs-package-is -Unmirrored ) ) {

            $DefaultYN = $( If ( $PassThru ) { "Y" } Else { $InputDefault } )
            $DefaultLeaveDo = $( If ( $DefaultYN -eq "Y" ) { "mirror package" } Else { "leave unmirrored" } )
            $TimeoutYN = $( If ( $PassThru ) { 10 } Else { $TimeoutBase } )

            $DoIt = ( $Batch -or ( "mirror" -iin $Automatically ) )
            If ( ( -Not $DoIt ) -and $Interactive ) {
                $DoIt = ( read-yesfromhost-cs.ps1 -Prompt ( "{0}: Mirror package {1}?" -f $sConfirm, $Package.Name ) -Timeout:$TimeoutYN -DefaultInput:N -DefaultTimeout:60 -DefaultAction:"leave unmirrored" )
            }
            If ( $DoIt ) {
                If ( ( -Not $Quiet ) -and ( $Context -ne $null ) ) { "* {0}: MIRRORING Copy-2 local preservation copy" -f $Context | Write-HostSectionHeader }
                $Package | & coldstorage mirror -Items -RoboCopy | Write-OutputWithLogMaybe -Log:$LogFile -Package:$Package -Command:"{0} | & coldstorage mirror -Items -RoboCopy"
                $PassThru = $true
            }
            Else {
                ( "{0} | & coldstorage mirror -Items -RoboCopy" -f ( "Get-Item -LiteralPath '{0}'" -f $Package.FullName ) ) | Out-File -LiteralPath:$DeferredFile -Append
            }

        }

       If ( -Not $SkipOver -and ( $PassThru -or ( $Package | test-cs-package-is -Unzipped ) ) ) {
            $DefaultYN = $( If ( $PassThru ) { "Y" } Else { $InputDefault } )
            $DefaultLeaveDo = $( If ( $DefaultYN -eq "Y" ) { "zip package" } Else { "leave unzipped" } )
            $TimeoutYN = $( If ( $PassThru ) { 10 } Else { $TimeoutBase } )

            $PassThru = $false
            $SkipOver = $true

            $DoIt = ( $Batch -or ( "zip" -iin $Automatically ) )
            If ( ( -Not $DoIt ) -and $Interactive ) {
                $DoIt = ( read-yesfromhost-cs.ps1 -Prompt ( "{0}: Zip package {1}?" -f $sConfirm, $Package.Name ) -Timeout:$TimeoutYN -DefaultInput:$DefaultYN -DefaultTimeout:10 -DefaultAction:$DefaultLeaveDo )
            }
            If ( $DoIt ) {
                $Package | & coldstorage zip -Items | Write-OutputWithLogMaybe -Log:$LogFile -Package:$Package -Command:"{0} | & coldstorage zip -Items" |% {
                    $FGColor = "Gray"
                    If ( $_.New -eq $false ) {
                        $FGColor = "DarkGray"
                    }
                    "[{0}] Zipped package: {1} -> {2}" -f $sContext, ( $_.Bag | Resolve-PathRelativeTo -Base:$sPackageRepositoryLocation ), ( $_.Zip | Resolve-PathRelativeTo -Base:$sPackageRepositoryLocation ) | Write-Host -ForegroundColor:$FGColor
                }
                $Package = ( $Package | & coldstorage packages -Items -Bagged -Mirrored -Zipped -InCloud )
                $PassThru = $true
                $SkipOver = $false
            }
            Else {
                ( "{0} | & coldstorage zip -Items" -f ( "Get-Item -LiteralPath '{0}'" -f $Package.FullName ) ) | Out-File -LiteralPath:$DeferredFile -Append
            }
        }
        If ( -Not $SkipOver -and ( $PassThru -or ( $Package | test-cs-package-is -NotInCloud ) ) ) {
            $DefaultYN = $( If ( $PassThru ) { "Y" } Else { $InputDefault } )
            $DefaultLeaveDo = $( If ( $DefaultYN -eq "Y" ) { "upload to cloud" } Else { "leave not in cloud" } )
            $TimeoutYN = $( If ( $PassThru ) { 10 } Else { $TimeoutBase } )

            $PassThru = $false
            $SkipOver = $true


            $DoIt = ( $Batch -or ( "cloud" -iin $Automatically ) )
            If ( ( -Not $DoIt ) -and $Interactive ) {
                $DoIt = ( read-yesfromhost-cs.ps1 -Prompt ( "{0}: Upload {1} to cloud?" -f $sConfirm, $Package.Name ) -Timeout:$TimeoutYN -DefaultInput:$DefaultYN -DefaultTimeout:10 -DefaultAction:$DefaultLeaveDo )
            }
            If ( $DoIt ) {
                If ( ( -Not $Quiet ) -and ( $Context -ne $null ) ) { "* {0}: SENDING Copy-3 off-site preservation copy TO CLOUD STORAGE" -f $Context | Write-HostSectionHeader }

                $Package | & coldstorage to cloud -Quiet:( $Quiet -or ( $Context -ne $null ) ) | Write-OutputWithLogMaybe -Log:$LogFile -Package:$Package -Command:"{0} | & coldstorage to cloud -Items"
                $Package = ( $Package | & coldstorage packages -Items -Bagged -Mirrored -Zipped -InCloud )
                $PassThru = $true
                $SkipOver = $false
            }
            Else {
                ( "{0} | & coldstorage to cloud -Items" -f ( "Get-Item -LiteralPath '{0}'" -f $Package.FullName ) ) | Out-File -LiteralPath:$DeferredFile -Append
            }
        }
    
        If ( $DoIt ) {
            $Package | write-packages-report-cs.ps1 | Write-OutputWithLogMaybe -Log:$LogFile -Package:$Package -Command:"{0} | & write-packages-report-cs.ps1" | Write-Host -ForegroundColor Green -BackgroundColor Black
        }
    }
}

End {
}

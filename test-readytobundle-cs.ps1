Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    $Path=$null,
    $LiteralPath=$null,
    $Count=-1,
    [switch] $List=$false
)

Begin {
    $Verbose = ( $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent )
    $Verbose = $( If ( $Verbose -eq $null ) { $false } Else { $Verbose } )
    $Debug = ( $PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent )
    $Debug = $( If ( $Debug -eq $null ) { $false } Else { $Debug } )

    If ( $Debug ) {
        $DebugPreference = 'Continue'
    }

    $global:gColdStorageTestReadyToBundleCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gColdStorageTestReadyToBundleCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$Verbose -Debug:$Debug -Force:$Debug $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )

    Function Get-LogicalTotal {
    Param ( [Parameter(ValueFromPipeline=$true)] $Bit, [switch] $Product=$false, [switch] $Sum=$false  )

        Begin {
            If ( $Product ) {
                $RunningCount = $true
            }
            Else {
                $RunningCount = $false
            }
        }

        Process {
            If ( $Product ) {
                $RunningCount = ( $RunningCount -and $Bit )
            }
            If ( $Sum ) {
                $RunningCount = ( $RunningCount -or $Bit )
            }
        }

        End {
            $RunningCount
        }

    }

    Function Test-DirectoryCoversRange {
        Param ( [Parameter(ValueFromPipeline=$true)] $File, [Int] $At )

        Begin { }

        Process { 
        
            If ( $File -ne $null ) {
                $covered = @( )
                
                $Range = ( $File | get-numbereditemsrange-cs.ps1 -Prefix )
                "Checking item [{0}] for {1:D0} item range / {2}" -f $File.Name,$Range.Count,$File.FullName | Write-Debug
                $Range |% {

                    $Container = ( $File.FullName )
                    $FileSUffix = ".tif"
                    $Wildcard = ( "{0}*{1}" -f $_, $FileSuffix )
                    $WildPath = ( Join-Path $Container -ChildPath $Wildcard )

                    $result = @( Test-Path -Path:$WildPath )
                    If ( -Not ( $result ) ) {
                        "Missing: {0}" -f $WildPath | Write-Debug
                    }
                    $covered = @( $covered ) + @( $result )
                }

                $covered | Get-LogicalTotal -Product

            }

        }

        End { }
    }

    Function Test-DirectoryHasCount {
        Param ( [Parameter(ValueFromPipeline=$true)] $File, [Int] $At )

        Begin { }

        Process {
            $nBakedAt = $At
            If ( $At -lt 0 ) {
                $Props = ( $_ | Get-ItemColdStorageProps )
                $nBakedAt = $BakedAt
                If ( $nBakedAt -eq $null ) {
                    ( "Setting from PackageCount: {0:N0}" -f $Props.PackageCount ) | Write-Debug
                    $nBakedAt = $Props.PackageCount
                }
                If ( $nBakedAt -eq $null ) {
                    $nBakedAt = 500
                }
            }

            If ( $File -ne $null ) {
                "Checking item [{0}] for count {1:N0} / {2}" -f $File.Name,$nBakedAt,$File.FullName | Write-Debug

                Write-Progress -Id 502 -Activity "Measuring" -Status $_.FullName
                $N = ( Get-ChildItem -LiteralPath $File.FullName -Force | Measure-Object )
                Write-Progress -Id 502 -Activity "Measuring" -Completed

                "Item [{0}] count = {1:N0}" -f $File.Name,$N.Count | Write-Debug

                $File | Add-Member -MemberType NoteProperty -Name CSMCFileCount -Value $N.Count -Force
                ( $N.Count -ge $nBakedAt )

            }
        }

        End { }
    }

    $allObjects = @( )
    If ( $Path -ne $null ) {
        $allObjects = @( $allObjects ) + @( Get-Item -Path:$Path )
    }
    If ( $LiteralPAth -ne $null ) {
        $allObjects = @( $allObjects ) + @( Get-Item -LiteralPath:$LiteralPath )
    }

    $results = @( )
    $csExitCode = 255
}

Process {
    If ( $Count -eq $null ) {
        $nCount = -1
    }
    Else {
        $nCount = [int] $Count
    }

    $Item | get-file-cs.ps1 -Object |% {
        $BundleType = (  get-coldstorage-setting.ps1 -Context:$_ -Name:BundleType -Default:"count" )
        If ( $BundleType -eq 'range' ) {
            $result = ( $_ | Test-DirectoryCoversRange )
        }
        Else {
            $result = ( $_ | Test-DirectoryHasCount -At:$nCount )
        }
        If ( $List ) { $result }
        $results = @( $results ) + @( $result )
    }
}

End {
    $allObjects |% {
        $Cmd = $MyInvocation.MyCommand.Source
        $subresults = ( $_ | & "${Cmd}" -Count:$Count -List ) 
        
        If ( $List ) { $subresults }
        $results = @( $results ) + @( $subresults )
    }

    If ( $results | Get-LogicalTotal -Product ) {
        $csExitCode = 0
    }
    Else {
        $csExitCode = 1
    }

    If ( -Not $List ) {
        $results | Get-LogicalTotal -Product
    }

    Exit $csExitCode
}
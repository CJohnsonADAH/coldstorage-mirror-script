Param(
    [Parameter(ValueFromPipeline=$true)] $Location,
    [switch] $Report=$false,
    [switch] $Batch=$false
)


Begin {

    $Verbose = ( $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent )
    $Verbose = $( If ( $Verbose -eq $null ) { $false } Else { $Verbose } )
    $Debug = ( $PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent )
    $Debug = $( If ( $Debug -eq $null ) { $false } Else { $Debug } )

    $global:gCSSync321ScriptName = $MyInvocation.MyCommand
    $global:gCSSync321ScriptPath = $MyInvocation.MyCommand.Definition

    Function Get-CSScriptDirectory {
    Param ( $File=$null )
        $ScriptPath = ( Split-Path -Parent $PSCommandPath )
        If ( $File -ne $null ) { $ScriptPath = ( Join-Path "${ScriptPath}" -ChildPath "${File}" ) }
        ( Get-Item -Force -LiteralPath "${ScriptPath}" )
    }

    # Internal Dependencies - Modules
    $bVerboseModules = ( $Debug -eq $true )
    $bForceModules = ( ( $Debug -eq $true ) -or ( $psISE ) -or ( $Force ) -or ( $versionChange ) )

    Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageBagItDirectories.psm1" )

    $ExitCode = 0

    $aObjects = @( )
}

Process {
    If ( $Location -ne $null ) {
        $aObjects = @( $aObjects ) + @( $Location )
    }
}

End {

    $CSScript = $( Get-CSScriptDirectory -File "coldstorage.ps1" )
    $CSGetPackages = $( Get-CSScriptDirectory -File "get-itempackage-cs.ps1" )
    $CSTestPackageIs = $( Get-CSScriptDirectory -File "test-cs-package-is.ps1" )
    $CSWritePackagesReport = $( Get-CSScriptDirectory -File "write-packages-report-cs.ps1" )
    $CSSyncPackageToPreservation = $( Get-CSScriptDirectory -File "sync-cs-packagetopreservation.ps1" )
    $CSGet321ChildItemPackages = $( Get-CSScriptDirectory -File "get-321childitempackages.ps1" )

    If ( ( $aObjects | Measure-Object ).Count -eq 0 ) {
        $aObjects = @( Get-Item -LiteralPath:. -Force )
    }
    $aObjects = ( $aObjects | & "${CSGet321ChildItemPackages}" )

    $oo = ( $aObjects | & "${CSGetPackages}" -Check321 |% {
        If ( $_ | & "${CSTestPackageIs}" -Not -Bagged -Mirrored -Zipped -InCloud ) {
            $FGColor = "Yellow"
            $_ | Write-Output
        }
        Else {
            $FGColor = "Green"
        }
        $_ | & "${CSWritePackagesReport}" | Write-Host -ForegroundColor:$FGColor -BackgroundColor:Black
    } )

    If ( -Not $Report ) {
        "" | Write-Host -ForegroundColor:Cyan
        If ( ( $oo | Measure-Object ).Count -gt 0 ) {
            "=== 3-2-1 Digital Preservation ===" | Write-Host -ForegroundColor:Cyan
            $oo |% {
                $_ | & "${CSWritePackagesReport}" | Write-Host -ForegroundColor:Yellow -BackgroundColor:Black
                If ( $Batch -or ( & read-yesfromhost-cs.ps1 -Prompt:"Proceed to 3-2-1 digital preservation steps" -DefaultInput:"Y" -Timeout:60 ) ) {
                    $_ | & "${CSSyncPackageToPreservation}" -Batch:$Batch -Automatically:@( "zip" ) -InputDefault:"Y" -InputTimeout:60 -Context:"321"
                }
            }
        }
        Else {
            "~~~ 3-2-1 Digital Preservation: all packages appear to be 3-2-1 preserved ~~~" | Write-Host -ForegroundColor:Blue
        }

    }

    Exit $ExitCode
}
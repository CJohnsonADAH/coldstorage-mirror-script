<#
.SYNOPSIS
ADAHColdStorage Digital Preservation Packages compression script
@version 2025.0116

.PARAMETER Skip
coldstorage zip -Skip allows you to bypass potentially time-consuming steps in the process, like clamav scans, bagit validation, and zip checksum validation. Usually you shouldn't. They're important.

.DESCRIPTION
coldstorage-zip-packages compress: Zip preservation packages into cloud storage-formatted archival units
coldstorage-zip-packages uncache: Replace original binary archive of a zipped package with a reference to the copy uploaded to cloud storage
#>

Using Module ".\ColdStorageProgress.psm1"

Param (
    [switch] $Items = $false,
    [switch] $Help = $false,
    [switch] $Quiet = $false,
	[switch] $Batch = $false,
    [switch] $Interactive = $false,
    [String[]] $Skip = @(), 
    [switch] $Recurse = $false,
    [switch] $Force = $false,
    [switch] $PassThru = $false,
    [switch] $Dev = $false,
    [switch] $Bork = $false,
    [switch] $WhatIf = $false,
    [switch] $Version = $false,
    [Parameter(Position=0)] $Verb,
    [Parameter(ValueFromRemainingArguments=$true, Position=1)] $Words,
    [Parameter(ValueFromPipeline=$true)] $Piped
)

$Verbose = ( $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent )
$Verbose = $( If ( $Verbose -eq $null ) { $false } Else { $Verbose } )
$Debug = ( $PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent )
$Debug = $( If ( $Debug -eq $null ) { $false } Else { $Debug } )

$global:gBucketObjects = @{ }

Function Get-CSScriptDirectory {
Param ( $File=$null )
    $ScriptPath = ( Split-Path -Parent $PSCommandPath )
    If ( $File -ne $null ) { $ScriptPath = ( Join-Path "${ScriptPath}" -ChildPath "${File}" ) }
    ( Get-Item -Force -LiteralPath "${ScriptPath}" )
}
    
# Internal Dependencies - Modules
$bVerboseModules = ( $Debug -eq $true )
$bForceModules = ( ( $Debug -eq $true ) -or ( $psISE ) )

Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageInteraction.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageSettings.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageFiles.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageRepositoryLocations.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStoragePackagingConventions.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageScanFilesOK.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageBagItDirectories.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageBaggedChildItems.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageStats.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageZipArchives.psm1" )

$global:gCSScriptName = $MyInvocation.MyCommand
$global:gCSScriptPath = $MyInvocation.MyCommand.Definition

If ( $global:gScriptContextName -eq $null ) {
    $global:gScriptContextName = $global:gCSScriptName
}

Function Get-CurrentLine {
    $MyInvocation.ScriptLineNumber
}

Function Get-CSGPCommandWithVerb {
    $global:gCSGPCommandWithVerb
}

Function Get-CSScriptVersion {
Param ( [string] $Verb="", $Words=@( ), $Flags=@{ } )

    $oHelpMe = ( Get-Help ${global:gCSScriptPath} )
    $ver = ( $oHelpMe.Synopsis -split "@" |% { If ( $_ -match '^version\b' ) { $_ } } )
    If ( $ver.Count -gt 0 ) { Write-Output "${global:gCSScriptName} ${ver}" }
    Else { $oHelpMe }

}


#############################################################################################################
## COMMAND FUNCTIONS ########################################################################################
#############################################################################################################

Function Compress-CSBaggedPackage {
Param( [Parameter(ValueFromPipeline=$true)] $File, $Batch = $false, [String[]] $Skip=@(), [switch] $WhatIf )

Begin { }

Process {
    
    $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
    $Progress.Open( ( "Processing {0}" -f "${sArchive}" ), "Validating bagged preservation package", 5 )

    If ( Test-BagItFormattedDirectory -File $File ) {

        $oFile = Get-FileObject -File $File
        $sFile = Get-FileLiteralPath -File $File

        $Validated = ( Test-CSBaggedPackageValidates -DIRNAME $sFile -Skip:$Skip -NoLog )

        $Progress.Update( "Validated bagged preservation package" )
        
        If ( $Validated | Test-CSOutputForValidationErrors | Test-ShallWeContinue ) {

            $oZip = ( Get-ZippedBagOfUnzippedBag -File $oFile )

            $Result = $null

            # Idempotent: if you have created a zip of this bag before in a location that we know to look in, return that zip or its JSON placeholder
            If ( $oZip.Count -gt 0 ) {
                $asArchiveHashed = ( $oZip | Sort-Object -Property LastWriteTime -Descending |% { $oZip.FullName } )
                $sArchiveHashed = ( $asArchiveHashed | Select-Object -First 1 )
                $Result = @( [PSCustomObject] @{ "Bag"=$sFile; "Zip"=$sArchiveHashed; "Zips"=$asArchiveHashed; "New"=$false; "Validated"=$Validated; "Compressed"=$null } )
                $Progress.Update( "Located archive with MD5 Checksum", 2 )
            }
            Else {
                $Result = @( )

                $Progress.Update( "Compressing archive" )

                $oRepository = ( $oFile | Get-ZippedBagsContainer )
                $sRepository = $oRepository.FullName

                $sAlgorithm='MD5'
                $oTS = ( Get-Date )
                $sZipName = ( Get-ZippedBagNamePrefix -File $oFile -Extension:'zip' )
                If ( $sRepository ) {
        
                    $sArchive = ( $sRepository | Join-Path -ChildPath:$sZipName )

                    $Progress.Update( "Compressing archive {0}" -f $sArchive )
                    $Package = ( $sFile | Get-ItemPackage -Ascend )

                    $Package | Add-ZippedBagOfPreservationPackage -Force

                    If ( $Package.CSPackageZip ) {
                        $Package.CSPackageZip |% {

                            $oZip = $_
                            $Progress.Update( ( "Computing {0} checksum" -f $sAlgorithm ) )    
                            
                            $oZip | Add-CSFileChecksum -Algorithm:$sAlgorithm
                            $sArchiveHashed = ( $Package | Get-ZippedBagNameWithMetadata -Repository:$sRepository -TS:$oTS -Hash:( $oZip | Get-CSFileChecksum -Algorithm:$sAlgorithm ) -HashAlgorithm:$sAlgorithm )
                            If ( $sArchiveHashed ) {
                                Move-Item -LiteralPath:$oZip.FullName -Destination:$sArchiveHashed -Verbose -WhatIf:$WhatIf
                            }
                            Else {
                                ( "[Compress-CSBaggedPackage] Failed to move '{0}' to '{1}'" -f $oZip.FullName,$sArchiveHashed ) | Write-Warning
                            }
                            $Result = @( $Result ) + @( [PSCustomObject] @{ "Bag"=$sFile; "Zip"="${sArchiveHashed}"; "New"=$true; "Validated-Bag"=$Validated; "Compressed"=$oZip.CSCompressArchiveResult } )

                        }
                    }
                    Else {
                        ( "[Compress-CSBaggedPackage] Failed to compress '{0}' to '{1}'" -f $Package.FullName,$sZipName ) | Write-Warning
                     }

                }
                Else {
                    ( "[Compress-CSBaggedPackage] Could not determine destination container for path: '{0}'" -f $oFile.FullName ) | Write-Warning
                }

            }
            
            $Progress.Update( "Testing zip file integrity" )

            If ( ( $Result -ne $null ) -and ( $Result.Count -gt 0 ) ) {
                
                $Result |% {
                    $_ | Add-Member -MemberType NoteProperty -Name "Validated-Zip" -Value ( Test-ZippedBagIntegrity -File $sArchiveHashed -Skip:$Skip )
                    $_ | Write-Output
                }

            }

        }
    }
    Else {
        $sFile = $File.FullName
        Write-Warning "${sFile} is not a BagIt-formatted directory."
    }

    $Progress.Complete()

}

End { }

}

$sCommandWithVerb = ( $MyInvocation.MyCommand |% { "$_" } )
$global:gCSCommandWithVerb = $sCommandWithVerb

If ( $Verbose ) {
    $VerbosePreference = "Continue"
}

If ( $Help -eq $true ) {
    Get-CSUsageNotes -cmd $MyInvocation.MyCommand
}
ElseIf ( $Version ) {
    Get-CSScriptVersion -Verb:$Verb -Words:$Words -Flags:$MyInvocation.BoundParameters | Write-Output
}
Else {
    $t0 = date
    $sCommandWithVerb = "${sCommandWithVerb} ${Verb}"
    $global:gCSGPCommandWithVerb = $sCommandWithVerb

    If ( $Verb.Length -gt 0 ) {
        $global:gScriptContextName = $sCommandWithVerb
    }

    If ( $Verb -iin ( "test", "uncache", "get", "compress" ) ) {
        $allObjects = ( @( $Words | Where { $_ -ne $null } ) + @( $Input | Where { $_ -ne $null } ) )
    }
    Else {
        $allObjects = ( @( $Verb | Where { $_ -ne $null } ) + @( $Words | Where { $_ -ne $null } ) + @( $Input | Where { $_ -ne $null } ) )
        $Verb = "compress"
    }

    If ( $Verb -ieq "uncache" ) {
        $CSGetPackages = $( Get-CSScriptDirectory -File "coldstorage-get-packages.ps1" )
        $allObjects | & "${CSGetPackages}" -Items -Zipped -InCloud | ForEach-Object {
            $pack = $_ 
            $_ | Write-Warning
            $pack.CSPackageZip | Select-Object -First 1 | ForEach-Object {
                $ZipName = $_.FullName 
                If ( $ZipName -like '*.json' ) {
                    $NewName = $ZipName
                }
                Else {
                    $NewName = ( "{0}.json" -f $ZipName )
                }

                If ( $ZipName -ine $NewName ) {
                    $pack.CloudCopy | ConvertTo-Json | Out-File -Encoding utf8 -FilePath $ZipName
                    Move-Item $ZipName $NewName -Verbose
                }
                Else {
                    ( "JSON: {0}" -f $ZipName ) | Write-Warning
                }

                $pack.CloudCopy
            }
        }
        #|% { $pack = $_ ; $pack.CSPackageZip |% { $ZipName = $_.FullName ; If ( $ZipName -like '*.json' ) { $NewName = $ZipName } Else { $ZipName | Write-Warning ; $NewName = ( "{0}.json" -f $ZipName ) ; $pack.CloudCopy | ConvertTo-Json > $ZipName ; Move-Item $ZipName $NewName -Verbose } } }
    }
    ElseIf ( $Verb -eq "get" ) {
        $allObjects |% {
            $Package = ( $_ | Get-ItemPackage )
            $Package | Get-ZippedBagOfUnzippedBag
        }
    }
    ElseIf ( $Verb -eq "compress" ) {
        $allObjects |% {
            $sFile = Get-FileLiteralPath -File $_
            If ( Test-BagItFormattedDirectory -File $sFile ) {
                $_ | Compress-CSBaggedPackage -Skip:$Skip -WhatIf:$WhatIf
            }
            ElseIf ( Test-LooseFile -File $_ ) {
                $oBag = ( Get-BaggedCopyOfLooseFile -File $_ )
                If ($oBag) {
                    $oBag | Compress-CSBaggedPackage -Skip:$Skip
                }
                Else {
                    Write-Warning "${sFile} is a loose file not a BagIt-formatted directory."
                }
            }
            Else {
                $_ | Get-Item -Force |% { Get-BaggedChildItem -LiteralPath $_.FullName } | Compress-CSBaggedPackage -Skip:$Skip -WhatIf:$WhatIf
            }
        }
    }
}
Using Module ".\ColdStorageProgress.psm1"

Param(
    $Items,
    $Holdings=$null,
    [switch] $Debug=$false
)

Function Get-ScriptPath {
Param ( $File=$null )

    $ScriptPath = ( Split-Path -Parent $PSCommandPath )
    
    If ( $File -ne $null ) {
        $Item = ( Get-Item -Force -LiteralPath ( Join-Path "${ScriptPath}" -ChildPath "${File}" ) )
    }
    Else {
        $Item = ( Get-Item -Force -LiteralPath $ScriptPath )
    }

    $Item
}

# Internal Dependencies - Modules
$bVerboseModules = ( $Debug -eq $true )
$bForceModules = ( ( $Debug -eq $true ) -or ( $psISE ) )

Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "ColdStorageData.psm1" ).FullName )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "ColdStorageInteraction.psm1" ).FullName )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "ColdStorageSettings.psm1" ).FullName )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "ColdStorageFiles.psm1" ).FullName )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "ColdStorageMirrorFunctions.psm1" ).FullName )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "ColdStorageRepositoryLocations.psm1" ).FullName )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "ColdStoragePackagingConventions.psm1" ).FullName )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "ColdStorageScanFilesOK.psm1" ).FullName )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "ColdStorageBagItDirectories.psm1" ).FullName )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "ColdStorageBaggedChildItems.psm1" ).FullName )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "ColdStorageStats.psm1" ).FullName )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "ColdStorageZipArchives.psm1" ).FullName )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "ColdStorageToCloudStorage.psm1" ).FullName )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "ColdStorageToADPNet.psm1" ).FullName )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ( Get-ScriptPath -File "LockssPluginProperties.psm1" ).FullName )

$Workspace = $null
$Workspace = ( Get-PathToDependency -Package "Temporary-Workspace" )

$Repository = ( & coldstorage repository -Items $Items ).Repository
$Packages = ( & coldstorage packages -Items $Items -Zipped -Mirrored )

$cmd7z = ( Get-PathTo7z -Exe "7za.exe" )
$Algorithm = 'MD5'
$AlgoSlug = $Algorithm.ToLower()

$RepairExitCode = 0

$Packages |% { [PSCustomObject] @{ "MIRROR"=$_.CSPackageMirrorLocation; "ZIP"=$_.CSPackageZip } | Format-Table }

$Packages |% {

    $Item = $_
    
    $_.CSPackageZip | Sort-Object -Property Name -Unique |% {

        If ( Test-Path -LiteralPath $_ ) {

            $Zip = ( Get-Item -LiteralPath $_ -Force )
            $ZipFile = $Zip.FullName

            "[coldstorage-repair-bag] # 1. Attempting repair bag {0} from ZIP archive {1}" -f $Item.FullName,$Zip.Name | Write-Host -ForegroundColor Yellow

            $Container = ( $Zip.Directory )
            $WorkingName = ( $Zip.Name | Get-StringMD5 )
            $WorkingDir = ( Join-Path $Workspace -ChildPath $WorkingName )

            If ( -Not ( Test-Path -LiteralPath $WorkingDir ) ) {
                $WorkingDirItem = ( New-Item -ItemType Directory -Path $WorkingDir )
            }
            Else {
                $WorkingDirItem = ( Get-Item -LiteralPath $WorkingDir -Force )
            }

            $WorkingZip = ( Join-Path $WorkingDir -ChildPath $Zip.Name )

            Copy-MirroredFile -From $ZipFile -To $WorkingZip -Discard

            $Copied = ( Join-Path $WorkingDir -ChildPath $_.Name )

            If ( $Zip | Test-ZippedBagIntegrity ) {

                Push-Location $WorkingDir
                & "${cmd7z}" x "${Copied}"

                Get-ChildItem -Directory $WorkingDir |? { $data = ( Join-Path $_.FullName -ChildPath "data" ); Test-Path -LiteralPath $data } |% {
                    $Extracted = $_.FullName
                    If ( Test-Path -LiteralPath "${Extracted}" ) {

                        Push-Location "${Extracted}"
                        & bagit.ps1 --validate . -Progress ; $bagExit = $LASTEXITCODE
                        $RepairExitCode = $bagExit
                        Pop-Location

                        If ( $bagExit -eq 0 ) {

                            $Destination = $Item.FullName

                            Sync-MirroredFiles -From:"${Extracted}" -To:"${Destination}" -DiffLevel 3 -NoScan -RepositoryOf:"${Destination}"

                            "[coldstorage-repair-bag] Attempting to validate repaired bag at {0}" -f "${Destination}" | Write-Host -ForegroundColor Yellow
                            Push-Location "${Destination}"
                            & bagit.ps1 --validate . -Progress ; $bagExit = $LASTEXITCODE
                            $RepairExitCode = $bagExit
                            Pop-Location

                        }
                        Else {
                            "[coldstorage-repair-bag] FAILED: Zip repository [{0}] also contains a busted bag." -f $ZipFile | Write-Warning
                        }

                    } # If
                } # ForEach

                If ( Read-YesFromHost -Prompt "CLEAN UP: Remove extracted directory '${Extracted}'?" ) {
                    Remove-Item -Force -Verbose -Recurse "${Extracted}"
                }

                Pop-Location

            }
            Else {
                ( "[coldstorage-repair-bag] ZIP file checksum mismatch: {0} /= {1}" -f $Hash.Hash,$Hash.RecordedHash ) | Write-Warning
                $RepairExitCode = 255

            } # If 

            If ( Read-YesFromHost -Prompt "CLEAN UP: Remove copied ZIP file '${Copied}'?" ) {
                Remove-Item -Force -Verbose "${Copied}"
            }

        } # If ( Test-Path -LiteralPath $_ )
    } # ForEach
} # ForEach

Exit $RepairExitCode

# TODO: Incorporate test-for-missing-files.ps1 secondary repair / rebag script

                #    If ( $bagExit -gt 0 ) {
                #        If ( ( Read-YesFromHost -Prompt "CONFIRM: Test for Missing Files in Bag '${Extracted}' '$_'?" ) ) {
                #            test-for-missing-files.ps1 -Package:"${Package}" -Repository:$Repository -ZipFile:$ZipFile
                #            Push-Location "${Extracted}"
                #            & bagit.ps1 --validate . ; $bagExit = $LASTEXITCODE
                #            Pop-Location
                #        }
                #    }

# TODO: Use algorithm in test-file-hash-from-bagit.ps1 for checksum-validated copy / remove / recopy loop

                #    If ( $bagExit -eq 0 ) {
                #        $HoldingsDir = $HoldingsRepository
                #        $HoldingsAuxDir = $HoldingsRepositoryAux
                #        If ( $Holdings -ne $null ) {
                #            $HoldingsDir = ( Join-Path $HoldingsDir -ChildPath $Holdings )
                #            $HoldingsAuxDir = ( Join-Path $HoldingsAuxDir -ChildPath $holdings )
                #        }
                #
                #        $HoldingsDir = ( Join-Path $HoldingsDir -ChildPath "${Package}" )
                #        $HoldingsAuxDir = ( Join-Path $HoldingsAuxDir -ChildPath "${Package}" )
                #    
                #        $HoldingsDir,$HoldingsAuxDir |% {
                #
                #            $Timestamp = ( Get-Date -UFormat "%Y%m%d" )
                #            $LogContainer = "C:\Users\${env:USERNAME}\Desktop"
                #
                #            $SafePackage = ( $Package -replace '[^0-9a-zA-Z.]+','-' )
                #            $ToRemoveLogFile = ( "Errs-{0}-BagIt-Validation-{1}-TOREMOVE.log.txt" -f $SafePackage, $Timestamp )
                #            $CSVFile = ( "Errs-{0}-BagIt-Validation-{1}.csv" -f $SafePackage, $Timestamp )
                #
                #            $ToRemoveLog = ( Join-Path $LogContainer -ChildPath $ToRemoveLogFile )
                #            $CSV = ( Join-Path $LogContainer -ChildPath $CSVFile )
                #
                #            If ( ( Read-YesFromHost -Prompt "CONFIRM: ROBOCOPY '${Extracted}' '$_'?" ) ) {
                #                & copy-bag.ps1 "${Extracted}" "$_"
                #                Push-Location "$_"
                #                & bagit.ps1 --validate . -Progress -Stdout | & test-file-hash-from-bagit.ps1 -CSV "${CSV}" -Log "${ToRemoveLog}" -Source "${Extracted}" -Destination "$_" -DoIt ; $bagExit = $LASTEXITCODE
                #                Pop-Location
                #                "EXIT CODE: {0:N0}" -f $bagExit | Write-Warning
                #            } # If
                #        } # ForEach
                #    } # If
                #
                #}
                #Else {
                #    ( "I have no idea what to do! DNE: '{0}'" -f "${Extracted}" ) | Write-Error
                #}
                #
                #If ( Read-YesFromHost -Prompt "CLEAN UP: Remove copied ZIP file '${Copied}'?" ) {
                #    Remove-Item -Force -Verbose "${Copied}"
                #}
                #If ( Read-YesFromHost -Prompt "CLEAN UP: Remove extracted directory '${Extracted}'?" ) {
                #    Remove-Item -Force -Verbose -Recurse "${Extracted}"
                #}

                #Pop-Location
            #}
            #
#
#}




# Copy the needed ZIP file to the working space
# Unzip the ZIP file into the working space
# Validate the unzipped package

# restore-zipped-bag AAH_ER_022_006_AdministrativeFilesGovernmentDivision_20200103
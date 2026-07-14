Param (
    [Parameter(ValueFromPipeline=$true)] $Item,
    [int] $DiffLevel=1,
    [switch] $Batch,
    [switch] $Fast=$false,
    [switch] $Only=$false,
    [switch] $Force=$false,
    [switch] $Forward=$false,
    [switch] $Reverse=$false,
    [switch] $NoScan=$false,
    [switch] $RoboCopy=$false,
    [switch] $Scheduled=$false,
    $Context = $null,
    [switch] $WhatIf
)

Begin {
    $ExitCode = 0

    $global:gColdStorageSyncItemToMirrorCmd = $MyInvocation.MyCommand

        $modSource = ( $global:gColdStorageSyncItemToMirrorCmd.Source | Get-Item -Force )
        $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" ) -Force # Get-FileObject # ConvertTo-CSFileSystemPath # Resolve-PathRelativeTo
    Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageRepositoryLocations.psm1" ) -Force # Get-FileRepositoryLocation, Get-FileRepositoryName, Get-MirrorMatchedItem
    Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" ) -Force # Test-LooseFile # Get-ItemPackage
    Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageMirrorFunctions.psm1" ) # Sync-MirroredFiles
    Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageData.psm1" ) -Force # Get-CSDebugContext

    $sContext = $Context
    If ( $sContext -eq $null ) {
        $sContext = $MyInvocation.MyCommand.Name
    }

}

Process {
    $File = ( $Item | Get-FileObject )

    If ( $File ) {

            $oRepository = ( Get-FileRepositoryLocation -File $File )
            $sRepository = $oRepository.FullName
            $RepositorySlug = ( Get-FileRepositoryName -File $File )

            $Original = ( $File | Get-MirrorMatchedItem -Pair:$RepositorySlug -Original -All )
            If ( -Not $Forward ) {
                $Reflection = ( $File | Get-MirrorMatchedItem -Pair:$RepositorySlug -Reflection -All )
            }
            Else {
                $Reflection = ( $File | Get-MirrorMatchedItem -Pair:$RepositorySlug -Forward -All )
            }

            If ( -Not $Reverse ) {
                $Src = $Original
                $Dest = $Reflection
            }
            Else {
                $Src = $Reflection
                $Dest = $Original
            }

            ( "REPOSITORY: {0} - SLUG: {1}" -f $sRepository,$RepositorySlug ) | Write-Debug

            $sSrc = ( "${Src}" | ConvertTo-CSFileSystemPath )
            $sDest = ( "${Dest}" | ConvertTo-CSFileSystemPath )

            ( "[{0}] '{1}' --> '{2}' [DIFF LEVEL: {3:N0}]" -f $sContext, $sSrc, $sDest, $DiffLevel ) | Write-Verbose

            If ( ( "${sSrc}" -ne '' ) -and ( "${sDest}" -ne '' ) ) {
                
                If ( -Not $WhatIf ) {

                    $SyncOptions = @{ "Fast"=( [bool] $Fast ) }
                    Sync-MirroredFiles -From:"${Src}" -To:"${Dest}" -DiffLevel:$DiffLevel -Batch:$Batch -Force:$Force -NoScan:$NoScan -RoboCopy:$RoboCopy -Scheduled:$Scheduled -SyncOptions:$SyncOptions
                
                    If ( ( -Not $Only ) -and ( $Src | Test-LooseFile ) ) {

                        $srcPackage = ( $Src | Get-ItemPackage -At )
                        
                        If ( $srcPackage.CSPackageAssociates.Count -gt 0 ) {

                            $srcPackage.CSPackageAssociates |? { $_ -ne $null } |? { $_.FullName -ne $srcPackage.FullName } |% {
                                $AssociatedItem = $_

                                $AIRelPath = ( $_.FullName | Resolve-PathRelativeTo -Base:$srcPackage.FullName )
                                
                                $sCmd = ( $Context ) ; If ( $sCmd -notlike '*mirror*' ) { $subVerb = "mirror " } Else { $subVerb = "" }
                                "[{0}] {1}associated item: '{2}'" -f $sCmd, $subVerb, $AIRelPath | Write-Host -ForegroundColor:Gray
                                
                                $bDoIt = ( -Not $Only )
                                If ( $Only -and ( -Not $Batch ) ) {
                                    $bDoIt = ( & read-yesfromhost-cs.ps1 -Prompt ( "MIRROR: Also mirror associated files at {0}?" -f $_.FullName ) )
                                }
                                If ( $bDoIt ) {
                                    $AssociatedItem | & sync-cs-itemtomirror.ps1 -DiffLevel:$DiffLevel -Batch:$Batch -Fast:$Fast -Force:$Force -Reverse:$Reverse -NoScan:$NoScan -RoboCopy:$RoboCopy -Scheduled:$Scheduled -Only -Context:$sContext -WhatIf:$WhatIf
                                }

                            }
                        }

                    }

                }
                Else {
                    Write-Host "(WhatIf) Sync-MirroredFiles -From '${Src}' -To '${Dest}' -DiffLevel $DiffLevel -Batch $Batch -Force $Force -NoScan:$NoScan -RoboCopy:$RoboCopy -Scheduled:$Scheduled"
                }
            }
            Else {
                ( '[{0}] ( "{1}", "{2}" ) has an empty file path parameter.' -f ( Get-CSDebugContext -Function:$MyInvocation ), $sSrc, $sDest ) | Write-Error
            }

        }
}

End {
    Exit $ExitCode
}

Using Module ".\ColdStorageProgress.psm1"

#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################


$global:gColdStorageMirrorFunctionsModuleCmd = $MyInvocation.MyCommand
    
    $modSource = ( $global:gColdStorageMirrorFunctionsModuleCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

# External Dependencies - Modules
Import-Module -Verbose:$false BitsTransfer
Import-Module -Verbose:$false Posh-SSH

# Depdencies - Script
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageRepositoryLocations.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageZipArchives.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageInteraction.psm1" )

Function Get-ScriptPath {
Param ( $Command=$null, $File=$null )

    If ( $Command -eq $null ) {
        $Command = $global:gColdStorageMirrorFunctionsModuleCmd
    }

    $Source = ( $Command.Source | Get-Item -Force )
    $Path = ( $Source.Directory | Get-Item -Force )

    If ( $File -ne $null ) {
        $Path = ($Path.FullName | Join-Path -ChildPath $File)
    }

    $Path
}

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function ConvertTo-MirroredPath {

    [CmdletBinding()]

Param ( [String] $Within, $SyncOptions=$null, [Parameter(ValueFromPipeline=$true)] $File )

    Begin {}

    Process {
        If ( $File ) {

            $oFile = Get-FileObject($File)
            $BaseTo = $Within

            $FileIsLeaf = ( Test-Path -LiteralPath $oFile.FullName -PathType Leaf )
            $ToIsContainer = ( Test-Path -LiteralPath $BaseTo -PathType Container )

            If ( $FileIsLeaf -and ( -Not $ToIsContainer ) ) {
                $BaseTo = ( $To | Split-Path -Parent )
            }

            $Rebased = ( $BaseTo | Get-FileObject | Get-ItemFileSystemLocation | Get-FileLiteralPath )        
            $Rebased = ( $Rebased | Join-Path -ChildPath $oFile.Name )

            $Rebased
        }
    }

    End {}

}

Function Sync-ItemMetadata ($From, $To, $SyncOptions=$null, $Progress=$null, [switch] $Verbose) {
    
    if (Test-Path -LiteralPath $from) {
        $oFrom = (Get-Item -Force -LiteralPath $from)

        if (Test-Path -LiteralPath $to) {
            $oTo = (Get-Item -Force -LiteralPath $to)

            $altered = $false
            if ($oTo.LastWriteTime -ne $oFrom.LastWriteTime) {
                $oTo.LastWriteTime = $oFrom.LastWriteTime
                $altered = $true
            }
            if ($oTo.CreationTime -ne $oTo.CreationTime) {
                $oTo.CreationTime = $oFrom.CreationTime
                $altered = $true
            }

            $Acl = $null
            $Acl = Get-Acl -LiteralPath $oFrom.FullName
            $oOwner = $Acl.GetOwner([System.Security.Principal.NTAccount])

            $Acl = $null
            $Acl = Get-Acl -LiteralPath $oTo.FullName
            $acl.SetOwner($oOwner)

            If ($altered -or $verbose) {
                If ( $Progress ) {
                    $Progress.Log("meta:${oFrom} => meta:${oTo}")
                }
            }
        }
        else {
            if ($verbose) {
                Write-Error "Destination ${to} does not seem to exist."
            }
        }
    }
    else {
        Write-Error "Source ${from} does not seem to exist."
    }
}

Function Copy-MirroredFile {
Param ( $From, $To, $File=$null, $Direction="over", $SyncOptions=$null, [switch] $Batch=$false, [switch] $ReadOnly=$false, $Progress=$null, [switch] $Discard=$false )

    $SourceContainer = $From
    $DestinationContainer = $To
    $FileName = $File

    $Source = $SourceContainer
    $Destination = $DestinationContainer
    If ( $FileName -ne $null ) {
        $Source = ( Join-Path $Source -ChildPath $File )
        $Destination = ( Join-Path $Destination -ChildPath $File )
        "[Copy-MirroredFile] FILENAME: {0} / SOURCE: '{1}' -> DESTINATION: '{2}'" -f $FileName,$SourceContainer,$DestinationContainer | Write-Debug
    }
    ElseIf ( Test-Path -LiteralPath $SourceContainer -PathType Leaf ) {
        $SourceContainer = ( Split-Path $Source -Parent )
        $DestinationContainer = ( Split-Path $Destination -Parent )

        $FileName = ( Split-Path $Source -Leaf )
        "[Copy-MirroredFile] FILENAME (implicit): {0} / SOURCE: '{1}' -> DESTINATION: '{2}'" -f $FileName,$SourceContainer,$DestinationContainer | Write-Debug
    }

    $o1 = ( Get-Item -Force -LiteralPath "${Source}" )

    If ( $Progress ) {
        $I0 = $Progress.I
        $Progress.Update( ( "Copying: #{0}/{1}. {2}" -f ( ( $Progress.I - $I0 + 1), ( $Progress.N - $I0 + 1), $o1.Name ) ), 0, "${CopyFrom} =>> ${CopyTo}" )
    }
    Else {
        $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
        $Progress.Open( ( "Copying Mirrored File [{0}]" -f ( ( Get-ItemFileSystemLocation $o1 ).FullName | Resolve-Path -Relative ) ),  ( "Copying: {0}" -f ( $o1.Name ) ), 1 )
    }

    If ( $o1.Count -gt 0 ) {
        
        # 0. Overwrite if present -- save the copy about to be obliterated to the Trash
        If ( ( Test-Path "${Destination}" ) -And ( -Not $Discard ) ) {
            Remove-ItemToTrash -From "${Source}"
        }

        # 1. Copy item
        If ( $Batch ) {
            Copy-Item -LiteralPath "${Source}" -Destination "${Destination}"
        }
        Else {
            $Fallback = $false

            # 1B-1. Attempt to use BITS network service
            Try {
                Start-BitsTransfer -Source "${Source}" -Destination "${Destination}" -Description "${Direction} to ${To}" -DisplayName "Copy from ${From}" -ErrorAction Stop
            }
            Catch {
                # "[Copy-MirroredFile] Failed to add BITS job due to an exception: {0}" -f $_.ToString() | Write-Error
                $Fallback = $true
            }

            # 1B-2. Attempt to use RoboCopy.exe with piped output into a progress bar
            $RoboCopy = ( Get-Command ROBOCOPY -ErrorAction SilentlyContinue )
            If ( $RoboCopy.Source -And $Fallback ) {

                $rcSource = ( Convert-Path -LiteralPath "${SourceContainer}" )
                $rcDestination = ( Convert-Path -LiteralPath "${DestinationContainer}" )
                
                If ( $File -ne $null ) {
                    & $RoboCopy.Source /DCOPY:DAT /COPY:DAT /R:4 /W:4 /Z /IS /IT "${rcSource}" "${rcDestination}" "${File}" | Write-RoboCopyOutput
                    $RoboCode = $LASTEXITCODE
                }
                Else {
                    & $RoboCopy.Source /DCOPY:DAT /COPY:DAT /R:4 /W:4 /Z /IS /IT "${rcSource}" "${rcDestination}" | Write-RoboCopyOutput
                    $RoboCode = $LASTEXITCODE
                }
                $Fallback = ( $RoboCode -ge 5 )
            }

            # 1B-3. Fall back to Copy-Item
            If ( $Fallback ) {
                Copy-Item -LiteralPath "${Source}" -Destination "${Destination}"
            }

        }
    }

    $Progress.Update( ( "Copied: #{0}/{1}. {2}" -f ( ( $Progress.I - $I0 + 1 ), ( $Progress.N - $I0 + 1 ), $o1.Name ) ), 1 )

    If ( $ReadOnly ) {
	    Try {
	    	Set-ItemProperty -Path "$to" -Name IsReadOnly -Value $true
	    }
	    Catch {
		    "[Copy-MirroredFile] setting read-only failed: ${To}" | Write-Error
	    }
    }
}

Function Copy-MirroredFilesWithMetadata {
Param ($From, $To, $SyncOptions=$null, [switch] $Batch=$false, [switch] $RoboCopy=$false, $DiffLevel=1, $Depth=0, $Progress=$null)

    $sStatus = "*.*"

    $RoboCopyExe = ( Get-Command ROBOCOPY -ErrorAction SilentlyContinue )
    $UseRoboCopy = ( $RoboCopy -And $RoboCopyExe )
    If ( $UseRoboCopy ) {

        $Progress.Update( "${sStatus} (ROBOCOPY)" )

        $rcFrom = ( Convert-Path "${From}" -ErrorAction SilentlyContinue )
        $rcTo = ( Convert-Path "${To}" -ErrorAction SilentlyContinue )
        $rcFile = $null
        If ( Test-Path -LiteralPath "${From}" -PathType Leaf ) {
            $rcFrom = ( Split-Path "${From}" -Parent )
            $rcTo = ( Split-Path "${To}" -Parent )
            $rcFrom = ( Convert-Path "${rcFrom}" -ErrorAction SilentlyContinue )
            $rcTo = ( Convert-Path "${rcTo}" -ErrorAction SilentlyContinue )
            $rcFile = ( Split-Path "${From}" -Leaf )

            If ( ( $rcFrom -ne $null ) -and ( $rcTo -ne $null ) ) {
                & $RoboCopyExe.Source /DCOPY:DAT /COPY:DAT /Z /R:2 /W:4 "${rcFrom}" "${rcTo}" "${rcFile}" | Write-RoboCopyOutput -Prolog -Epilog
            }

        }
        Else {
            If ( ( $rcFrom -ne $null ) -and ( $rcTo -ne $null ) ) {
                & $RoboCopyExe.Source /E /DCOPY:DAT /COPY:DAT /Z /R:2 /W:4 "${rcFrom}" "${rcTo}" | Write-RoboCopyOutput -Prolog -Epilog
            }

        }
    }
    Else {

        ##################################################################################################################
        ## COPY OVER (cp): Copy snapshot files onto destination to mirror files on source. ###############################
        ##################################################################################################################

        $Progress.Update( "${sStatus} (cp)" )
        Copy-MirroredFiles -From:$From -To:$To -Batch:$Batch -DiffLevel:$DiffLevel -Depth:$Depth # -Progress:$Progress

        ##################################################################################################################
        ## METADATA: Synchronize source file system meta-data to destination #############################################
        ##################################################################################################################

        $Progress.Update( "${sStatus} (meta)" )
        Sync-Metadata -From:$From -To:$To -Batch:$Batch # -Progress:$Progress

    }

}

Function Copy-MirroredFiles {
Param ($From, $To, $SyncOptions=$null, [switch] $Batch=$false, $DiffLevel=1, $Depth=0, $Progress=$null)

    "Copy-MirroredFiles FROM: {0}" -f $From | Write-Debug
    "Copy-MirroredFiles TO: {0}" -f $To | Write-Debug

    $aFiles = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aFiles = ( Get-ChildItem -File -LiteralPath "$From" )
    }
    $N = $aFiles.Count

    $newProgress = $false
    If ( $Progress -eq $null ) {
        $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
        $newProgress = $true
    }


    $sFiles = ( "file" | Get-PluralizedText($N) )
    If ( $newProgress ) {
        $matchingProgress = $Progress
    }
    Else {
        $matchingProgress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
    }
    
    $matchingProgress.Open( "Matching Files (cp) [${From} => ${To}]", ( "{0:N0} {1}" -f $N, $sFiles ), $N )
    
    $aFiles = ( $aFiles | Select-UnmatchedItems -Exclude "Thumbs[.]db" -Match "${To}" -DiffLevel $DiffLevel -Progress:$matchingProgress )

    $N = $aFiles.Count
    $matchingProgress.Complete()

    If ( $newProgress ) {
        $Progress.Open( ( "Copying Unmatched {0} [{1} => {2}]" -f $sFiles, $From, $To ), ( "{0:N0} {1}" -f $N, $sFiles ), $N )
    }
    Else {
        $Progress.InsertSegment( $N )
        $Progress.Redraw()    
    }

    $aFiles | ForEach {
        If ( $_ ) {
            $BaseName = $_.Name
            $CopyFrom = $_.FullName
            $CopyWithin = $CopyTo
            $CopyFile = $null

            $CopyTo = "${To}"
            If ( Test-Path -LiteralPath "${CopyFrom}" -PathType Leaf ) {
                $CopyFile = $BaseName
                $CopyFrom = ( $_.Directory.FullName )
                $CopyToFile = ( Split-Path "${CopyTo}" -Leaf )
                $CopyTo = ( Split-Path "${CopyTo}" -Parent )
                
                If ( $CopyToFile -eq $CopyFile ) {
                    $CopyWithin = ( Split-Path "${CopyTo}" -Parent )
                }
                Else {
                    $CopyWithin = $CopyTo
                }
            }
            $CopyTo = ( $CopyFrom | ConvertTo-MirroredPath -Within "${CopyWithin}" )

            "Copy-MirroredFiles CopyFile: {0}" -f $CopyFile | Write-Debug
            "Copy-MirroredFiles CopyFrom: {0}" -f $CopyFrom | Write-Debug
            "Copy-MirroredFiles CopyTo: {0}" -f $CopyTo | Write-Debug

            If ( -Not ( $_ | Test-UnmirroredDerivedItem -MirrorBaggedCopies ) ) {
                Copy-MirroredFile -From:${CopyFrom} -To:${CopyTo} -File:$CopyFile -Batch:${Batch} -Progress:${Progress}
            }
        }
    }
    $Progress.Complete()
}

Function Remove-ItemToTrash {
Param ( [Parameter(ValueFromPipeline=$true)] $From, [switch] $Copy=$false, $SyncOptions=$null, $RepositoryOf=$null )

    Begin {
    }

    Process {
        If ( $RepositoryOf -eq $null ) {
            $Matcher = $From
        }
        Else {
            $Matcher = $RepositoryOf
        }

        $From = Get-FileLiteralPath($From)

        $To = ($Matcher | Get-MirrorMatchedItem -Trashcan -IgnoreBagging)

        ( "Trashcan Path: {0}" -f $To ) | Write-Debug

        $TrashContainer = ( $To | Split-Path -Parent )
        If ( $TrashContainer ) {
            If ( -Not ( Test-Path -LiteralPath $TrashContainer ) ) {
                "[Remove-ItemsToTrash] Create destination container: ${TrashContainer}" | Write-Verbose
                $TrashContainer = ( New-Item -ItemType Directory -Path $TrashContainer -Force )
            }

            If ( $Copy ) {
                Copy-Item $LiteralPath $From -Destination $To -Force
            }
            Else {
                Move-Item -LiteralPath $From -Destination $To -Force
            }
        }
        Else {
            "Remove-ItemToTrash COPY={0} < {1} COULD NOT GET CONTAINER PATH [{2}]" -f $Copy,$From,$To | Write-Error
        }
    }

    End { }

}

Function Get-TombstoneFile {
Param ( [Parameter(ValueFromPipeline=$true)] $Path )

    Begin {
        $FileName = Get-TombstoneFileName
    }

    Process {
        Join-Path $Path -ChildPath $FileName
    }

    End { }
}

Function Get-TombstoneFileName {
    "removedmanifest-md5.txt"
}

Function Remove-MirroredFilesWhenObsolete {
Param ( $From, $To, $SyncOptions=$null, [switch] $Batch=$false, $Depth=0, $RepositoryOf=$null, [switch] $FromTombstone )

    ( "[mirror] Remove-MirroredFilesWhenObsolete -From:{0} -To:{1} -Batch:{2} -Depth:{3}" -f $From, $To, $Batch, $Depth ) | Write-Debug

    #$Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )

    $aDirsTo = Get-ChildItem -LiteralPath "$To"
    $N = $aDirsTo.Count

    $sFiles = ( "file" | Get-PluralizedText($N) )
    #$Progress.Open( "Matching (rm): [${To}]", ( "{0:N0} {1}" -f $N, $sFiles ), $N )

    $ToRemove = ( $aDirsTo | Select-UnmatchedItems -Match "$From" -DiffLevel 0 ) # -Progress:$Progress )
    If ( $FromTombstone ) {
        $tombstone = ( "${From}" | Get-TombstoneFile )
        If ( Test-Path -LiteralPath $tombstone ) {
            Get-Content $tombstone | ForEach-Object {
                $md5, $Path = ( "$_" -split "\s+", 2 )
                $Path = ( Join-Path "${To}" -ChildPath $Path )
                
                If ( Test-Path -LiteralPath:$Path ) {
                    $ToHash = ( Get-FileHash -LiteralPath:$Path -Algorithm:MD5 )
                    If ( $md5 -eq $ToHash.Hash ) {
                        $ToRemove = ( $ToRemove + @( ( Get-Item -LiteralPath:$ToHash.Path -Force ) ) )
                    }
                }
            }
        }
    }

    $ToRemove | ForEach {
        If ( $_ ) {
            $BaseName = $_.Name
            $MoveFrom = $_.FullName
            If ( -Not ( $_ | Test-UnmirroredDerivedItem ) ) {
                $MoveFrom | Remove-ItemToTrash -RepositoryOf:$RepositoryOf
            }
            Else {
                "[mirror:Remove-MirroredFilesWhenObsolete] SKIPPED (UNMIRRORED DERIVED ITEM): [${MoveFrom}]" | Write-Verbose
            }
        }
    }
    # $Progress.Complete()

}

Function Sync-MirroredDirectories {
Param (
    $From,
    $To,
    $DiffLevel=1,
    [switch] $Batch=$false,
    [switch] $Scheduled=$false,
    $SyncOptions=$null,
    $Depth=0
)

    $aDirs = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aDirs = Get-ChildItem -Directory -LiteralPath "$From"
    }

    $N = $aDirs.Count

    #$Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )

    $sFiles = ( "file" | Get-PluralizedText($N) )
    # $Progress.Open( "Matching (mkdir): [${From}]", ( "{0:N0} {1}" -f $N, $sFiles ), $N )

    $aDirs | Select-UnmatchedItems -Match "${To}" -DiffLevel 0 | ForEach { # -Progress:$Progress
        If ( $_ ) {
            If ( -Not ( $_ | Test-UnmirroredDerivedItem -MirrorBaggedCopies ) ) {
                $CopyFrom = $_.FullName
                $CopyTo = ($_ | ConvertTo-MirroredPath -Within "${To}")

                #If ( $Progress ) {
                #    $Progress.Log( "${CopyFrom}\\ =>> ${CopyTo}\\" )
                #}
                Copy-Item -LiteralPath "${CopyFrom}" -Destination "${CopyTo}"
            }
        }
    }
    # $Progress.Complete()
}

Function Sync-Metadata {
Param( $From, $To, $Progress=$null, $SyncOptions=$null, [switch] $Batch=$false )

    $aFiles = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aFiles = ( Get-ChildItem -LiteralPath "$From" | Select-MatchedItems -Match "${To}" -SyncOptions:$SyncOptions -DiffLevel 0 )
    }
    $N = $aFiles.Count
    $sFiles = ( "file" | Get-PluralizedText($N) )

    If ( $Progress -eq $null ) {
        $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
        $Progress.Open( "Synchronizing metadata [${From}]", ( "{0:N0} {1}" -f $N, $sFiles ), $N )
    }
    Else {
        $Progress.InsertSegment( $N + 1 )
        $Progress.Update( ( "Synchronizing metadata: {0:N0} {1} [${From}]" -f $N, $sFiles ) )
    }

    $I0 = $Progress.I
    $aFiles | ForEach  {
        $CopyFrom = $_.FullName
        $CopyTo = ($_ | ConvertTo-MirroredPath -Within "${To}")

        $Progress.Update( ( "Meta: #{0:N0}/{1:N0}. {2}" -f ( ( $Progress.I - $I0 + 1 ), $N, $_.Name ) ) )

        Sync-ItemMetadata -From "${CopyFrom}" -To "${CopyTo}" -SyncOptions:$SyncOptions -Verbose:$false -Progress:$Progress
    }
    $Progress.Complete()
}

Function Sync-MirroredFiles {
Param (
    $From,
    $To,
    $DiffLevel=1,
    $Depth=0,
    $SyncOptions=$null,
    [switch] $Batch=$false,
    [switch] $Force=$false,
    [switch] $NoScan=$false,
    $RepositoryOf=$null,
    [switch] $RoboCopy=$false,
    [switch] $AlreadyCopied=$false,
    [switch] $Scheduled=$false,
    [ScriptBlock] $TestMoveIntoBag=$null
)

    If ( $TestMoveIntoBag -eq $null ) {
        $TestMoveIntoBag = [ScriptBlock] {
            Param( $Scheduled )

            If ( $Scheduled ) {
                $YNTimeout=60
            }
            Else {
                $YNTimeout=$null
            }

            & read-yesfromhost-cs.ps1 -Prompt ( "Move {0} contents into a BagIt data payload directory?" -f "${To}" ) -Timeout:$YNTimeout
        }
    }

    $sActScanning = "Scanning contents: [${From}]"
    $sStatus = "*.*"

    If ( -Not ( Test-Path -LiteralPath "${To}" ) ) {

        If ( Test-Path -PathType Container "${From}" ) {
            $ToDir = ( New-Item -Type Directory "${To}" -Force:$Force -Verbose )
            If ( ( -Not $ToDir ) -or ( -Not ( Test-Path -LiteralPath "${To}" ) ) ) {
                $ErrMesg = ( "[{0}] Sync-MirroredFiles: Destination '{1}' could neither be found NOR created." -f $global:gCSSCriptName, $To )
                Write-Error $ErrMesg
                Return
            }
        }
        ElseIf ( Test-Path -PathType Leaf "${From}" ) {
            $ToContainer = ( Split-Path "${To}" -Parent )
            $ToDir = ( Get-Item -LiteralPath "${ToContainer}" -Force -ErrorAction SilentlyContinue )

            $FromItem = ( Get-Item -LiteralPath "${From}" -Force -ErrorAction SilentlyContinue )
            If ( $FromItem ) {
                If ( -Not ( Test-Path -PathType Container "${ToContainer}" ) ) {
                    $ToDir = ( New-Item -Type Directory "${ToContainer}" -Force:$Force -Verbose )
                }
            }
           
            If ( -Not ( $ToDir ) ) {
                $ErrMesg = ( "[{0}] Sync-MirroredFiles: Destination '{1}' cannot be found?!" -f $global:gCSSCriptName, $To )
                Write-Error $ErrMesg
                Return
            }
        }
        Else {
            $ErrMesg = ( "[{0}] Sync-MirroredFiles: Source '{1}' cannot be found." -f $global:gCSSCriptName, $From )
            Write-Error $ErrMesg
            Return
        }
    }

    $sTo = $To
    If ( Test-BagItFormattedDirectory -File $To ) {

        If ( -Not ( Test-BagItFormattedDirectory -File $From ) ) {
            $oPayload = ( Get-FileObject($To) | Select-BagItPayloadDirectory )
            $To = $oPayload.FullName
        }
        Else {
            $CSGetPackages = $( Get-ScriptPath -File "coldstorage-get-packages.ps1" )

            $OKBagIt = 0
            If ( -Not $NoScan ) {
                $Bag = ( $From | & "${CSGetPackages}" validate -Items -NoValidateLog -PassThru ); $OKBagIt = $LastExitCode
            }

            If ( $OKBagIt -gt 0 ) {

                $ErrMesg = ( "[{0}] Sync-MirroredFiles: Source '{1}' no longer validates and SHOULD NOT overwrite Destination '{2}' !!!" -f $global:gCSSCriptName, $From, $To )
                Write-Error $ErrMesg
                Return

            }

        }
    }
    ElseIf ( Test-BagItFormattedDirectory -File $From ) {

        $CSGetPackages = $( Get-ScriptPath -File "coldstorage-get-packages.ps1" )

        $OKBagIt = 0
        If ( -Not $NoScan ) {
            
            $bagProgress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
            $bagProgress.Open( $sActScanning, "${From} (validating)" )

            $bagProgress.Update( $sActScanning, "${sStatus} (bagit)" )
            $Bag = ( $From | & "${CSGetPackages}" validate -Items -PassThru ); $OKBagIt = $LastExitCode
            $bagProgress.Complete()

        }

        If ( $OKBagIt -gt 0 ) {

            $ErrMesg = ( "[{0}] Sync-MirroredFiles: Source '{1}' no longer validates and SHOULD NOT overwrite Destination '{2}' !!!" -f $global:gCSSCriptName, $From, $To )
            Write-Error $ErrMesg
            Return

        }
        Else {
            $Items = ( Get-ChildItem -Force -LiteralPath "${To}" )
            If ( $Items.Count -gt 0 ) {
                $DoTheMove = $Force
                $DoTheRepair = $false

                If ( -Not $DoTheMove ) {
                    If ( -Not $Batch ) {
                        $DoTheMove = ( $TestMoveIntoBag.Invoke( $Scheduled ) )
                    }
                }
                If ( -Not $DoTheMove ) {
                    If ( -Not $Batch ) {
                        $DoTheRepair = ( Read-YesFromHost -Prompt ( "Repair {0} contents from BagIt data payload directory?" -f "${To}" ) )
                    }
                }

                If ( $DoTheMove ) {

                    $sPayload = ( Join-Path "${To}" -ChildPath "data" )
                    $oPayload = ( New-Item -Path $sPayload -ItemType Directory -Force )
                    $Items |% {
                        Move-Item $_.FullName -Destination $oPayload.FullName
                    }

                }
                Else {
                    If ( -Not $DoTheRepair ) {
                        $oPayload = ( Get-FileObject($From) | Select-BagItPayloadDirectory )
                        $From = $oPayload.FullName
                    }
                    Else {
                        # NOOP
                    }
                }

            }
        }

    }


    $Steps = @(
        "Copy-MirroredFiles"
        "Sync-Metadata"
        "Sync-MirroredDirectories"
        "Remove-MirroredFilesWhenObsolete"
        "recurse"
    )
    $nSteps = $Steps.Count

    $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
    $Progress.Open( $sActScanning, "${sStatus} (sync)", $nSteps + 1 )

    If ( -Not $AlreadyCopied ) {
        Copy-MirroredFilesWithMetadata -From:$From -To:$To -Batch:$Batch -DiffLevel:$DiffLevel -Depth:$Depth -RoboCopy:$RoboCopy -Progress:$Progress
    }

    If ( Test-MirrorSyncBidirectionally -LiteralPath $From ) {
        Copy-MirroredFilesWithMetadata -From:$To -To:$From -Batch:$Batch -DiffLevel:$DiffLevel -Depth:$Depth -RoboCopy:$RoboCopy -Progress:$Progress
        Remove-MirroredFilesWhenObsolete -From:$From -To:$To -Batch:$Batch -Depth:$Depth -RepositoryOf:$RepositoryOf -FromTombstone
        Remove-MirroredFilesWhenObsolete -From:$To -To:$From -Batch:$Batch -Depth:$Depth -RepositoryOf:$RepositoryOf -FromTombstone
    }
    Else {
        ##################################################################################################################
        ### CLEAN UP (rm): Files on destination not (no longer) on source get tossed out. ################################
        ##################################################################################################################

        $Progress.Update( $sActScanning, "${sStatus} (rm)" )
        Remove-MirroredFilesWhenObsolete -From $From -To $To -Batch:$Batch -Depth $Depth -RepositoryOf:$RepositoryOf
    }

    $RoboCopyExe = ( Get-Command ROBOCOPY -ErrorAction SilentlyContinue )
    $UseRoboCopy = ( $RoboCopy -And $RoboCopyExe -And ( Test-Path -LiteralPath "${From}" -PathType Container ) )

    If ( -Not ( $UseRoboCopy ) ) {
        ##################################################################################################################
        ## COPY OVER (mkdir): Create child directories on destination to mirror subdirectories of source. ################
        ##################################################################################################################

        $Progress.Update( "${sStatus} (mkdir)" )
        Sync-MirroredDirectories -From $From -To $To -SyncOptions:$SyncOptions -Batch:$Batch -Scheduled:$Scheduled -DiffLevel $DiffLevel -Depth $Depth
    }

    ##################################################################################################################
    ### RECURSION: Drop down into child directories and do the same mirroring down yonder. ###########################
    ##################################################################################################################

    $aFiles = @( )
    If ( Test-Path -LiteralPath "$From" -PathType Container ) {
        $aFiles = ( Get-ChildItem -Directory -LiteralPath "$From" | Select-MatchedItems -Match "$To" -SyncOptions:$SyncOptions -DiffLevel 0 )
    }


    $N = $aFiles.Count
    
    $Progress.InsertSegment( $N )
    $Progress.Redraw()

    $sFiles = ( "file" | Get-PluralizedText($N) )
    $aFiles | ForEach {
        $BaseName = $_.Name
        $MirrorFrom = $_.FullName
        $MirrorTo = ($_ | ConvertTo-MirroredPath -Within "${To}")

        $Mesg = ( "{4:N0}/{5:N0}: ${BaseName}" )
        $Progress.Update( $Mesg, 0 )
        $Mesg | Write-Debug
        Sync-MirroredFiles -From "${MirrorFrom}" -To "${MirrorTo}" -DiffLevel $DiffLevel -Depth ($Depth + 1) -SyncOptions:$SyncOptions -Batch:$Batch -NoScan:$NoScan -RoboCopy:$RoboCopy -AlreadyCopied:$RoboCopy
        $Progress.Update( $Mesg )
    }

    $Progress.Complete()
}


############################################################################################################
## FILE / DIRECTORY COMPARISON FUNCTIONS ###################################################################
############################################################################################################

# Is-Matched-File
Function Test-MatchedFile ($From, $To, $SyncOptions=$null, $DiffLevel=0) {

    $ToPath = $To
    If ( $To -eq $null ) {
        $ToPath = $To
    }
    ElseIf ( Get-Member -InputObject $To -name "FullName" -MemberType Properties ) {
        $ToPath = $To.FullName
    }

    $TreatAsMatched = ( Test-Path -LiteralPath "${ToPath}" )
    If ( $TreatAsMatched ) {
        $ObjectFile = (Get-Item -Force -LiteralPath "${ToPath}")
        If ( $DiffLevel -gt 0 ) {
            $TreatAsMatched = -Not ( Test-DifferentFileContent -From $From -To $ObjectFile -DiffLevel $DiffLevel )
        }
    }
    
    $TreatAsMatched

}

# Get-Unmatched-Items
Function Select-UnmatchedItems {
    [CmdletBinding()]

   Param (
    [String]
    $Match,

    [String]
    $Exclude="^$",

    [Int]
    $DiffLevel = 0,

    $SyncOptions=$null,

    $Progress=$null,

    [Parameter(ValueFromPipeline=$true)]
    $File
   )

   Begin { }

   Process {

        If ( $Progress -ne $null ) { $Progress.Update( ( "{0}" -f $File.Name ) ) }
        
        If ( $File ) {
            If ( -Not ( $File.Name -match $Exclude ) ) { 
                $Object = ($File | ConvertTo-MirroredPath -Within $Match)

                If ( -Not ( Test-MatchedFile -From:$File -To:$Object -DiffLevel:$DiffLevel ) ) {
                    $File
                }

            }
        }
   }

   End { }
}

# Get-Matched-Items
Function Select-MatchedItems {
    [CmdletBinding()]

    Param (
    [String] $Match,
    [Int] $DiffLevel = 0,
    $SyncOptions=$null,
    $Progress=$null,
    [string] $Exclude="^$",
    [Parameter(ValueFromPipeline=$true)] $File
    )

    Begin { }

    Process {
        If ( $Progress -ne $null ) { $Progress.Update( $File.Name ) }

        If ( -Not ( $File.Name -match $Exclude ) ) {
            $Object = ($File | ConvertTo-MirroredPath -Within $Match)
            If ( Test-MatchedFile -From $File -To $Object -DiffLevel $DiffLevel ) {
                $File
            }
        }
    }

    End { }

}

Function Test-UnmirroredDerivedItem {
Param( [Parameter(ValueFromPipeline=$true)] $File, $LiteralPath=$null, $SyncOptions=$null, [switch] $MirrorBaggedCopies=$false ) 

Begin { }

Process {
    $result = $false

    $Path = ( Get-FileLiteralPath -File $File )
    $oFile = ( Get-FileObject -File $File )

    If ( $Path ) {
        If ( Test-Path -PathType Container -LiteralPath $Path ) { # Directory

            If ( Test-ZippedBagsContainer -File $Path ) {
                $result = $true        
            }
            ElseIf ( $oFile | Test-ColdStoragePropsDirectory ) {
                $result = $true
            }
            ElseIf ( -Not $MirrorBaggedCopies ) {
                If ( Test-BaggedCopyOfLooseFile -File $oFile ) {
                    $result = $true
                }
            }

        }
        Else { # File

            If ( Test-ZippedBag -LiteralPath $Path ) {
                $result = $true
            }
            ElseIf ( $oFile | Test-ColdStorageRepositoryPropsFile ) {
                $result = $true
            }

        }
    }

    $result

}

    End {
        If ( $LiteralPath.Count -gt 0 ) {
            $LiteralPath | Test-UnmirroredDerivedItem -LiteralPath:$null -SyncOptions:$SyncOptions -MirrorBaggedCopies:$MirrorBaggedCopies
        }
    }

}

Function Test-MirrorSyncBidirectionally {
Param ( $LiteralPath, $SyncOptions=$null )

    $package = ( Get-Item -LiteralPath $LiteralPath | Get-ItemPackage -Ascend )
    $patterns = ( & get-coldstorage-setting.ps1 -Name:MirrorWildcards )

    $Bidi = $false
    
    If ( $package.FullName ) {

        If ( Test-Path -LiteralPath $package.FullName -PathType Container ) {
    
            $patterns.Bidi |% {
                $ChildPath = ( $_ | ConvertTo-ColdStorageSettingsFilePath )
        
                Push-Location $package.FullName
                $RelPath = ( Resolve-Path -Relative $LiteralPath )
                Pop-Location

                $Bidi = ( $Bidi -or ( $RelPath -like $ChildPath ) )
            }
        }

    }

    $Bidi
}

Export-ModuleMember -Function ConvertTo-MirroredPath
Export-ModuleMember -Function Sync-ItemMetadata
Export-ModuleMember -Function Copy-MirroredFile
Export-ModuleMember -Function Copy-MirroredFiles
Export-ModuleMember -Function Test-MatchedFile
Export-ModuleMember -Function Select-UnmatchedItems
Export-ModuleMember -Function Select-MatchedItems
Export-ModuleMember -Function Test-UnmirroredDerivedItem
Export-ModuleMember -Function Remove-ItemToTrash
Export-ModuleMember -Function Remove-MirroredFilesWhenObsolete
Export-ModuleMember -Function Sync-MirroredDirectories
Export-ModuleMember -Function Sync-Metadata
Export-ModuleMember -Function Sync-MirroredFiles

Export-ModuleMember -Function Test-MirrorSyncBidirectionally

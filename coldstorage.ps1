<#
.Description
Sync files to or from the ColdStorage server.
#>
param (
    [switch] $Help = $false,
    [switch] $Quiet = $false
)

# coldstorage
#
# Last-Modified: 30 Quintilis 2020

Import-Module BitsTransfer

$ColdStorageER = "\\ADAHColdStorage\ADAHDATA\ElectronicRecords"
$ColdStorageDA = "\\ADAHColdStorage\ADAHDATA\Digitization"
$ColdStorageBackup = "\\ADAHColdStorage\Share\ColdStorageMirroredBackup"

$mirrors = @{
    Processed=( "ER", "\\ADAHFS3\Data\Permanent", "${ColdStorageER}\Processed" )
    Working_ER=( "ER", "${ColdStorageER}\Working-Mirror", "\\ADAHFS3\Data\ArchivesDiv\PermanentWorking" )
    Unprocessed=( "ER", "\\ADAHFS1\PermanentBackup\Unprocessed", "${ColdStorageER}\Unprocessed" )
    Masters=( "DA", "${ColdStorageDA}\Masters", "\\ADAHFS3\Data\DigitalMasters" )
    Access=( "DA", "${ColdStorageDA}\Access", "\\ADAHFS3\Data\DigitalAccess" )
    Working_DA=( "DA", "${ColdStorageDA}\Working-Mirror", "\\ADAHFS3\Data\DigitalWorking" )
}

# Bleep Bleep Bleep Bleep Bleep Bleep -- BLOOP!
function Do-Bleep-Bloop () {
    [console]::beep(659,250) ##E
    [console]::beep(659,250) ##E
    [console]::beep(659,300) ##E
    [console]::beep(523,250) ##C
    [console]::beep(659,250) ##E
    [console]::beep(784,300) ##G
    [console]::beep(392,300) ##g
    [console]::beep(523,275) ## C
    [console]::beep(392,275) ##g
    [console]::beep(330,275) ##e
    [console]::beep(440,250) ##a
    [console]::beep(494,250) ##b
    [console]::beep(466,275) ##a#
    [console]::beep(440,275) ##a
}

function Do-Copy-Snapshot-File ($from, $to, $direction="over") {
    $o1 = ( Get-Item -LiteralPath "${from}" )
    $o2 = ( Get-Item -Path "${from}" )

    if ( $o1.Count -eq $o2.Count ) {
        try {
            Start-BitsTransfer -Source "${from}" -Destination "${to}" -Description "$direction to $to" -DisplayName "Copy from $from" -ErrorAction Stop
        } catch {
            Write-Error "Start-BitsTransfer raised an exception"
        }
    }

    if ( -Not ( Test-Path -LiteralPath "${to}" ) ) {
        Write-Error "Attempting to fall back to Copy-Item"
        Copy-Item -LiteralPath "${from}" -Destination "${to}"
    }

	#try {
	#	Set-ItemProperty -Path "$to" -Name IsReadOnly -Value $true
	#}
	#catch {
	#	Write-Error "setting read-only failed: $to"
	#}
}

function Do-Reset-Metadata ($from, $to, $verbose) {
    
    if (Test-Path -LiteralPath $from) {
        $oFrom = (Get-Item -LiteralPath $from)

        if (Test-Path -LiteralPath $to) {
            $oTo = (Get-Item -LiteralPath $to)

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

            if ($altered -or $verbse) {
                Write-Output "meta:${oFrom} => meta:${oTo}"
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

function Sync-Metadata ($from, $to, $verbose) {
    Get-ChildItem -Recurse "$from" | ForEach-Object -Process {

        $LocalFile = $_.FullName
        $LocalSrcDir = Split-Path -Parent $LocalFile
        $LocalSrcDirParent = Split-Path -Parent $LocalFile
        $LocalSrcDirRelPath = ""
        while ($LocalSrcDirParent -ne $from) {
            $LocalSrcDirStem = Split-Path -Leaf $LocalSrcDirParent
            $LocalSrcDirParent = Split-Path -Parent $LocalSrcDirParent
            $LocalSrcDirRelPath = "${LocalSrcDirStem}\${LocalSrcDirRelPath}"
        }

		$Basename = Split-Path -Leaf $LocalFile

        $DestinationTargetPath = "${to}\${LocalSrcDirRelPath}${Basename}"

        Set-Location $LocalSrcDir
        Do-Reset-Metadata $_.FullName $DestinationTargetPath $verbose
    }
}

function Get-Unmatched-Dirs {
    [CmdletBinding()]

   param (
    [String]
    $Match,

    [Parameter(ValueFromPipeline=$true)]
    $File
   )

   Begin {}

   Process {
    $BaseName = $File.Name
    $Object = $Match + "\" + $BaseName

    if ( -Not ( Test-Path -LiteralPath "$Object" ) ) {
        $File
    }
   }

   End {}
}

function Get-Matched-Dirs {
    [CmdletBinding()]

   param (
    [String]
    $Match,

    [Parameter(ValueFromPipeline=$true)]
    $File
   )

   Begin {}

   Process {
    $BaseName = $File.BaseName
    $Object = $Match + "\" + $BaseName

    if ( Test-Path -LiteralPath "$Object" ) {
        $File
    }
   }

   End {}
}

function Rebase-File {
    [CmdletBinding()]

   param (
    [String]
    $To,

    [Parameter(ValueFromPipeline=$true)]
    $File
   )

   Begin {}

   Process {
    $BaseName = $File.Name
    $Object = $To + "\" + $BaseName
    $Object
   }

   End {}
}

function Do-Mirror-Child-Dirs ($From, $To, $Trashcan, $Depth=0) {
    $IdBase = (10 * $Depth)
    if ($Depth -gt 0) {
        $RootedIdBase = 10
    } else {
        $RootedIdBase = 0
    }

    Write-Progress -Id ($RootedIdBase + 2) -Activity "Scanning contents: [${From}]" -Status "*.*" -percentComplete 0

    $Level = ("="*$Depth)
    if ($Depth -gt 0) {
        $DirLevelHeader = $Level + " " + $From + " " + $Level
    } else {
        $DirLevelHeader = ""
    }

    Get-ChildItem -Directory -LiteralPath "$To" | Get-Unmatched-Dirs -Match "$From" | ForEach {
        if ($DirLevelHeader) {
            $DirLevelHeader
            $DirLevelHeader=""
        }
        $BaseName = $_.Name
        $MoveFrom = $_.FullName
        $MoveTo = ($_ | Rebase-File -To $Trashcan)
        "Move-Item -LiteralPath $MoveFrom -Destination $MoveTo -Force"
        if ( -Not ( Test-Path -LiteralPath $Trashcan ) ) {
            mkdir $Trashcan
        }
        Move-Item -LiteralPath $MoveFrom -Destination $MoveTo -Force
    }

    Write-Progress -Id ($RootedIdBase + 2) -Activity "Scanning contents: [${From}]" -Status "*.*" -percentComplete 20

    Get-ChildItem -Directory -LiteralPath "$From" | Get-Unmatched-Dirs -Match "${To}" | ForEach {
        if ($DirLevelHeader) {
            $DirLevelHeader
            $DirLevelHeader=""
        }

        $CopyFrom = $_.FullName
        $CopyTo = ($_ | Rebase-File -To "${To}")

        Write-Output "${CopyFrom} =>\> ${CopyTo}"
        Copy-Item -LiteralPath "${CopyFrom}" -Destination "${CopyTo}"
    }

    Write-Progress -Id ($RootedIdBase + 2) -Activity "Scanning contents: [${From}]" -Status "*.*" -percentComplete 40

    $i = 0
    $aFiles = ( Get-ChildItem -File -LiteralPath "$From" | Get-Unmatched-Dirs -Match "${To}"  )
    $N = $aFiles.Count

    $aFiles | ForEach {
        $BaseName = $_.Name
        $CopyFrom = $_.FullName
        $CopyTo = ($_ | Rebase-File -To "${To}")
        
        Write-Progress -Id ($IdBase + 3) -Activity "Copying Unmatched Files [${From}]" -Status "${BaseName}" -percentComplete (100*$i / $N)
        $i = $i + 1

        if ($DirLevelHeader) {
            $DirLevelHeader
            $DirLevelHeader=""
        }
        Write-Output "${CopyFrom} =>> ${CopyTo}"
        
        Do-Copy-Snapshot-File "${CopyFrom}" "${CopyTo}"
        
    }
    Write-Progress -Id ($IdBase + 3) -Activity "Copying Unmatched Files [${From}]" -Completed

    Write-Progress -Id ($RootedIdBase + 2) -Activity "Scanning contents: [${From}]" -Status "*.*" -percentComplete 60

    $i = 0
    $aFiles = ( Get-ChildItem -LiteralPath "$From" | Get-Matched-Dirs -Match "${To}" )
    $N = $aFiles.Count

   $aFiles | ForEach  {
        $BaseName = $_.Name
        $CopyFrom = $_.FullName
        $CopyTo = ($_ | Rebase-File -To "${To}")

        Write-Progress -Id ($IdBase + 1) -Activity "Synchronizing metadata [${From}]" -Status "${BaseName}" -percentComplete (100*$i / $N)
        $i = $i + 1

        Do-Reset-Metadata -from "${CopyFrom}" -to "${CopyTo}" -verbose $false        
    }
    Write-Progress -Id ($IdBase + 1) -Activity "Synchronizing metadata [${From}]" -Completed

    Write-Progress -Id ($RootedIdBase + 2) -Activity "Scanning contents: [${From}]" -Status "*.*" -percentComplete 80

    $i = 0
    $aFiles = ( Get-ChildItem -Directory -LiteralPath "$From" | Get-Matched-Dirs -Match "$To" )
    $N = $aFiles.Count
    
    $aFiles | ForEach {
        $BaseName = $_.Name
        $MirrorFrom = $_.FullName
        $MirrorTo = ($_ | Rebase-File -To "${To}")
        $MirrorTrash = ($_ | Rebase-File -To "${Trashcan}")

        $i = $i + 1
        Write-Progress -Id ($RootedIdBase + 2) -Activity "Recursing into subdirectories [${From}]" -Status "${BaseName}" -percentComplete (100*$i / $N)

        Do-Mirror-Child-Dirs -From "${MirrorFrom}" -To "${MirrorTo}" -Trashcan "${MirrorTrash}" -Depth ($Depth + 1)
    }
    Write-Progress -Id ($RootedIdBase + 2) -Activity "Recursing into subdirectories [${From}]" -Completed
}

function Do-Mirror ($Pairs=$null) {

    if ( $Pairs.Count -lt 1 ) {
        $Pairs = $mirrors.Keys
    }

    $i = 0
    $N = $Pairs.Count
    $Pairs | ForEach {
        $Pair = $_
        if ( $mirrors.ContainsKey($Pair) ) {
            $locations = $mirrors[$Pair]

            $slug = $locations[0]
            $src = $locations[2]
            $dest = $locations[1]
            $TrashcanLocation = "${ColdStorageBackup}\${slug}_${Pair}"

            if ( -Not ( Test-Path -LiteralPath "${TrashcanLocation}" ) ) { 
                mkdir "${TrashcanLocation}"
            }

            Write-Progress -Id 1138 -Activity "Mirroring between ADAHFS servers and ColdStorage" -Status "Location: ${Pair}" -percentComplete ( 100 * $i / $N )
            Do-Mirror-Child-Dirs -From "${src}" -To "${dest}" -Trashcan "${TrashcanLocation}"
        } else {
            $recurseInto = @( )
            $mirrors.Keys | ForEach {
                $subPair = $_
                $locations = $mirrors[$subPair]
                $slug = $locations[0]
                $src = $locations[2]
                $dest = $locations[1]

                if ( $slug -eq $Pair ) {
                    $recurseInto += @( $subPair )
                }
            }
            Do-Mirror -Pairs $recurseInto
        } # if
        $i = $i + 1
    }
    Write-Progress -Id 1138 -Activity "Mirroring between ADAHFS servers and ColdStorage" -Completed
}

function Do-Clear-And-Bag {

    [Cmdletbinding()]

param (
    [Switch]
    $Quiet,

    [String]
    $Exclude="^$",

    [Parameter(ValueFromPipeline=$true)]
    $File
)

    Begin {
        if ( $Exclude.Length -eq 0 ) {
            $Exclude = "^$"
        }
    }

    Process {
        $Anchor = $PWD

        $DirName = $File.FullName
        $BaseName = $File.Name
        if ( $BaseName -match "^[A-Za-z0-9]{2,3}_ER" ) {
            if ( -not ( $BaseName -match $Exclude ) ) {
                $DirParts = $BaseName.Split("_")
                $CURNAME = $DirParts[0]
                $ERType = $DirParts[1]
                $ERCreator = $DirParts[2]
                $ERCreatorInstance = $DirParts[3]
                $Slug = $DirParts[4]

                $ERCode = $ERType + "-" + $ERCreator + "-" + $ERCreatorInstance

                chdir $DirName

                $DataDir = "${DirName}\bagit.txt"
                if ( Test-Path -LiteralPath "$DataDir" ) {
                    if ( $Quiet -eq $false ) {
                        Write-Output "BAGGED: ${ERCode}, $DirName"
                    }
                } else {
                    Write-Output "UNBAGGED: ${ERCode}, $DirName"
                    
                    $NotOK = ( $DirName | Do-Scan-ERInstance )
                    if ( $NotOK.Count -gt 0 ) {
                        Do-Bleep-Bloop
                        $ShouldWeContinue = Read-Host "Exit Code ${NotOK}, Continue (Y/N)? "
                    } else {
                        $ShouldWeContinue = "Y"
                    }

                    if ( $ShouldWeContinue -eq "Y" ) {
                        Do-Bag-ERInstance $DirName
                    }

                }
            } elseif ( $Quiet -eq $false ) {
                Write-Output "SKIPPED: ${ERCode}, $DirName"
            }

            chdir $Anchor
        }
    }

    End {
    }
}

function Bagged-File-Path {
    param (
        [Switch]
        $FullName,

        [Switch]
        $Wildcard,

        [Parameter(ValueFromPipeline=$true)]
        $File
    )

    Begin { }

    Process {
        $Prefix = ""
        if ( $FullName ) {
            $Prefix = $File.Directory
            $Prefix = "${Prefix}\"
        }
        $FileName = $File.Name
        $FileName = ( $FileName -replace "[^A-Za-z0-9]", "_" )
        
        if ( $Wildcard ) {
            # 4 = YYYY, 2 = mm, 2 = dd, 2 = HH, 2 = MM, 2 = SS
            $Suffix = ( "[0-9]" * ( 4 + 2 + 2 + 2 + 2 + 2) )
        } else {
            $DateStamp = ( Date -UFormat "%Y%m%d%H%M%S" )
            $Suffix = "${DateStamp}"
        }
        $Suffix = "_bagged_${Suffix}"

        "${Prefix}${FileName}${Suffix}"
    }

    End { }
}

function Do-Scan-File-For-Bags {
    [CmdletBinding()]

param (
    [Switch]
    $Quiet,

    [String]
    $Exclude="^$",

    [ScriptBlock]
    $OnBagged={ Param($File, $Payload, $BagDir); $FilePath = $File.FullName; $PayloadPath = $Payload.FullName; Write-Output "BAGGED: ${FilePath} = ${PayloadPath}" },

    [ScriptBlock]
    $OnDiff={ Param($File, $Payload, $LeftHash, $RightHash); },

    [ScriptBlock]
    $OnUnbagged={ Param($File); $FilePath = $File.FullName; Write-Output "UNBAGGED: ${FilePath}" },

    [Parameter(ValueFromPipeline=$true)]
    $File
)

    Begin {
        if ( $Exclude.Length -eq 0 ) {
            $Exclude = "^$"
        }
    }

    Process {
        $Anchor = $PWD
        
        $Parent = $File.Directory
        chdir $Parent

        $FileName = $File.Name
        $FilePath = $File.FullName
        $CardBag = ( $File | Bagged-File-Path -Wildcard )

        $BagPayload = $null
        if ( Test-Path -Path $CardBag ) {
            Dir -Path $CardBag | ForEach {
                $BagPath = $_
                $BagData = $BagPath.FullName + "\data"
                if ( Test-Path -LiteralPath $BagData ) {
                    $BagPayloadPath = "${BagData}\${FileName}"
                    if ( Test-Path -LiteralPath $BagPayloadPath ) {
                    
                        $LeftHash = Get-FileHash -LiteralPath $File
                        $RightHash = Get-FileHash -LiteralPath $BagPayloadPath

                        if ( $LeftHash.hash -eq $RightHash.hash ) {
                            $BagPayload = ( Get-Item -LiteralPath $BagPayloadPath )
                            $OnBagged.Invoke($File, $BagPayload, $BagPath)
                        } else {
                            $OnDiff.Invoke($File, $(Get-Item $BagPayloadPath), $LeftHash, $RightHash )
                        }
                    }
                }
            }
        }

        if ( -Not $BagPayload ) {
            $OnUnbagged.Invoke($File)
        }

        chdir $Anchor
    }

    End {
        if ( $Quiet -eq $false ) {
            Do-Bleep-Bloop
        }
    }

}

function Select-Unbagged-Dirs () {

    [CmdletBinding()]

    param (
        [Parameter(ValueFromPipeline=$true)]
        $File
    )

    Begin { }

    Process {
        $BaseName = $File.Name
        if ( -Not ( $BaseName -match "_bagged_[0-9]+$" ) ) {
            $BaseName
        }
    }

    End { }

}

function Do-Scan-Dir-For-Bags {

    [CmdletBinding()]

param (
    [Switch]
    $Quiet,

    [String]
    $Exclude="^$",

    [Parameter(ValueFromPipeline=$true)]
    $File
)

    Begin {
        if ( $Exclude.Length -eq 0 ) {
            $Exclude = "^$"
        }
    }

    Process {
        $Anchor = $PWD

        $DirName = $File.FullName
        $BaseName = $File.Name

        # Is this an ER Instance directory?
        if ( $BaseName -match "^[A-Za-z0-9]{2,3}_ER" ) {
            if ( -not ( $BaseName -match $Exclude ) ) {
                $DirParts = $BaseName.Split("_")
                $CURNAME = $DirParts[0]
                $ERType = $DirParts[1]
                $ERCreator = $DirParts[2]
                $ERCreatorInstance = $DirParts[3]
                $Slug = $DirParts[4]

                $ERCode = $ERType + "-" + $ERCreator + "-" + $ERCreatorInstance

                chdir $DirName

                $DataDir = "${DirName}\bagit.txt"
                if ( Test-Path -LiteralPath "$DataDir" ) {
                    if ( $Quiet -eq $false ) {
                        Write-Output "BAGGED: ${ERCode}, $DirName"
                    }
                } else {
                    Write-Output "UNBAGGED: ${ERCode}, $DirName"
                }
            } elseif ( $Quiet -eq $false ) {
                Write-Output "SKIPPED: ${ERCode}, $DirName"
            }

            chdir $Anchor
        } else {
            chdir $File
            
            dir -File | Do-Scan-File-For-Bags
            dir -Directory | Select-Unbagged-Dirs | Do-Scan-Dir-For-Bags

            chdir $Anchor
        }
    }

    End {
        if ( $Quiet -eq $false ) {
            Do-Bleep-Bloop
        }
    }
}

function Do-Scan-ERInstance () {
    [CmdletBinding()]

param (
    [Parameter(ValueFromPipeline=$true)]
    $Path
)

    Begin { }

    Process {
        Write-Host "ClamAV Scan: ${Path}" -InformationAction Continue
        & "C:\Users\charlesw.johnson\OneDrive - Alabama OIT\clamav-0.102.3-win-x64-portable\clamscan.exe" --stdout --bell --suppress-ok-results --recursive "${Path}" | Write-Host
        if ( $LastExitCode -ne 0 ) {
            $LastExitCode
        }
    }

    End { }
}

function Do-Validate-Bag ($DIRNAME) {

    $Anchor = $PWD
    chdir $DIRNAME

    & python.exe "${HOME}\bin\bagit\bagit.py" --validate --quiet . 2>&1
    $NotOK = $LastExitCode

    if ( $NotOK -gt 0 ) {
        Do-Bleep-Bloop
        & python.exe "${HOME}\bin\bagit\bagit.py" --validate . 2>&1
    } else {
        Write-Host "OK-BagIt: ${DIRNAME}"
    }

    chdir $Anchor
}

function Do-Bag-ERInstance ($DIRNAME) {

    $Anchor = $PWD
    chdir $DIRNAME

    Write-Host ""
    Write-Host "BagIt: ${PWD}"
    & python.exe "${HOME}\bin\bagit\bagit.py" . 2>&1

    chdir $Anchor
}

function Do-Bag-One ($LiteralPath) {
    $Anchor = $PWD

    $Item = Get-Item -LiteralPath $LiteralPath
    
    chdir $Item.DirectoryName
    $OriginalFileName = $Item.Name
    $OriginalFullName = $Item.FullName
    $FileName = ( $Item | Bagged-File-Path )

    $BagDir = ".\${FileName}"
    if ( -Not ( Test-Path -LiteralPath $BagDir ) ) {
        $BagDir = mkdir -Path $BagDir
    }

    Move-Item -LiteralPath $Item -Destination $BagDir
    Do-Bag-ERInstance -DIRNAME $BagDir
    if ( $LastExitCode -eq 0 ) {
        $NewFilePath = "${BagDir}\data\${OriginalFileName}"
        if ( Test-Path -LiteralPath "${NewFilePath}" ) {
            New-Item -ItemType HardLink -Path $OriginalFullName -Target $NewFilePath
	        
            Set-ItemProperty -LiteralPath $OriginalFullName -Name IsReadOnly -Value $true
            Set-ItemProperty -LiteralPath $NewFilePath -Name IsReadOnly -Value $true
        }
    }
    chdir $Anchor
}

function Do-Bag-Repo-Dirs ($Pair, $From, $To) {
    $Anchor = $PWD

    chdir $From
    dir -Attributes Directory | Do-Clear-And-Bag -Quiet -Exclude $null
    chdir $Anchor
}

function Do-Bag ($Pairs=$null) {
    if ( $Pairs.Count -lt 1 ) {
        $Pairs = $mirrors.Keys
    }

    $i = 0
    $N = $Pairs.Count
    $Pairs | ForEach {
        $Pair = $_
        $locations = $mirrors[$Pair]

        $slug = $locations[0]
        $src = $locations[2]
        $dest = $locations[1]

        Do-Bag-Repo-Dirs -Pair "${Pair}" -From "${src}" -To "${dest}"
        $i = $i + 1
    }
}

function Do-Check-Repo-Dirs ($Pair, $From, $To) {
    $Anchor = $PWD

    chdir $From
    dir -File | Do-Scan-File-For-Bags
    dir -Directory| Do-Scan-Dir-For-Bags -Quiet -Exclude $null

    chdir $Anchor
}

function Do-Check ($Pairs=$null) {
    if ( $Pairs.Count -lt 1 ) {
        $Pairs = $mirrors.Keys
    }

    $i = 0
    $N = $Pairs.Count
    $Pairs | ForEach {
        $Pair = $_
        if ( $mirrors.ContainsKey($Pair) ) {
            $locations = $mirrors[$Pair]

            $slug = $locations[0]
            $src = $locations[2]
            $dest = $locations[1]

            Do-Check-Repo-Dirs -Pair "${Pair}" -From "${src}" -To "${dest}"
        } else {
            $recurseInto = @( )
            $mirrors.Keys | ForEach {
                $subPair = $_
                $locations = $mirrors[$subPair]
                $slug = $locations[0]
                $src = $locations[2]
                $dest = $locations[1]
        
                if ( $slug -eq $Pair ) {
                    $recurseInto += @( $subPair )
                }
            }
            Do-Check -Pairs $recurseInto
        } # if

        $i = $i + 1
    }

}

function Do-Rsync ($Pairs=$null) {
    
    if ( $Pairs.Count -lt 1 ) {
        $Pairs = $mirrors.Keys
    }
    
    $i = 0
    $N = ($Pairs.Count * 2)
    $Pairs | ForEach {
        $Pair = $_
        $locations = $mirrors[$Pair]
        
        $slug = $locations[0]
        $src = $locations[2]
        $dest = $locations[1]

        Write-Progress -Id 1137 -Activity "rsync between ADAHFS servers and ColdStorage" -Status "Location: ${Pair}" -percentComplete ( 100 * $i / $N )
        wsl -- "~/bin/coldstorage/coldstorage-mirror.bash" "${Pair}"
        $i = $i + 1 # Step 1

        Write-Progress -Id 1137 -Activity "rsync between ADAHFS servers and ColdStorage" -Status "Location: ${Pair}" -percentComplete ( 100 * $i / $N )
        Do-Mirror -Pair "${Pair}"

        $i = $i + 1 # Step 2
    }
    Write-Progress -Id 1137 -Activity "rsync between ADAHFS servers and ColdStorage" -Completed
}

function Do-Write-Usage ($cmd) {
    $Pairs = ( $mirrors.Keys -Join "|" )

    Write-Host "Usage: $cmd mirror [$Pairs]"
}

if ( $Help -eq $true ) {
    Do-Write-Usage -cmd $MyInvocation.MyCommand
} else {
    $verb = $args[0]
    $t0 = date
    
    if ( $verb -eq "mirror" ) {
        $N = ( $args.Count - 1 )
        if ( $N -gt 0 ) {
            $Words = $args[1 .. $N]
        } else {
            $Words = @( )
        }
        Do-Mirror -Pairs $Words
    } elseif ( $verb -eq "check" ) {
        $Words = @( )

        $N = ( $args.Count - 1 )
        if ( $N -gt 0 ) {
            $Words = $args[1 .. $N]
        }
        Do-Check -Pairs $Words
    } elseif ( $verb -eq "bag" ) {
        $Words = @( )

        $N = ( $args.Count - 1 )
        if ( $N -gt 0 ) {
            $Words = $args[1 .. $N]
        }
        Do-Bag -Pairs $Words
    } elseif ( $verb -eq "bleep" ) {
        Do-Bleep-Bloop
    } else {
        Do-Write-Usage -cmd $MyInvocation.MyCommand
        $Quiet = $true
    }

    $tN = date

    if ( -not $Quiet ) {
        Write-Output "Completed: ${tN}"
        Write-Output ( $tN - $t0 )
    }
}

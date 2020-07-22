Import-Module BitsTransfer

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
        $oFrom = (Get-Item $from)

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
            $Acl = Get-Acl -Path $oFrom.FullName
            $oOwner = $Acl.GetOwner([System.Security.Principal.NTAccount])

            $Acl = $null
            $Acl = Get-Acl -Path $oTo.FullName
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

$ColdStorageER = "\\ADAHColdStorage\ADAHDATA\ElectronicRecords"
$ColdStorageDA = "\\ADAHColdStorage\ADAHDATA\Digitization"
$ColdStorageBackup = "\\ADAHColdStorage\Share\ColdStorageMirroredBackup"

$mirrors = @{
    Processed=( "ER", "${ColdStorageER}\Processed", "\\ADAHFS3\Data\Permanent" )
    Working_ER=( "ER", "${ColdStorageER}\Working-Mirror", "\\ADAHFS3\Data\ArchivesDiv\PermanentWorking" )
    Unprocessed=( "ER", "${ColdStorageER}\Unprocessed", "\\ADAHFS1\PermanentBackup\Unprocessed" )
    Masters=( "DA", "${ColdStorageDA}\Masters", "\\ADAHFS3\Data\DigitalMasters" )
    Access=( "DA", "${ColdStorageDA}\Access", "\\ADAHFS3\Data\DigitalAccess" )
    Working_DA=( "DA", "${ColdStorageDA}\Working-Mirror", "\\ADAHFS3\Data\DigitalWorking" )
}

function Do-Mirror ($Pairs=$null) {

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
        $TrashcanLocation = "${ColdStorageBackup}\${slug}_${Pair}"

        if ( -Not ( Test-Path -LiteralPath "${TrashcanLocation}" ) ) { 
            mkdir "${TrashcanLocation}"
        }

        Write-Progress -Id 1138 -Activity "Mirroring between ADAHFS servers and ColdStorage" -Status "Location: ${Pair}" -percentComplete ( 100 * $i / $N )
        Do-Mirror-Child-Dirs -From "${src}" -To "${dest}" -Trashcan "${TrashcanLocation}"
        $i = $i + 1
    }
    Write-Progress -Id 1138 -Activity "Mirroring between ADAHFS servers and ColdStorage" -Completed
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

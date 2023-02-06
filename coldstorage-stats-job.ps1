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

$Processed = $mirrors["Processed"]
$Unprocessed = $mirrors["Unprocessed"]
$Masters = $mirrors["Masters"]

Function ColdStorage-Location {
Param ( $Repository )

    $aRepo = $mirrors[$Repository]

    If ( ( $aRepo[1] -Like "${ColdStorageER}\*" ) -Or ( $aRepo[1] -Like "${ColdStorageDA}\*" ) ) {
        $aRepo[1]
    }
    Else {
        $aRepo[2]
    }
}

Function ColdStorage-Zip-Location {
Param ( $Repository )

    $BaseDir = ColdStorage-Location -Repository $Repository

    If ( Test-Path -LiteralPath "${BaseDir}\ZIP" ) {
        Get-Item -Force -LiteralPath "${BaseDir}\ZIP"
    }
}

Function Get-File-Object ( $File ) {
    
    $oFile = $null
    If ( $File -is [String] ) {
        If ( Test-Path -LiteralPath "${File}" ) {
            $oFile = ( Get-Item -Force -LiteralPath "${File}" )
        }
    }
    Else {
        $oFile = $File
    }

    $oFile
}

function Is-BagIt-Formatted-Directory ( $File ) {
    $result = $false # innocent until proven guilty

    $oFile = Get-File-Object -File $File   

    $BagDir = $oFile.FullName
    if ( Test-Path -LiteralPath $BagDir -PathType Container ) {
        $PayloadDir = "${BagDir}\data"
        if ( Test-Path -LiteralPath $PayloadDir -PathType Container ) {
            $BagItTxt = "${BagDir}\bagit.txt"
            if ( Test-Path -LiteralPath $BagItTxt -PathType Leaf ) {
                $result = $true
            }
        }
    }

    return $result
}

Function Is-Zipped-Bag {

Param ( $LiteralPath )

    $oFile = Get-File-Object -File $LiteralPath

    ( ( $oFile -ne $null ) -and ( $oFile.Name -like '*_md5_*.zip' ) )
}

function Is-Indexed-Directory {
Param( $File )

    $FileObject = Get-File-Object($File)
    $FilePath = $FileObject.FullName

    $result = $false
    if ( Test-Path -LiteralPath "${FilePath}" ) {
        $NewFilePath = "${FilePath}\index.html"
        $result = Test-Path -LiteralPath "${NewFilePath}"
    }
    
    $result
}

function Is-Bagged-Indexed-Directory {
Param( $File )

    $FileObject = Get-File-Object($File)
    $FilePath = $FileObject.FullName

    $result = $false
    if ( Is-BagIt-Formatted-Directory($File) ) {
        $payloadPath = "${FilePath}\data"
        $result = Is-Indexed-Directory($payloadPath)
    }
    
    $result
}

Function Get-Bagged-ChildItem-Candidates {
Param( $LiteralPath=$null, $Path=$null, [switch] $Zipped=$false )

    If ( $Zipped ) {
        If ( $LiteralPath -ne $null ) {
            $Zips = Get-ChildItem -LiteralPath $LiteralPath -File | Select-Zipped-Bags
        }
        Else {
            $Zips = Get-ChildItem -Path $Path -File | Select-Zipped-Bags
        }
        $Zips
    }

    If ( $LiteralPath -ne $null ) {
        $Dirs = Get-ChildItem -LiteralPath $LiteralPath -Directory
    }
    Else {
        $Dirs = Get-ChildItem -Path $Path -Directory
    }
    $Dirs
}

Function Get-Bagged-ChildItem {
Param( $LiteralPath=$null, $Path=$null, [switch] $Zipped=$false )

    Get-Bagged-ChildItem-Candidates -LiteralPath:$LiteralPath -Path:$Path -Zipped:$Zipped |% {

        $Item = Get-File-Object -File $_
    Write-Progress -Id 101 -Activity "Scanning ${sRepo} for bags" -Status $Item.FullName -PercentComplete 75

        If ( Is-BagIt-Formatted-Directory($Item) ) {
            $Item
        }
        ElseIf ( Is-Zipped-Bag $Item ) {
            $Item
        }
        ElseIf ( Is-Indexed-Directory -File $Item ) {
            # NOOP - Do not descend into an unbagged indexed directory
        }
        ElseIf ( Test-Path -LiteralPath $Item.FullName -PathType Container ) {
            # Descend to next directory level
            Get-Bagged-ChildItem -LiteralPath $Item.FullName
        }
    }

}

"Processed","Unprocessed", "Masters" |% {

    Write-Progress -Id 101 -Activity "Scanning ${sRepo}"
    $sRepo = $_

    Write-Progress -Id 101 -Activity "Scanning ${sRepo}" -Status "Getting locations" -PercentComplete 0

    Write-Progress -Id 101 -Activity "Scanning ${sRepo}" -Status "Counting zipped bags" -PercentComplete 50

    $ZipLocation = ( ColdStorage-Zip-Location -Repository $_ )
    If ( $ZipLocation ) {
        $nZipped = ( Get-ChildItem -LiteralPath $ZipLocation.FullName ).Count
    }
    Else {
        $nZipped = 0
    }

    Write-Progress -Id 101 -Activity "Scanning ${sRepo}" -Status "Counting bags" -PercentComplete 75
    
    $Location = ( Get-Item -Force -LiteralPath ( ColdStorage-Location -Repository $_ ) )

    $nBagged = ( Get-Bagged-ChildItem -LiteralPath $Location.FullName ).Count

    Write-Progress -Id 101 -Activity "Scanning ${sRepo}" -Status "Writing object" -PercentComplete 100
   
    @{} | Select-Object @{n='Location';e={ $sRepo }}, @{n='Bagged';e={ $nBagged }}, @{n='Zipped';e={ $nZipped }}

    Write-Progress -Id 101 -Activity "Scanning ${sRepo}" -Status "Writing object" -PercentComplete 100 -Completed
   
}
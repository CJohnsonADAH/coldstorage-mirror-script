#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################

Function My-Script-Directory {
Param ( $Command, $File=$null )

    $Source = ( $Command.Source | Get-Item -Force )
    $Path = ( $Source.Directory | Get-Item -Force )

    If ( $File -ne $null ) {
        $Path = ($Path.FullName + "\" + $File)
    }

    $Path
}

#############################################################################################################
## DATA #####################################################################################################
#############################################################################################################

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

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Get-ColdStorageRepositories () {
    $mirrors
}

Function Get-ColdStorageLocation {
Param ( $Repository )

    $aRepo = $mirrors[$Repository]

    If ( ( $aRepo[1] -Like "${ColdStorageER}\*" ) -Or ( $aRepo[1] -Like "${ColdStorageDA}\*" ) ) {
        $aRepo[1]
    }
    Else {
        $aRepo[2]
    }
}

Function Get-ColdStorageZipLocation {
Param ( $Repository )

    $BaseDir = Get-ColdStorageLocation -Repository $Repository

    If ( Test-Path -LiteralPath "${BaseDir}\ZIP" ) {
        Get-Item -Force -LiteralPath "${BaseDir}\ZIP"
    }
}

Export-ModuleMember -Function Get-ColdStorageRepositories
Export-ModuleMember -Function Get-ColdStorageLocation
Export-ModuleMember -Function Get-ColdStorageZipLocation


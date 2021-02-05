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

$ColdStorageData = "\\ADAHColdStorage\ADAHDATA"
$ColdStorageDataER = "${ColdStorageData}\ElectronicRecords"
$ColdStorageDataDA = "${ColdStorageData}\Digitization"
$ColdStorageER = "\\ADAHColdStorage\ElectronicRecords"
$ColdStorageDA = "\\ADAHColdStorage\Digitization"
$ColdStorageBackup = "\\ADAHColdStorage\Share\ColdStorageMirroredBackup"

$mirrors = @{
    Processed=( "ER", "\\ADAHFS3\Data\Permanent", "${ColdStorageDataER}\Processed" )
    Unprocessed=( "ER", "\\ADAHFS1\PermanentBackup\Unprocessed", "${ColdStorageDataER}\Unprocessed" )
    Working_ER=( "ER", "${ColdStorageDataER}\Working-Mirror", "\\ADAHFS3\Data\ArchivesDiv\PermanentWorking" )
    Masters=( "DA", "${ColdStorageDataDA}\Masters", "\\ADAHFS3\Data\DigitalMasters" )
    Access=( "DA", "${ColdStorageDataDA}\Access", "\\ADAHFS3\Data\DigitalAccess" )
    Working_DA=( "DA", "${ColdStorageDataDA}\Working-Mirror", "\\ADAHFS3\Data\DigitalWorking" )
}
$RepositoryAliases = @{
    Processed=( "${ColdStorageER}\Processed", "${ColdStorageDataER}\Processed" )
    Working_ER=( "${ColdStorageER}\Working-Mirror", "${ColdStorageDataER}\Working-Mirror" )
    Unprocessed=( "${ColdStorageER}\Unprocessed", "${ColdStorageDataER}\Unprocessed" )
    Masters=( "${ColdStorageDA}\Masters", "${ColdStorageDataDA}\Masters" )
    Access=( "${ColdStorageDA}\Access", "${ColdStorageDataDA}\Access" )
    Working_DA=( "${ColdStorageDA}\Working-Mirror", "${ColdStorageDataDA}\Working-Mirror" )
    
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

    If ( ( $aRepo[1] -Like "${ColdStorageER}\*" ) -Or ( $aRepo[1] -Like "${ColdStorageDA}\*" ) -Or ( $aRepo[1] -Like "${ColdStorageData}\*" ) ) {
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

Function Get-FileRepositoryCandidates {
Param ( $Key, [switch] $UNC=$false )

    $mirrors = ( Get-ColdStorageRepositories )

    $repo = $mirrors[$Key][1..2]
    $aliases = $RepositoryAliases[$Key]

    ( $repo + $aliases) |% {
        $sTestRepo = ( $_ ).ToString()
        If ( $oTestRepo = Get-FileObject -File $sTestRepo ) {

            $sTestRepo # > stdout

            $sLocalTestRepo = ( $oTestRepo | Get-LocalPathFromUNC ).FullName

            If ( -Not ( $UNC ) ) {
                If ( $sTestRepo.ToUpper() -ne $sLocalTestRepo.ToUpper() ) {
                    $sLocalTestRepo # > stdout
                }
            }

        }
    }

}

Function Get-FileRepository {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $Slug=$false )

Begin { $mirrors = ( Get-ColdStorageRepositories ) }

Process {
    
    # get self if $File is a directory, parent if it is a leaf node
    $oDir = ( Get-ItemFileSystemLocation $File | Get-UNCPathResolved -ReturnObject )

    $oRepos = ( $mirrors.Keys |% {
        $sKey = $_;
        $oCands = ( Get-FileRepositoryCandidates -Key $_ );

        If ($oCands -ieq $oDir.FullName) {

            If ($Slug) { $sKey }
            Else { $oDir.FullName }
    } } )

    $oRepos
    If ( ( $oRepos.Count -lt 1 ) -and ( $oDir.Parent ) ) {
        $oDir.Parent | Get-FileRepository -Slug:$Slug
    }

}

End { }

}


Export-ModuleMember -Function Get-ColdStorageRepositories
Export-ModuleMember -Function Get-ColdStorageLocation
Export-ModuleMember -Function Get-ColdStorageZipLocation
Export-ModuleMember -Function Get-FileRepository

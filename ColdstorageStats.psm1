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

Import-Module $( My-Script-Directory -Command $MyInvocation.MyCommand -File "ColdStorageRepositoryLocations.psm1" )
Import-Module $( My-Script-Directory -Command $MyInvocation.MyCommand -File "ColdStorageBaggedChildItems.psm1" )

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Get-RepositoryStats {
Param ( [Parameter(ValueFromPipeline=$true)] $Repository, [switch] $Batch=$false )

Begin { }

Process {
    $sRepo = $Repository
    If ( -Not $Batch ) {
        Write-Progress -Id 102 -Activity "Scanning ${sRepo}"

        Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status "Getting locations" -PercentComplete 20

        Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status "Counting zipped bags" -PercentComplete 40
    }

    $ZipLocation = ( Get-ColdStorageZipLocation -Repository $Repository )
    If ( $ZipLocation ) {
        $aZipped = ( Get-ChildItem -LiteralPath $ZipLocation.FullName )
        
        #$aZipped | Write-Verbose

        $nZipped = $aZipped.Count
    }
    Else {
        ( "{0} ZIP LOCATION: {1} DOES NOT EXIST." -f $sRepo,$ZipLocation ) | Write-Warning
        $nZipped = 0
    }

    #Write-Verbose ( "ZIP: {0}" -f $ZipLocation )
    
    If ( -Not $Batch ) {
        Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status "Counting bags in cloud storage" -PercentComplete 75
    }
    $bucket = ( $ZipLocation | Get-CloudStorageBucket )

    #Write-Verbose ( "BUCKET: {0}" -f $bucket )

    $nInCloud = 0
    If ( $bucket ) {
        If ( -Not $Batch ) {
            Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status ("Counting bags in cloud storage [{0}]" -f $bucket) -PercentComplete 80
        }
        $aInCloud = ( $ZipLocation | Get-CloudStorageListing )
        $nInCloud = $aInCloud.Count
    }

    If ( -Not $Batch ) {
        Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status "Counting bags" -PercentComplete 60
    }

    $Location = ( Get-Item -Force -LiteralPath ( Get-ColdStorageLocation -Repository $_ ) )

    $aBagged = ( Get-BaggedChildItem -LiteralPath $Location.FullName )

    #$aBagged | Write-Verbose

    $nBagged = $aBagged.Count

    If ( -Not $Batch ) {
        Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status "Writing object" -PercentComplete 100
   }

    @{} | Select-Object @{n='Location';e={ $sRepo }}, @{n='Bagged';e={ $nBagged }}, @{n='Zipped';e={ $nZipped }}, @{n='Cloud';e={ $nInCloud }}

    If ( -Not $Batch ) {
        Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status "Writing object" -PercentComplete 100 -Completed
    }
}

End { }
}

Export-ModuleMember -Function Get-RepositoryStats

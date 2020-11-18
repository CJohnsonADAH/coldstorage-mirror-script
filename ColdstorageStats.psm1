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
Param ( [Parameter(ValueFromPipeline=$true)] $Repository )

Begin { }

Process {
    Write-Progress -Id 101 -Activity "Scanning ${sRepo}"
    $sRepo = $_

    Write-Progress -Id 101 -Activity "Scanning ${sRepo}" -Status "Getting locations" -PercentComplete 0

    Write-Progress -Id 101 -Activity "Scanning ${sRepo}" -Status "Counting zipped bags" -PercentComplete 50

    $ZipLocation = ( Get-ColdStorageZipLocation -Repository $_ )
    If ( $ZipLocation ) {
        $nZipped = ( Get-ChildItem -LiteralPath $ZipLocation.FullName ).Count
    }
    Else {
        $nZipped = 0
    }

    Write-Progress -Id 101 -Activity "Scanning ${sRepo}" -Status "Counting bags" -PercentComplete 75
    
    $Location = ( Get-Item -Force -LiteralPath ( Get-ColdStorageLocation -Repository $_ ) )

    $nBagged = ( Get-BaggedChildItem -LiteralPath $Location.FullName ).Count

    Write-Progress -Id 101 -Activity "Scanning ${sRepo}" -Status "Writing object" -PercentComplete 100
   
    @{} | Select-Object @{n='Location';e={ $sRepo }}, @{n='Bagged';e={ $nBagged }}, @{n='Zipped';e={ $nZipped }}

    Write-Progress -Id 101 -Activity "Scanning ${sRepo}" -Status "Writing object" -PercentComplete 100 -Completed
}

End { }
}

Export-ModuleMember -Function Get-RepositoryStats

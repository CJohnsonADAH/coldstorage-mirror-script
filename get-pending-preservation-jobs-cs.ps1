Param(
    $Days=7,
    [switch] $Full=$false,
    $Locations=@( "*" )
)

Function Get-CSPendingPreservationJobs {
Param( [Parameter(ValueFromPipeline=$true)] $Container, $Days )

    Begin { }

    Process {
        Push-Location $Container.FullName
        Get-ChildItem -Directory $Container.FullName |? {
            $BagItTxt = ( Join-Path $_.FullName -ChildPath "bagit.txt" )
            ( Test-Path -LiteralPath $BagItTxt -PathType Leaf )
        } |? {
            $_ | & test-pending-preservation-job-cs.ps1 -Days:$Days -Full:$Full
        }
        Pop-Location
    }

    End { }
}

$AvailableLocations = @{
    "Q-Master"="H:\Digitization\Masters\Q_numbers\Master";
    "Q-Altered"="H:\Digitization\Masters\Q_numbers\Altered";
    "SC"="H:\Digitization\Masters\Supreme_Court";
    "ER-Unprocessed"="H:\ElectronicRecords\Unprocessed"
}

$ActiveLocations = @( )
$AvailableLocations.Keys |% { 
    $Key = $_ ; $Value = $AvailableLocations[ $Key ]

    $AnyMatch = $false
    $Locations |% {
        $AnyMatch = ( $AnyMatch -or ( $Key -like $_ ) )
        $AnyMatch = ( $AnyMatch -or ( $Value -like $_ ) )
    }
    If ( $AnyMatch ) {
        $ActiveLocations += @( $Value )
    }
}
$ActiveLocations |% {
    ( Get-Item -LiteralPath $_ -Force ) | Get-CSPendingPreservationJobs -Days:$Days
}

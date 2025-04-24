Param(
    $Days=7,
    [switch] $Full=$false
)

Function Get-CSDeferredValidationJobs {
Param( [Parameter(ValueFromPipeline=$true)] $Container, $Days )

    Begin { }

    Process {
        Push-Location $Container.FullName
        Get-ChildItem -Directory $Container.FullName |? {
            $BagItTxt = ( Join-Path $_.FullName -ChildPath "bagit.txt" )
            ( Test-Path -LiteralPath $BagItTxt -PathType Leaf )
        } |? {
            $_ | & test-deferred-validation-job-cs.ps1 -Days:$Days -Full:$Full
        }
        Pop-Location
    }

    End { }
}

"H:\Digitization\Masters\Q_numbers\Master",
"H:\Digitization\Masters\Q_numbers\Altered",
"H:\Digitization\Masters\Supreme_Court",
"H:\ElectronicRecords\Unprocessed" |% {
    ( Get-Item -LiteralPath $_ -Force ) | Get-CSDeferredValidationJobs -Days:$Days
}

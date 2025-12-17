Param(
    $Log=$null
)

If ( $Log -eq $null ) {
    $Here = ( Get-Item -LiteralPath . -Force )
    $LogName = ( "validation-{0}-{1}.csv" -f $Here.Name, ( Get-Date -Format "yyyyMMdd-HHmmss" ) )
    $Log = ( Join-Path $Here.FullName -ChildPath $LogName )
}

If ( Test-Path -LiteralPath $Log ) {
    "{0} already exists!!" -f $Log | Write-Error
    Exit 1
}

$dirs = ( Get-ChildItem -Directory )
$N = ( $dirs | Measure-Object ).Count ; $I = 0
$dirs |% {
    $Pct = ( 100.0*$I / $N ) ; $I++
    
    Push-Location $_.FullName

    $Thumbs = ( Get-ChildItem -File -Force -Recurse |? { $_.Name -eq 'Thumbs.db' } )

    Write-Progress -ID 001 -Activity ( "Validating {0}" -f $_.Parent.FullName ) -Status $_.Name -PercentComplete:$Pct
    $out = ( & bagit.ps1 --validate --dangerously . -Progress -Stdout ) ; $bex = $LASTEXITCODE

    Pop-Location

    [PSCustomObject] @{ 
        "NAME"=$_.Name ;
        "EXIT"=$bex ;
        "THUMBS"=( $Thumbs | Measure-Object ).Count ;
        "RESULT"=( $out | Select-Object -Last:1 )
    }
} | ConvertTo-Csv -NoTypeInformation | Out-File -Encoding utf8 $Log

Write-Progress -Id 001 -Activity "Validating" -Completed
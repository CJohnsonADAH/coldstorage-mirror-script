Param(
    $N=1,
    [switch] $Fast=$false
)

$Cmd = $MyInvocation.MyCommand.Name

$DeferredFile = ( & get-deferred-preservation-jobs-cs.ps1 -JobType:REPORT | Select-Object -First 1 )

$jobs = ( & get-deferred-validation-jobs-cs.ps1 -Full:( -Not $Fast ) )
If ( $jobs.Count -gt 0 ) {
    $jobs | Sort-Object { Get-Random } | Select-Object -First:$N |% {
        Write-Progress -Activity "Considering for Validation" -Status $_.FullName
        
        Push-Location $_.FullName
        $_.FullName | Write-Host -ForegroundColor Yellow
        Get-Item . | & coldstorage validate -Items -Fast:$Fast ; $ValidateExit = $LASTEXITCODE
        If ( $ValidateExit -gt 0 ) {
            $ReportMessage = ( "[{0}] ({1}) {2} failed {3} validation!" -f $Cmd,( Get-Date ),$_.FullName,$( If ( $Fast ) { "Oxum" } Else { "checksum" } ) )
            $ReportMessage | Write-Warning
            ( "'{0}' | Write-Warning" -f $ReportMessage ) >> $DeferredFile
            ( "{0} | & coldstorage consider repair -Items" -f ( "Get-Item -LiteralPath '{0}'" -f $_.FullName ) ) >> $DeferredFile

        }
        Pop-Location
    }
}


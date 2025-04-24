Param(
    $N=1,
    [switch] $Fast=$false,
    $Locations=@( "*" )
)

$Cmd = $MyInvocation.MyCommand.Name

$DeferredFile = ( & get-deferred-preservation-jobs-cs.ps1 -JobType:REPORT | Select-Object -First 1 )

$jobs = ( & get-pending-preservation-jobs-cs.ps1 -Full:( -Not $Fast ) -Locations:$Locations )
If ( $jobs.Count -gt 0 ) {
    $jobs | Sort-Object { Get-Random } | Select-Object -First:$N |% {
        Write-Progress -Activity "Considering for Preservation" -Status $_.FullName
        
        Push-Location $_.FullName
        "PRESERVE: {0}" -f $_.FullName | Write-Host -ForegroundColor White -BackgroundColor Black
        Get-Item . | & coldstorage packages get -Items -Mirrored -Zipped -InCloud |% {
            $_ | & write-packages-report-cs.ps1
            $_ | & coldstorage validate -Items -Fast ; $ValidateExit = $LASTEXITCODE
            If ( $ValidateExit -eq 0 ) {
                $_ | & sync-cs-packagetopreservation.ps1
                #If ( Test-Path -LiteralPath $PreservationLogFile ) {
                #    Get-Content $PreservationLogFile |% {
                #        ( "'{0}' | Write-Host -ForegroundColor DarkGreen -BackgroundColor Black" -f ( "$_" -replace "'","''" ) ) >> $DeferredFile
                #    }
                #    Remove-Item $PreservationLogFile
                #}

            }
        }
        
        If ( $ValidateExit -gt 0 ) {
            $ReportMessage = ( "[{0}] ({1}) {2} failed {3} validation!" -f $Cmd,( Get-Date ),$_.FullName,$( If ( $Fast ) { "Oxum" } Else { "checksum" } ) )
            $ReportMessage | Write-Warning
            ( "'{0}' | Write-Warning" -f $ReportMessage ) >> $DeferredFile
            ( "{0} | & coldstorage consider repair -Items" -f ( "Get-Item -LiteralPath '{0}'" -f $_.FullName ) ) >> $DeferredFile

        }
        Pop-Location
    }
}


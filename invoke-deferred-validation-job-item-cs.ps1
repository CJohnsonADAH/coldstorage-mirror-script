Param(
    [switch] $Fast=$false,
    $Cmd,
    $DeferredFile,
    $PretestExitCode=$null,
    [Parameter(ValueFromPipeline=$true)] $Item
)

Begin {
    $ExitCode = 0
}

Process {
    Push-Location $Item.FullName
    
    If ( $PretestExitCode -eq $null ) {
        $Item.FullName | Write-Host -ForegroundColor Yellow
        Get-Item . | & coldstorage validate -Items -Fast:$Fast ; $ValidateExit = $LASTEXITCODE
    }
    Else {
        $ValidateExit = $PretestExitCode
    }

    If ( $ValidateExit -gt 0 ) {
        $ExitCode = $ValidateExit

        $ReportMessage = ( "{0} failed {1} validation!" -f $Item.FullName,$( If ( $Fast ) { "Oxum" } Else { "checksum" } ) )
        $ReportTest = $( If ( $Fast ) { "Oxum" } Else { "checksum" } )
        $ReportSource = $Cmd
        $ReportTimestamp = ( Get-Date )
        "[{0}] ({1}) {2}" -f $ReportSource, $ReportTimestamp, $ReportMessage | Write-Warning
        $exprGetItem = ( "Get-Item -LiteralPath '{0}'" -f ( $_.FullName -replace "'","''" ) )
        $exprReportMessageObject = ( '( [PSCustomObject] @{{ "Consider"=$true; "Message"="{0}"; "MessageTest"="{1}"; "MessageSource"="{2}"; "MessageTimestamp"=( [DateTime]::Parse( "{3}" ) ) }} )' -f ( $ReportMessage -replace '"','""' ), ( $ReportTest ), ( $ReportSource ), ( $ReportTimestamp ) )
        ( '{0} | Add-Member -MemberType NoteProperty -Name CSPackageConsider -Value:{1} -PassThru | & coldstorage consider repair -Items' -f $exprGetItem, $exprReportMessageObject ) >> $DeferredFile
    }

    Pop-Location
}

End {
    Exit $ExitCode
}


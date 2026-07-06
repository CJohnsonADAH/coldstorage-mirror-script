Param(
    $N=1,
    $Progress=002
)
$Location = ( Get-Location )

$I = 0 ; $J = 0
get-321preservationreport.ps1 -Attn -Output:"object" |% {
    $I = $I + 1

    If ( $Progress -gt 0 ) {
        Write-Progress -Activity:( "Reviewing ATTN items for {0}" -f $Location.Path ) -Status:( "{0:N0}. {1}" -f $I, $_ ) -Id:$Progress
    }

    If ( $J -lt $N ) {
        $p = ( $_ | get-file-cs.ps1 -Object -Localize | get-itempackage-cs.ps1 -Check321 )
        If ( $p | test-cs-package-is.ps1 -NotInCloud ) {
            $p | Write-Output
            $J = $J + 1
        }
    }
}

Set-Location -LiteralPath:( $Location.Path )
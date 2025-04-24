Param(
    [switch] $Wildcard=$false,
    [switch] $Items=$false,
    [switch] $Directory=$false,
    [switch] $Mkdir=$false,
    $JobType="",
    $Extension="log.txt"
)

$deferredDirs = @(
    ( Join-Path $env:USERPROFILE -ChildPath "CS-DEFERRED" ),
    $env:USERPROFILE
)

If ( $Wildcard -or $Items ) {
    $Suffix = '*'
}
Else {
    $Suffix = ( Get-Date -Format "yyyyMMdd" )
}
If ( $JobType.Length -gt 0 ) {
    $Suffix = ( "{0}-{1}" -f $JobType, $Suffix )
}

$deferredDirs |% {
    If ( -Not ( Test-Path $_ ) ) {
        If ( $Mkdir ) {
            $Container = ( New-Item -ItemType Directory $_ -Force )
        }
    }

    If ( Test-Path $_ -PathType Container ) {
        If ( $Directory ) {
            If ( $Items ) {
                Get-Item -LiteralPath $_ -Force
            }
            Else {
                $_
            }
        }
        Else {
            $FilePath = ( $_ | Join-Path -ChildPath ( "coldstorage-mirror-checkup-DEFERRED-{0}.{1}" -f $Suffix,$Extension ) )
            If ( $Items ) {
                Get-Item -Path $FilePath -Force
            }
            Else {
                $FilePath
            }
        }
    }
}


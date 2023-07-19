Param(
    [switch] $Stdout=$false,
    [switch] $Progress=$false,
    [switch] $DisplayResult=$false
)

$cmd = ( $MyInvocation.MyCommand )
$cmdName = ( $cmd.Name )
$cmdDir = ( Split-Path -LiteralPath $cmd.Source )

# Internal Dependencies - Modules
$bVerboseModules = ( $Debug -eq $true )
$bForceModules = ( ( $Debug -eq $true ) -or ( $psISE ) )

Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Join-Path -Path $cmdDir -ChildPath "ColdStorageSettings.psm1" )

Function Get-BagitPyFilePath {
Param ( $Path )

    Join-Path -Path $Path -ChildPath "bagit.py"

}

Function Get-BagitPyPath {

    $BagIt = Get-PathToBagIt
    If ( $BagIt ) {
        Get-Item -Force -LiteralPath ( $BagIt | Join-Path -ChildPath "bagit.py" )
    }
    Else {
        ( $env:PATH -split ';' ) |? { $_.Length -gt 0 } |? { Test-Path -PathType Leaf ( Get-BagitPyFilePath -Path $_ ) } |% { Get-Item -Force -LiteralPath ( Get-BagitPyFilePath -Path $_ ) }
    }

}

$PExit = 254

$pythonExe = Get-ExeForPython
$bagitPy = Get-BagItPyPath

If ( $bagitPy ) {
    $bagitPyPath = $bagitPy.FullName
    If ( $Stdout -or $Progress ) {
        $sActivity = "bagit.py {0}" -f ( $args -join " " )
        & python.exe "${bagitPyPath}" $args 2>&1 |% {
            If ( $Progress ) {
                If ( ( $_ -ne $null ) -and ( $_.Length -gt 0 ) ) {
                    Write-Progress -Activity:( $sActivity ) -Status "$_"
                }
                If ( $DisplayResult -or ( -Not $Stdout ) ) {
                    If ( $_ -match "^(([0-9\-\:\,]|\s)+)\s*-\s*([A-Z]+)\s-(.*)is\s+(in)?valid([:]|$)" ) {
                        If ( $Matches[3] -eq "ERROR" ) {
                            $FG = "Red"
                        }
                        ElseIf ( $Matches[3] -eq "INFO" ) {
                            $FG = "Green"
                        }
                        Else {
                            $FG = "Yellow"
                        }
                        Write-Host "$_" -ForegroundColor $FG
                    }
                }
            }
            If ( $Stdout ) { "$_" }
        }
        $PExit = $LASTEXITCODE

        If ( $Progress ) {
            Write-Progress -Activity $sActivity -Status "DONE" -Completed
        }
    }
    Else {
        & python.exe "${bagitPyPath}" $args
        $PExit = $LASTEXITCODE
    }
} Else {
    ( '[{0}] Could not locate bagit.py script; check your $env:PATH variable.' -f $cmdName ) | Write-Error
}

Exit $PExit

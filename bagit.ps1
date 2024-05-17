Param(
    [switch] $Stdout=$false,
    [switch] $Progress=$false,
    [switch] $DisplayResult=$false,
    [switch] $PassThru=$false
)

Function Get-BagitPyFilePath {
Param ( $Path )

    Join-Path -Path $Path -ChildPath "bagit.py"

}

Function Get-BagitPyPath {

    ( $env:PATH -split ';' ) |? { $_.Length -gt 0 } |? { Test-Path -PathType Leaf ( Get-BagitPyFilePath -Path $_ ) } |% { Get-Item -Force -LiteralPath ( Get-BagitPyFilePath -Path $_ ) }

}

Function Write-BagItOutput {
Param( [Parameter(ValueFromPipeline=$true)] $Line, $args, [switch] $Progress=$false, [switch] $Stdout=$false, [switch] $DisplayResult=$false )
    Begin {
				 
									
								  
        $sActivity = "bagit.py {0}" -f ( $args -join " " )
        $AfterErrorMessage = $false
    }

    Process {
        
        If ( $Progress ) {
            If ( ( $Line -ne $null ) -and ( $Line.Length -gt 0 ) ) {
                Write-Progress -Activity:( $sActivity ) -Status "${Line}"
            }
            If ( $DisplayResult -Or ( -Not $Stdout ) ) {
                If ( $Line -match "^(([0-9\-\:\,]|\s)+)\s*-\s*([A-Z]+)\s-(.*)is\s+(in)?valid([:]|$)" ) {
                    If ( $Matches[3] -eq "ERROR" ) {
                        $FG = "Red"
						 
														   
										 
						 
							  
										  
						 
															
                    }
                    ElseIf ( $Matches[3] -eq "INFO" ) {
                        $FG = "Green"
                    }
                    Else {
                        $FG = "Yellow"
                    }
                    Write-Host "${Line}" -ForegroundColor $FG
                }
                ElseIf ( $AfterErrorMessage -or ( $Line -match "^(([0-9\-\:\,]|\s)+)\s*-\s*(ERROR)\s-(.*)$" ) ) {
                    $FG = "Red"
                    Write-Host "${Line}" -ForegroundColor $FG
                    $AfterErrorMessage = $true
                }
                # 2023-12-11 12:15:44,140 - ERROR
            }
								   
        }
        If ( $Stdout ) {
            "${Line}"
        }

    }

    End {
        If ( $Progress ) {
            Write-Progress -Activity $sActivity -Status "DONE" -Completed
        }
    }

}

$PExit = 254

$bagitPy = $null
$bagitArgs = $args
Get-BagItPyPath |% {
    $bagitPy = $_
    $bagitPyPath = $bagitPy.FullName
    If ( $Stdout -or $Progress ) {
        
        & python.exe "${bagitPyPath}" $bagitArgs 2>&1 | Write-BagItOutput -args:$bagitArgs -Progress:$Progress -Stdout:$Stdout -DisplayResult:$DisplayResult
        $PExit = $LASTEXITCODE

    }
    Else {

        & python.exe "${bagitPyPath}" $bagitArgs
        $PExit = $LASTEXITCODE

    }

    If ( $PassThru ) {
        If ( $PExit -eq 0 ) {
            $Item = $null
            $bagitArgs |? { -not ( "$_" -match '^--' ) } |% {
                If ( Test-Path -LiteralPath "$_" ) {
                    $Item = ( Get-Item -LiteralPath "$_" -Force )
                    $Item
                }
            }
            If ( $Item -eq $null ) {
                '[bagit.ps1] Could not determine directory for PassThru' | Write-Error
            }
        }
    }

}

If ( -Not $bagitPy ) {
    '[bagit.ps1] Could not locate bagit.py script; check your $env:PATH variable.' | Write-Error
}

Exit $PExit

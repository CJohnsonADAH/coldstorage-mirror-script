Param(
    $Repositories=@( 'Access', 'Masters' ),
    $Window=60,
    $IPG=75,
    $Schedule='6:00 PM'
)

Function Write-RoboCopyOutput {
Param (
    [Parameter(ValueFromPipeline=$true)] $Line,
    [switch] $Prolog=$false,
    [switch] $Epilog=$false,
    [switch] $Echo=$false,
    [switch] $Directories=$false,
    [switch] $ChangeLog=$false
)

    Begin { $Status = $null; $pct = 0.0; $Sect = 0; $CurDir = $null ; $DisplayedDir = $null ; $roboCopyParams = @{ } }

    Process {
        If ( "${Line}" ) {
            If ( "${Line}" -match "^\s*([0-9.]+)%\s*$" ) {
                $pct = [Decimal] $Matches[1]
            }
            Else {
                $pct = 0.0
                $Status = ( "${Line}" -replace "\t","    " )
                $Status = ( "${Status}" -replace "\s"," " )
                $Status = ( "({0}) {1}" -f ( Get-Date ), $Status )
            }
            
            $Source = $roboCopyParams[ "Source" ]
            $Destination = $roboCopyParams[ "Destination" ]
            $Options = $roboCopyParams[ "Options" ]
            Write-Progress -Activity ( "Robocopy.exe {0} {1} {2}" -f "${Options}","${Source}","${Destination}" ) -Status "${Status}" -PercentComplete $pct
            
            If ( "${Line}" -match "\s([0-9]+)\s+(\S.*[\\])\s*$" ) {
                $CurDir = $Line ; $DisplayedDir = $null
                If ( $Directories ) {
                    $Line | Write-Host -ForegroundColor Yellow -BackgroundColor Black
                }
            }

        }

        If ( "${Line}" -match "^\s*-+\s*$" ) {
            $Sect = $Sect + 1
        }

        If ( $Echo ) {
            "${Line}"
        }
        ElseIf ( $ChangeLog ) {
            $LogLine = $null
            If ( $pct -eq 100 ) {
                $LogLine = $Status
                $LogFG = 'Green'
            }
            ElseIf ( "${Line}" -match '^(\s*)([*]EXTRA File)(\s+)([0-9]+)(\s+)(\S.*)$' ) {
                $LogLine = $Line
                $LogFG = 'Yellow'
            }

            If ( $LogLine -ne $null ) {
                If ( ( $DisplayedDir -eq $null ) -or ( $CurDir -ne $DisplayedDir ) ) {
                    $DisplayedDir = $CurDir
                    $DisplayedDir | Write-Host -ForegroundColor Cyan -BackgroundColor Black
                }
                $LogLine | Write-Host -ForegroundColor:$LogFG -BackgroundColor:Black
            }

        }
               

        If ( $Prolog -Or $Epilog ) {
            If ( $Prolog -and ( $Sect -le 2 ) ) {
                "${Line}" | Write-Host
                If ( "${Line}" -match "^\s*([^:]+)\s*[:]\s*(\S(.*\S)?)\s*$" ) {
                    $Key = $Matches[1].Trim()
                    $Value = $Matches[2]
                    $roboCopyParams[ $Key ] = $Value
                }

            }
            ElseIf ( "${Line}" -match "^[0-9/]+\s+[0-9:]+\s+(ERROR|WARNING)\s" ) {
                "${Line}" | Write-Host -ForegroundColor Red
            }
            ElseIf ( $Epilog -and ( $sect -gt 3 ) ) {
                "${Line}" | Write-Host
            }
             
        }
        ElseIf ( -Not $Echo ) {
            If ( "${Line}" -match "^[0-9/]+\s+[0-9:]+\s+(ERROR|WARNING)\s" ) {
                "${Line}" | Write-Host -ForegroundColor Red
            }
        }

    }

    End { }
}

If ( $Schedule -ne $null ) {
    $Timeout = ( [DateTime]::Parse( $Schedule ) - ( Get-Date ) ).TotalSeconds
    $sSchedule = ( " (schedule: {0})" -f $Schedule )
}
Else {
    $Timeout = $null
    $sSchedule = ""
}

If ( & read-yesfromhost-cs.ps1 -Prompt:( "Initiate mirror{0}:" -f $sSchedule ) -Timeout:$Timeout -DefaultInput:"Y" ) {

    $Repositories |% {
        $repo = ( & coldstorage repository $_ -Location:Original )

        If ( Test-Path -LiteralPath $repo.File -PathType Container ) {
            $Local = ( $repo.File | & get-mirrormatcheditem-cs.ps1 -Original | Convert-Path )
            $o = ( Get-Item -LiteralPath $Local -Force )

            Push-Location -LiteralPath $o.FullName

            $t0 = ( Get-Date )
            $sActivityLabel = ( "Daily Repository Data Transfer ({0} / time window: {1:N0})" -f $t0, $Window )
            $TopDirectories = ( Get-ChildItem -Directory |? { $_.Name -notlike '.*' } |? { $_.Name -notin @( 'ZIP' ) } )
            $I = 0 ; $N = ( $TopDirectories | Measure-Object ).Count
            $TopDirectories |% {
                $Pct = ( 100.0 * $I / $N ) ; $I++ ; $tN = ( Get-Date )

                Push-Location -LiteralPath $_.FullName
                Write-Progress -Id 002 -Activity:$sActivityLabel -Status:( "({0} / {1}) {2}" -f $tN,( $tN - $t0 ),( $_.FullName ) ) -PercentComplete:$Pct

                $mirror = ( Get-Item . | get-mirrormatcheditem-cs.ps1 -ColdStorage )
                If ( Test-Path $mirror ) {
                    $mirror = ( $mirror | Convert-Path )
                }
                Else {
                    $oMirror = ( New-Item -ItemType Directory $mirror )
                    $mirror = ( $oMirror.FullName | Convert-Path )
                }

                If ( $mirror ) {
                    & Robocopy.exe /copy:DAT /dcopy:DAT /maxage:${Window} /ipg:${IPG} /z /r:1 /w:1 /e $_.FullName $mirror /XD .coldstorage ZIP | Write-RoboCopyOutput -Prolog -Epilog -ChangeLog
                }

                Pop-Location

            }
            Write-Progress -Id 002 -Activity:$sActivityLabel -Status:( "Completed" ) -Completed

            Pop-Location
        }
        Else {
            "COULD NOT CHANGE LOCATION TO {0}" -f $_ | Write-Error
        }
    }
}

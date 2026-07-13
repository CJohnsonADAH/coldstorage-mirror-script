Param(
    $Repositories=@( 'Access', 'Processed', 'Unprocessed' ),
    $Directories='*',
    $Window=60,
    $IPG=50,
    $Schedule='6:00 PM',
    [switch] $Randomize,
    [switch] $Forward=$false
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

    Begin {
        $Status = $null
        $pct = 0.0
        $Sect = 0
        $CurDir = $null
        $DisplayedDir = $null
        $roboCopyParams = @{ }

        $ChangeLogText = @{ "PRE"=@( ) ; "POST"=@( ) }

    }

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

                If ( ( $ChangeLogText[ 'PRE' ] | Measure-Object ).Count -gt 0 ) {
                    $ChangeLogText[ 'PRE' ] | Write-Host -ForegroundColor Gray -BackgroundColor Black
                    $ChangeLogText[ 'PRE' ] = @( )
                }

                If ( ( $DisplayedDir -eq $null ) -or ( $CurDir -ne $DisplayedDir ) ) {
                    $DisplayedDir = $CurDir
                    $DisplayedDir | Write-Host -ForegroundColor Cyan -BackgroundColor Black
                }
                $LogLine | Write-Host -ForegroundColor:$LogFG -BackgroundColor:Black
            }

        }
               

        If ( $Prolog -Or $Epilog ) {
            If ( $Prolog -and ( $Sect -le 2 ) ) {
                
                If ( -Not $ChangeLog ) {
                    "${Line}" | Write-Host
                }
                Else {
                    $ChangeLogText[ "PRE" ] = @( $ChangeLogText[ "PRE" ] ) + @( "${Line}" )
                }

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
                If ( -Not $ChangeLog ) {
                    "${Line}" | Write-Host
                }
                Else {
                    $ChangeLogText[ "POST" ] = @( $ChangeLogText[ "POST" ] ) + @( "${Line}" )
                }
            }
             
        }
        ElseIf ( -Not $Echo ) {
            If ( "${Line}" -match "^[0-9/]+\s+[0-9:]+\s+(ERROR|WARNING)\s" ) {
                "${Line}" | Write-Host -ForegroundColor Red
            }
        }

    }

    End {
    
        If ( ( $ChangeLogText[ 'POST' ] | Measure-Object ).Count -gt 0 ) {
        
            If ( ( $ChangeLogText[ 'PRE' ] | Measure-Object ).Count -eq 0 ) {

                    $ChangeLogText[ 'POST' ] | Write-Host -ForegroundColor Gray -BackgroundColor Black
                    $ChangeLogText[ 'POST' ] = @( )
                
            }

        }

    }

}

Function Format-TextHeaderBlock {
Param( [Parameter(ValueFromPipeline=$true)] $Line, $Width=100, $BoxCharacter="=", $PadCharacter=" " )

    Begin {
        ( $BoxCharacter * ( $Width / $BoxCharacter.Length ) ) | Write-Output
    }

    Process {
        $PaddedLine = ( "{0} {1}" -f ( $BoxCharacter * 2), $Line )
        $Remaining = ( $Width - $PaddedLine.Length - ( $BoxCharacter.Length * 2 ) ) / $PadCharacter.Length
        $PaddedLine = ( "{0}{1}{2}" -f $PaddedLine, ( $PadCharacter * $Remaining ), ( $BoxCharacter * 2 ) )

        $PaddedLine | Write-Output
    }

    End {
        ( $BoxCharacter * ( $Width / $BoxCharacter.Length ) ) | Write-Output
    }
}

If ( $Schedule -ne $null ) {
    $Timeout = ( [DateTime]::Parse( $Schedule ) - ( Get-Date ) ).TotalSeconds
    $sSchedule = ( " (schedule: {0})" -f $Schedule )
}
Else {
    $Timeout = $null
    $sSchedule = ""
}

$aRepositories = ( $Repositories )
If ( $Randomize ) {
    $aRepositories = ( $aRepositories | Sort-Object { Get-Random } )
}

$OKtoStart = $true
If ( $Schedule -ne $null ) {
    $OKtoStart = ( & read-yesfromhost-cs.ps1 -Prompt:( "Initiate mirror [{0}]{1}:" -f ( $aRepositories -join ", " ), $sSchedule ) -Timeout:$Timeout -DefaultInput:"Y" )
}
Else {
    ( "INITIATING MIRROR DATA TRANSFERS [{0}]" -f ( $aRepositories -join ", " ) ) | Format-TextHeaderBlock | Write-Host -ForegroundColor:Cyan
}


If ( $OKtoStart ) {

    $aRepositories |% {
        $sRepository = $_
        
        $sRepositoryCode = $sRepository
        $nWindow = $Window
        $bForwardFlag = ( [bool] $Forward )
        $sDirectories = $Directories

        If ( $sRepository -match '^([^#@/]*)([#]([^@/]*))?([@]([^/]*))?([/](.*))?$') {
            
            $sRepositoryCode = $Matches[1]
            $vRepositoryFlag = $Matches[3]
            $vRepositoryWindow = $Matches[5]
            $vDirectories = $Matches[7]

            $vWindow = $null
            If ( ( $vRepositoryWindow -ne $null ) -and ( [int]::TryParse( $vRepositoryWindow, [ref] $vWindow ) ) ) {
                $nWindow = $vWindow
            }

            If ( ( $vRepositoryFlag -ne $null ) -and ( $vRepositoryFlag -imatch '^(Forward|Fwd)$' ) ) {
                $bForwardFlag = $true
            }

            If ( ( $vDirectories -ne $null ) -and ( $vDirectories.Length -gt 0 ) ) {
                $sDirectories = $vDirectories
            }
            
        }
        
        $repo = ( & coldstorage repository $sRepositoryCode -Location:Original )
        If ( $repo ) {
            $repoProps = ( $repo.File | & coldstorage repository properties ).Properties
        }
        Else {
            $repoProps = $null
        }

        $Lines = @( ( "DAILY MIRROR: {0} [{1}]" -f $sRepository, $repo.File ), ( "Date/Time: {0}" -f ( Get-Date ) ) )
        $FlexWidth = ( [Math]::Max( 80, ( $Lines | Sort-Object -Property:Length -Descending | Select-Object -First:1 ).Length + 6 ) )

        $Lines | Format-TextHeaderBlock -Width:$FlexWidth | Write-Host -ForegroundColor:Cyan


        If ( Test-Path -LiteralPath $repo.File -PathType Container ) {
            $Local = ( $repo.File | & get-mirrormatcheditem-cs.ps1 -Original | Convert-Path )
            $o = ( Get-Item -LiteralPath $Local -Force )

            Push-Location -LiteralPath $o.FullName

            $t0 = ( Get-Date )
            $sActivityLabel = ( "Daily Repository Data Transfer ({0} / time window: {1:N0})" -f $t0, $nWindow )
            $TopDirectories = ( Get-ChildItem -Directory |? { $_.Name -notlike '.*' } |? { $_.Name -notin @( 'ZIP' ) } )
            If ( $sDirectories -ne $null ) {
                $TopDirectories = ( $TopDirectories |? { $_.Name -like $sDirectories } )
            }

            $I = 0 ; $N = ( $TopDirectories | Measure-Object ).Count
            $TopDirectories |% {
                $Pct = ( 100.0 * $I / $N ) ; $I++ ; $tN = ( Get-Date )

                Push-Location -LiteralPath $_.FullName
                Write-Progress -Id 002 -Activity:$sActivityLabel -Status:( "({0} / {1}) {2}" -f $tN,( $tN - $t0 ),( $_.FullName ) ) -PercentComplete:$Pct

                If ( -Not $bForwardFlag ) {
                    $mirror = ( Get-Item . | get-mirrormatcheditem-cs.ps1 -ColdStorage )
                }
                Else {
                    $mirror = ( Get-Item . | get-mirrormatcheditem-cs.ps1 -Forward )
                }
                If ( Test-Path $mirror ) {
                    $mirror = ( $mirror | Convert-Path )
                }
                Else {
                    $oMirror = ( New-Item -ItemType Directory $mirror )
                    $mirror = ( $oMirror.FullName | Convert-Path )
                }

                If ( $mirror ) {
                    $roboCopyPre = @( "/copy:DAT", "/dcopy:DAT", "/maxage:${nWindow}", "/ipg:${IPG}", "/r:1", "/w:1", "/e" )
                    $roboCopyPost = @(  )
                    If ( $repoProps -ne $null ) {
                        If ( $repoProps | Get-Member -MemberType:NoteProperty -Name:Robocopy ) {
                            $robo = $repoProps.Robocopy
                            If ( $robo | Get-Member "pre" ) {
                                $roboCopyPre = @( $roboCopyPre ) + ( $robo.pre )
                                "[mirror] ADDING ROBOCOPY PRE PARAMETERS: {0}" -f ( $roboCopyPre -join ' ' ) | Write-Verbose
                            }
                            If ( $robo | Get-Member "post" ) {
                                $roboCopyPost = @( $roboCopyPost ) + ( $robo.post )
                                "[mirror] ADDING ROBOCOPY POST PARAMETERS: {0}" -f ( $roboCopyPost -join ' ' ) | Write-Verbose
                            }
                        }
                    }
                    
                    & Robocopy.exe @roboCopyPre $_.FullName $mirror @roboCopyPost /XD .coldstorage ZIP /XF Thumbs.db | Write-RoboCopyOutput -Prolog -Epilog -ChangeLog
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

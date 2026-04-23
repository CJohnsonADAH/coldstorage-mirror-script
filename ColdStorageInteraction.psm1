#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################

$global:gColdStorageInteractionModuleCmd = $MyInvocation.MyCommand
    
    $modSource = ( $global:gColdStorageInteractionModuleCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

#Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )
#Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageZipArchives.psm1" )

Function Get-ScriptPath {
Param ( $Command, $File=$null )

    $Source = ( $Command.Source | Get-Item -Force )
    $Path = ( $Source.Directory | Get-Item -Force )

    If ( $File -ne $null ) {
        $Path = ($Path.FullName | Join-Path -ChildPath $File)
    }

    $Path
}

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Write-BleepBloop {
<#
.SYNOPSIS
Make a familiar sound through the workstation's bleep-bloop speaker.

.DESCRIPTION
Produces a notification sound through [Console]::beep
Bleep Bleep Bleep Bleep Bleep Bleep -- BLOOP!
Formerly known as: Do-Bleep-Bloop
#>

    [console]::beep(659,250) ##E
    [console]::beep(659,250) ##E
    [console]::beep(659,300) ##E
    [console]::beep(523,250) ##C
    [console]::beep(659,250) ##E
    [console]::beep(784,300) ##G
    [console]::beep(392,300) ##g
    [console]::beep(523,275) ## C
    [console]::beep(392,275) ##g
    [console]::beep(330,275) ##e
    [console]::beep(440,250) ##a
    [console]::beep(494,250) ##b
    [console]::beep(466,275) ##a#
    [console]::beep(440,275) ##a
}

Function Select-UserApproved {
Param ( [Parameter(ValueFromPipeline=$true)] $Candidate, [String] $Prompt, [String] $Default="N" )

Begin { }

Process {
    $FormattedPrompt = $Prompt
    If ( $Prompt -match "\{[0-9]\}" ) {
        $FormattedPrompt = ( $Prompt -f $Candidate )
    }

    $ShouldWeContinue = ( Read-Host $FormattedPrompt )
    If ( $ShouldWeContinue -match "^[YyNn].*" ) {
        $ShouldWeContinue = ( $ShouldWeContinue )[0]
    }
    Else {
        $ShouldWeContinue = $Default
    }

    If ( $ShouldWeContinue -eq "Y" ) {
        $Candidate
    }
}

End { }

}

Function Get-BaggedItemNoticeMessage {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $Prefix, $Zip=$false, $Suffix=$null )

    Begin { }

    Process {

    $oFile = ( Get-FileObject($File) | Add-ERInstanceData -PassThru )

    $LogMesg = ""
    If ( $Prefix ) {
        $LogMesg = ( "{0}: {1}" -f $Prefix, $LogMesg ) 
    }

    $ERCode = ( $oFile.CSPackageERMeta.ERCode )

    $FileNameSlug = ( $oFile.Name )
    If ( $ERCode -ne $null ) {
        $FileNameSlug = ( "{0}, {1}" -f $ERCode,$FileNameSlug )
    }
    $LogMesg = ( "{0}{1}" -f $LogMesg,$FileNameSlug )

    If ( $Zip ) {
        $sZip = $oZip.Name
        $LogMesg += " (ZIP=${sZip})"
    }

    If ( $Suffix -ne $null ) {
        If ( $Suffix -notmatch "^\s+" ) {
            $LogMesg += ", "
        }
        
        $LogMesg += $Suffix
    }

    $LogMesg

    }

    End { }

}

Function Write-BaggedItemNoticeMessage {
Param( $File, $Item=$null, $Status=$null, $Message=$null, [switch] $Zip=$false, [switch] $Quiet=$false, [switch] $Verbose=$false, [switch] $ReturnObject=$false, $Line=$null )

    $Prefix = "BAGGED"
    If ( $Status -ne $null ) {
        $Prefix = $Status
    }

    If ( $Zip ) {
        $oZip = ( Get-ZippedBagOfUnzippedBag -File $File )
    }

    If ( $Prefix -like "BAG*" ) {
        If ( $oZip ) {
            $Prefix = "BAG/ZIP"
        }
    }

    If ( ( $Debug ) -and ( $Line -ne $null ) ) {
        $Prefix = "${Prefix}:${Line}"
    }

    $LogMesg = ($File | Get-BaggedItemNoticeMessage -Prefix $Prefix -Zip $Zip -Suffix $Message)

    If ( $Zip -and ( $oZip -eq $null ) ) { # a ZIP package was expected, but was not found.
        Write-Warning $LogMesg
    }
    ElseIf ( $Verbose ) {
        Write-Verbose $LogMesg
    }

    If ( ( $ReturnObject ) -and ( $Status -ne "SKIPPED" ) ) {
        Write-Output $Item
    }
    ElseIf ( $Zip -and ( $oZip -ne $null ) ) {
        # NOOP
    }
    ElseIf ( $Verbose ) {
        # NOOP
    }
    ElseIf ( $Quiet -eq $false ) {
        Write-Output $LogMesg
    }

}

Function Write-UnbaggedItemNoticeMessage {
Param( $File, $Status=$null, $Message=$null, [switch] $Quiet=$false, [switch] $Verbose=$false, $Line=$null )

    $Prefix = "UNBAGGED"
    If ( $Status -ne $null ) {
        $Prefix = $Status
    }
    If ( $Line -ne $null ) {
        $Prefix = "${Prefix}:${Line}"
    }

    $LogMesg = ($File | Get-BaggedItemNoticeMessage -Prefix $Prefix -Suffix $Message)

    If ( $Verbose ) {
        Write-Verbose $LogMesg
    }
    Else {
        Write-Warning $LogMesg
    }

}

Function Test-IsYesNoString {
Param ( [Parameter(ValueFromPipeline=$true)] $In, [string[]] $OtherOptions=@( ), [switch] $AllowEmpty )

    Begin { }

    Process {
        $ok = ( $In -match '^\s*[YyNn].*$' )
        If ( ( $OtherOptions | Measure-Object ).Count -gt 0 ) {
            $FirstCharacters = ( $OtherOptions |% { $_.Substring( 0, 1 ).ToUpper(), $_.Substring( 0, 1 ).ToLower() } | Select-Object -Unique )
            $ok = ( $ok -or ( $In.Substring( 0, 1 ) -iin $FirstCharacters ) )
        }
        If ( $AllowEmpty ) {
            $ok = ( $ok -or ( $In -match '^\s*$' ) )
        }
        $ok
    }

    End { }
}

Function Get-YesNoOpposite {
Param ( [Parameter(ValueFromPipeline=$true)] $In )
    Begin { }

    Process {
        If ( $In -match '^\s*[Yy]' ) { "N" }
        If ( $In -match '^\s*[Nn]' ) { "Y" }
    }

    End { }
}

Function Read-YesFromHost {
Param (
    [string] $Prompt,
    $OtherOptions=@( ),
    $Timeout = -1.0,
    $DefaultInput="Y",
    $DefaultAction="",
    $DefaultTimeout = 5.0,
    $PromptColor="Yellow"
)

    If ( $global:psISE ) {
        If ( $Timeout -gt 0 ) {
            $wshellTimeout = $Timeout
        }
        Else {
            $wshellTimeout = 0
        }

        $wshell = ( New-Object -ComObject Wscript.Shell )
        $answer = $wshell.Popup( $Prompt, $wshellTimeout, "Question", 32+4 )
        
        $InKey = $DefaultInput
        If ( $answer -eq -1 ) {
            $InKey = $DefaultInput
        }
        ElseIf ( $answer -eq 6 ) {
            $InKey = 'Y'
        }
        ElseIf ( $answer -eq 7 ) {
            $InKey = 'N'
        }

        ( $InKey -match '^\s*[Yy].*$' )

    }
    Else {

        If ( $PromptColor -is [string] ) {
            $FGColor = $PromptColor
            $BGColor = $null
        }
        ElseIf ( $PromptColor -is [Hashtable] ) {
            $FGColor = $PromptColor[ 'Foreground' ]
            $BGColor = $PromptColor[ 'Background' ]
        }

        If ( $BGColor -ne $null ) {
            $Prompt | Write-Host -ForegroundColor:$FGColor -BackgroundColor:$BGColor
        }
        Else {
            $Prompt | Write-Host -ForegroundColor:$FGColor
        }

        $TextOptions = @( "[Y]es", "[N]o" )
        $OtherOptions |% { $Opt = ( '[{0}]{1}' -f $_.Substring(0, 1).ToUpper(), $_.Substring(1) ) ; $TextOptions = ( @( $TextOptions ) + @( $Opt ) ) }
        $YNPrompt = ( '{0} (default is "{1}")' -f ( $TextOptions -join " " ), $DefaultInput )
        Do {
            If ( $Timeout -lt 0.0 ) {
                $InKey = ( Read-Host -Prompt $YNPrompt )
            }
            Else {
                ( "{0}: " -f $YNPrompt ) | Write-Host -NoNewline

                $InKey = $null
                $T0 = ( Get-Date ) ; $TN = ( $Timeout + 0.25 )
                Do {
                    $TDiff = ( Get-Date ) - $T0
                    $tPct = ( @( 100.0, ( 100 * $TDiff.TotalSeconds / $TN ) ) | Measure-Object -Minimum ).Minimum
                    Write-Progress -Id 707 -Activity "Waiting to Trigger Default Action" -Status ( '{0} in {1:N0}' -f $DefaultAction, ( $TN - $TDiff.TotalSeconds ) ) -PercentComplete:$tPct
                    If ( [Console]::KeyAvailable ) { $InKey = ( Read-Host ) }
                } While ( ( $TDiff.TotalSeconds -lt $TN ) -and ( $InKey -eq $null ) )
                Write-Progress -Id 707 -Activity "Waiting to Trigger Default Action" -Status ( '{0} in {1:N0}' -f $DefaultAction, ( $TN - $TDiff.TotalSeconds ) ) -PercentComplete:100.0 -Completed

                If ( $InKey -eq $null ) {
                    $InKey = $DefaultInput
                    $InKey | Write-Host -ForegroundColor Yellow
                }

            }
        } While ( -Not ( Test-IsYesNoString -In:$InKey -OtherOptions:$OtherOptions -AllowEmpty ) )
        
        If ( $InKey -match '^\s*$' ) {
            $T0 = ( Get-Date ) ; $TN = ( $DefaultTimeout + 0.25 ) ; $keyinfo = $null

            If ( $TN -lt 0.0 ) {
                $CancelMessage = ""
            }
            Else {
                $CancelMessage = ( " ... ({0:N0} seconds to cancel)" -f $TN )
            }

            ( 'DEFAULT SELECTION - {0}{1} ' -f $DefaultAction,$CancelMessage ) | Write-Host -ForegroundColor Green -NoNewline
            Do {
                $TDiff = ( Get-Date ) - $T0
                $tPct = ( @( 100.0, ( 100 * $TDiff.TotalSeconds / $TN ) ) | Measure-Object -Minimum ).Minimum
                Write-Progress -Id 707 -Activity "Waiting to Trigger Default Action" -Status ( '{0} in {1:N0}' -f $DefaultAction, ( $TN - $TDiff.TotalSeconds ) ) -PercentComplete:$tPct
                If ( [Console]::KeyAvailable ) { $keyinfo = [Console]::ReadKey($true) }
            } While ( ( $TDiff.TotalSeconds -lt $TN ) -and ( $keyinfo -eq $null ) )
            Write-Progress -Id 707 -Activity "Waiting to Trigger Default Action" -Status ( '{0} in {1:N0}' -f $DefaultAction, ( $TN - $TDiff.TotalSeconds ) ) -PercentComplete:100.0 -Completed

            $DefaultOpposite = ( $DefaultInput | Get-YesNoOpposite )
            If ( ( $keyinfo -ne $null ) -and ( -Not ( $keyinfo.KeyChar -match "[YyNn`r`n]" ) ) ) {
                $InKey = $DefaultOpposite
            }
            ElseIf ( ( $keyinfo -ne $null ) -and ( $keyinfo.KeyChar -match "[YyNn]" ) ) {
                $InKey = $keyinfo.KeyChar
            }
            Else {
                $InKey = $DefaultInput
            }
            $InKey | Write-Host -ForegroundColor Yellow

        }

        $MatchesYes = ( $InKey -match '^\s*[Yy].*$' )
        $MatchesNo = ( $InKey -match '^\s*[Nn].*$' )
        
        $Result = $MatchesYes
        If ( ( $OtherOptions | Measure-Object ).Count -gt 0 ) {
            If ( ( -Not $MatchesYes ) -and ( -Not $MatchesNo ) ) {
                $Result = $InKey.Substring( 0, 1 ).ToUpper()
            }
        }

        $Result | Write-Output

    }
}

Function Get-ConditionalText {
Param( [Parameter(ValueFromPipeline=$true)] $Test, $WhenTrue, $WhenFalse=$null )

    Begin {
        $FormatWhenTrue = ( $WhenTrue -like "*{0}*" )
        $FormatWhenFalse = ( $WhenFalse -like "*{0}*" )
    }

    Process {

        If ( $Test -is [ScriptBlock] ) {
            $bResult = ( & $Test )
        }
        Else {
            $bResult = ( -Not ( -Not ( $Test ) ) )
        }

        If ( $FormatWhenTrue ) {
            $vWhenTrue = ( $WhenTrue -f $WhenFalse )
        }
        Else {
            $vWhenTrue = $WhenTrue
        }
        If ( $FormatWhenFalse ) {
            $vWhenFalse = ( $WhenFalse -f $WhenTrue )
        }
        Else {
            $vWhenFalse = $WhenFalse
        }

        If ( $bResult ) {

            If ( $vWhenTrue -ne $null ) {
                $vWhenTrue
            }
        }
        Else {

            If ( $vWhenFalse -ne $null ) {
                $vWhenFalse
            }
        }

    }

    End { }

}

Function Get-PluralizedText {
Param ( [Parameter(Position=0)] $N, [Parameter(ValueFromPipeline=$true)] $Singular, $Plural="{0}s" )

    Begin { }

    Process {
        $Pluralized = $( $Plural -f $Singular )
        If ( $N -eq 1 ) {
            $Singular
        }
        Else {
            $Pluralized
        }
    }

    End { }

}

Function Write-CSOutputWithLogMaybe {
Param ( [Parameter(ValueFromPipeline)] $Line, $Package, $Command=$null, $Log )

	Begin {
		If ( $Log -ne $null ) {
			If ( ( -Not ( Test-Path -LiteralPath $Log ) ) -or ( ( Get-Item -LiteralPath $Log -Force ).Length -eq 0 ) ) {
				$StartMessage = @{ "Location"=$Package.FullName; "User"=( $env:USERNAME ); "Time"=( Get-Date ).ToString() }
				( "! JSON[Start]: {0}" -f ( $StartMessage | ConvertTo-Json -Compress ) ) | Out-File -LiteralPath:$Log -Append
			}
		}
		If ( $Command -ne $null ) {
			If ( $Log -ne $null ) {
				$StartMessage = @{ "Command"=( $Command -f ( "Get-Item -LiteralPath '{0}' -Force" -f $Package.FullName ) ); "User"=( $env:USERNAME ); "Time"=( Get-Date ).ToString() }
				( "! JSON[Command]: {0}" -f ( $StartMessage | ConvertTo-Json -Compress ) ) | Out-File -LiteralPath:$Log -Append
			}
		}
	}

	Process {
		If ( $Line -ne $null ) {
			$Line | Write-Output
			If ( $Log -ne $null ) {
				If ( ( $Line -is [string] ) -or ( $Line -is [DateTime] ) ) {
					"$Line" | Out-File -LiteralPath:$Log -Append
				}
                ElseIf ( $Line -is [System.Management.Automation.InformationalRecord] ) {
                    $TypeName = ( $Line.GetType().Name -replace "Record$","" )
                    "{0}: {1}" -f ( $TypeName.ToUpper(), "$Line" ) | Out-File -LiteralPath:$Log -Append
                }
                ElseIf ( $Line -is [System.Management.Automation.ErrorRecord] ) {
                    $TypeName = ( $Line.GetType().Name -replace "Record$","" )
                    "{0}: {1}" -f ( $TypeName.ToUpper(), "$Line" ) | Out-File -LiteralPath:$Log -Append
                    $Line | ConvertTo-Json -Compress | Out-File -LiteralPath:$Log -Append
                }
				Else {
					$Line | ConvertTo-Json -Compress | Out-File -LiteralPath:$Log -Append
				}
			}
		}
	}

	End {		

        If ( $Log -ne $null ) {
		    $ExitMessage = @{ "Location"=$Package.FullName; "Time"=( Get-Date ).ToString() }
		    ( "! JSON[Exit]: {0}" -f ( $ExitMessage | ConvertTo-Json -Compress ) ) | Out-File -LiteralPath:$Log -Append
        }
		
	}

}

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
        $DisplayedLogLine = $null
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
                $CurDir = $Line ; $DisplayedDir = $null ; $DisplayedLogLine = $null
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
                If ( ( $DisplayedLogLine -eq $null ) -or ( $LogLine -ne $DisplayedLogLine ) ) {
                    $LogLine | Write-Host -ForegroundColor:$LogFG -BackgroundColor:Black
                    $DisplayedLogLine = $LogLine
                }
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

Function Set-CSIDiagnosticMessageStream {
Param( [Parameter(ValueFromPipeline=$true)] $For, $Value=$true )

    Begin {
        If ( $global:gCSIDiagnostics -eq $null ) {
            $global:gCSIDiagnostics = @{ }
        }    
    }

    Process {

        $For |% {
            If ( ( $Value -eq $null ) -or ( $Value -eq $false ) ) {
                If ( $global:gCSIDiagnostics.ContainsKey( $_ ) ) {
                    $global:gCSIDiagnostics.Remove( $_ )
                }
            }
            Else {
                $global:gCSIDiagnostics[ $_ ] = $Value
            } 
        }

    }

    End { }

}

Function Get-CSIDiagnosticMessageStream {
Param( [Parameter(ValueFromPipeline=$true)] $For, [switch] $Each=$false, [switch] $All=$false )

    Begin {
        $GoodList = @( )
        $TotalList =  @( )
    }

    Process {
        If ( $For -is [string] ) {
            $Name = "${For}"
        }
        ElseIf ( ( $For -is [object] ) -and ( $For | Get-Member -Name:Name ) ) {
            $Name = $For.Name
        }
        ElseIf ( ( $For -is [object] ) -and ( $For | Get-Member -Name:MyCommand ) -and ( $For.MyCommand | Get-Member -Name:Name ) ) {
            $Name = $For.MyCommand.Name
        }
        Else {
            $Name = "${For}"
        }

        $TotalList = @( $TotalList ) + @( $Name )
        If ( $global:gCSIDiagnostics.ContainsKey( $Name ) ) {
            $Value = $global:gCSIDiagnostics[ $Name ]
            If ( [bool] $Value ) {
                If ( $Each ) {
                    $Value | Write-Output
                }
                $GoodList = @( $GoodList ) + @( $Name )
            }
        }
    }

    End {
        If ( $All ) {
            ( $GoodList.Count -eq $TotalList.Count ) | Write-Output
        }
        ElseIf ( -Not $Each ) {
            ( $GoodList.Count -gt 0 ) | Write-Output
        }
    }
}

Function Get-CSIDiagnosticMessageStreamsActive {

    If ( $global:gCSIDiagnostics -is [Hashtable] ) {
        $global:gCSIDiagnostics.Keys
    }

}

Function Write-CSIDiagnosticMessageStream {
Param( [Parameter(ValueFromPipeline)] $Line, $ForegroundColor=$null, $BackgroundColor=$null, [switch] $NoNewline, $Context=@( ) )

    Begin {
        If ( $global:gCSIDiagnostics -eq $null ) {
            $global:gCSIDiagnostics = @{ }
        }
    }

    Process {
        
        If ( $Context | Get-CSIDiagnosticMessageStream ) {
            $Colors = ( $Context | Get-CSIDiagnosticMessageStream -Each |? { $_ -is [string] } |? { $_ -iin [ConsoleColor]::GetNames( [ConsoleColor] ) } )
            If ( $Colors.Count -gt 0 ) {
                $Line | Write-Host -NoNewline:$NoNewline -ForegroundColor:( $Colors | Select-Object -First:1 )
            }
            ElseIf ( ( $ForegroundColor -eq $null ) -and ( $BackgroundColor -eq $null ) ) {
                $Line | Write-Host -NoNewline:$NoNewline
            }
            ElseIf ( $ForegroundColor -eq $null ) {
                $Line | Write-Host -BackgroundColor:$BackgroundColor -NoNewline:$NoNewline
            }
            ElseIf ( $BackgroundColor -eq $null ) {
                $Line | Write-Host -ForegroundColor:$ForegroundColor -NoNewline:$NoNewline
            }
            Else {
                $Line | Write-Host -ForegroundColor:$ForegroundColor -BackgroundColor:$BackgroundColor -NoNewline:$NoNewline
            }


        }

    }

    End { }

}

Set-Alias -Name:Diagnostics -Value:Write-CSIDiagnosticMessageStream

Export-ModuleMember -Function Write-BleepBloop
Export-ModuleMember -Function Select-UserApproved

Export-ModuleMember -Function Get-BaggedItemNoticeMessage
Export-ModuleMember -Function Write-BaggedItemNoticeMessage
Export-ModuleMember -Function Write-UnbaggedItemNoticeMessage

Export-ModuleMember -Function Test-IsYesNoString
Export-ModuleMember -Function Read-YesFromHost

Export-ModuleMember -Function Get-PluralizedText
Export-ModuleMember -Function Get-ConditionalText

Export-ModuleMember -Function Write-RoboCopyOutput
Export-ModuleMember -Function Write-CSOutputWithLogMaybe

Export-ModuleMember -Function Set-CSIDiagnosticMessageStream
Export-ModuleMember -Function Get-CSIDiagnosticMessageStream
Export-ModuleMember -Function Get-CSIDiagnosticMessageStreamsActive
Export-ModuleMember -Function Write-CSIDiagnosticMessageStream
Export-ModuleMember -Alias Diagnostics
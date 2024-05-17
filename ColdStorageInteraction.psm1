#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################

$global:gColdStorageInteractionModuleCmd = $MyInvocation.MyCommand
    
    $modSource = ( $global:gColdStorageInteractionModuleCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageZipArchives.psm1" )

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
Param ( [Parameter(ValueFromPipeline=$true)] $In, [switch] $AllowEmpty )

    Begin { }

    Process {
        $ok = ( $In -match '^\s*[YyNn].*$' )
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
Param ( [string] $Prompt, $Timeout = -1.0, $DefaultInput="Y", $DefaultAction="", $DefaultTimeout = 5.0 )

        $Prompt | Write-Host -ForegroundColor Yellow
        $YNPrompt = ( '[Y]es [N]o (default is "{0}")' -f $DefaultInput )
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
        } While ( -Not ( Test-IsYesNoString -In:$InKey -AllowEmpty ) )
        
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

        ( $InKey -match '^\s*[Yy].*$' )
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


Function Write-RoboCopyOutput {
Param ( [Parameter(ValueFromPipeline=$true)] $Line, [switch] $Prolog=$false, [switch] $Epilog=$false, [switch] $Echo=$false )

    Begin { $Status = $null; $pct = 0.0; $Sect = 0; }

    Process {
        If ( "${Line}" ) {
            If ( "${Line}" -match "^\s*([0-9.]+)%\s*$" ) {
                $pct = [Decimal] $Matches[1]
            }
            Else {
                $pct = 0.0
                $Status = ( "${Line}" -replace "\t","    " )
                $Status = ( "${Status}" -replace "\s"," " )
            }
            Write-Progress -Activity ( "Robocopy.exe {0} {1}" -f "${Source}","${Destination}" ) -Status "${Status}" -PercentComplete $pct

        }

        If ( "${Line}" -match "^\s*-+\s*$" ) {
            $Sect = $Sect + 1
        }

        If ( $Echo ) {
            "${Line}"
        }

        If ( $Prolog -Or $Epilog ) {
            If ( $Prolog -and ( $Sect -le 2 ) ) {
                "${Line}" | Write-Host
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

Export-ModuleMember -Function Write-BleepBloop
Export-ModuleMember -Function Select-UserApproved

Export-ModuleMember -Function Get-BaggedItemNoticeMessage
Export-ModuleMember -Function Write-BaggedItemNoticeMessage
Export-ModuleMember -Function Write-UnbaggedItemNoticeMessage

Export-ModuleMember -Function Read-YesFromHost

Export-ModuleMember -Function Get-PluralizedText

Export-ModuleMember -Function Write-RoboCopyOutput

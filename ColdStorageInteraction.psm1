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

Function Read-YesFromHost {
Param ( [string] $Prompt, $DefaultAction="" )

        $Prompt | Write-Host -ForegroundColor Yellow
        Do {
            $InKey = ( Read-Host -Prompt '[Y]es [N]o (default is "Y")' )
        } While ( ( -Not ( $InKey -match '^[YyNn].*$' ) ) -and ( -Not ( $InKey -match '^\s*$' ) ) )
        
        If ( $InKey -match '^\s*$' ) {
            ( 'DEFAULT SELECTION - {0} ... (5 seconds to cancel)' -f $DefaultAction )
            $T0 = ( Get-Date ) ; $keyinfo = $null
            Do {
                $TDiff = ( Get-Date ) - $T0
                Write-Progress -Activity "Waiting to Trigger Default Action" -Status ( '{0} in {1:N0}' -f $DefaultAction, ( 5.0 - $TDiff.TotalSeconds ) ) -PercentComplete ( 100 * $TDiff.TotalSeconds / 5.5 )
                If ( [Console]::KeyAvailable ) { $keyinfo = [Console]::ReadKey($true) }
            } While ( ( $TDiff.TotalSeconds -lt 5.5 ) -and ( $keyinfo -eq $null ) )
                
            If ( ( $keyinfo -ne $null ) -and ( -Not ( $keyinfo.KeyChar -match "[Yy`r`n]" ) ) ) {
                $InKey = 'N'
            }
            Else {
                $InKey = 'Y'
            }
        }

        ( $InKey -match '^[Yy].*$' )
}

Export-ModuleMember -Function Write-BleepBloop
Export-ModuleMember -Function Select-UserApproved

Export-ModuleMember -Function Get-BaggedItemNoticeMessage
Export-ModuleMember -Function Write-BaggedItemNoticeMessage
Export-ModuleMember -Function Write-UnbaggedItemNoticeMessage

Export-ModuleMember -Function Read-YesFromHost

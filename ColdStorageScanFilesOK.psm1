#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################

Function My-Script-Directory {
Param ( $Command, $File=$null )

    $Source = ( $Command.Source | Get-Item -Force )
    $Path = ( $Source.Directory | Get-Item -Force )

    If ( $File -ne $null ) {
        $Path = ($Path.FullName + "\" + $File)
    }

    $Path
}

$global:gScanFilesOKCmd = $MyInvocation.MyCommand

Import-Module $( My-Script-Directory -Command $global:gScanFilesOKCmd -File "ColdStorageSettings.psm1" )
Import-Module $( My-Script-Directory -Command $global:gScanFilesOKCmd -File "ColdStorageFiles.psm1" )
Import-Module $( My-Script-Directory -Command $global:gScanFilesOKCmd -File "ColdStorageBagItDirectories.psm1" )
Import-Module $( My-Script-Directory -Command $global:gScanFilesOKCmd -File "ColdStorageRepositoryLocations.psm1" )

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################


Function Test-CSOutputForValidationErrors {
Param ( [Parameter(ValueFromPipeline=$true)] $Message )

Begin { $ExitCode = 0 }

Process {
    If ( -Not ( $Message -match "^OK-" ) ) {
        $ExitCode = $ExitCode + 1
    }
}

End { $ExitCode }

}

Function Test-CSFilesOK {

    [CmdletBinding()]

Param (
    [String[]]
    $Skip=$false,

    [Int[]]
    $OKCodes=@( 0 ),

    [switch]
    $ShowWarnings=$false,

    [Parameter(ValueFromPipeline=$true)]
    $Path

)

    Begin { }

    Process {
        $outPath = ( $Path | Select-CSFilesOK -Skip:$Skip -OKCodes:$OKCodes )

        ( $outPath.Count -eq $Path.Count ) | Write-Output
    }

    End { }

}
                
Function Select-CSFilesOK {

    [CmdletBinding()]

Param (
    [String[]]
    $Skip=@(), 

    [Int[]]
    $OKCodes=@( 0 ),

    [Int[]]
    $ContinueCodes=@( 0 ),

    [switch]
    $ShowWarnings=$false,

    [Parameter(ValueFromPipeline=$true)]
    $Path

)

    Begin { }

    Process {
        $Path `
        | Select-CSFilesOKByClamAV -Skip:$Skip -OKCodes:$OKCodes -ContinueCodes:$ContinueCodes -ShowWarnings:$ShowWarnings `
        | Write-Output
    }
    #  -Verbose:$Verbose
    End { }


}

Function Select-CSFilesOKByClamAV {

    [CmdletBinding()]

Param (
    [String[]]
    $Skip=@(),

    [Int[]]
    $OKCodes=@( 0 ),

    [Int[]]
    $ContinueCodes=@( 0 ),

    [Parameter(ValueFromPipeline=$true)]
    $Path,

    [switch]
    $ShowWarnings=$false

)

    Begin { }

    Process {
        # VARIABLES
        $bOK = $false
        $bContinue = $false
        $iExitCode = $null

        # CODE
        $scanned = ( $Path | Get-CSFilesClamAVScanCode -Skip:$Skip -OKCodes:$OKCodes -ContinueCodes:$ContinueCodes ) # -Verbose:$Verbose
        $iExitCode = $scanned.CSScannedOK["clamav"].ExitCode
        $bOK = (( $OKCodes -eq $iExitCode ).Count -gt 0 )
        $bContinue = (( $ContinueCodes -eq $iExitCode ).Count -gt 0 )

        If ( $bOK -or $bContinue ) {
            $scanned | Write-Output
        }
        ElseIf ( $ShowWarnings ) {
            "[clamav] Exit Code {0:N0} for {1}" -f ( $scanned.CSScannedOK["clamav"][0], $scanned.FullName ) | Write-Warning
        }

    }

    End { }
}

Function Get-CSFilesClamAVScanCode {

    [CmdletBinding()]

Param (
    [String[]]
    $Skip=@(),

    [Int[]]
    $OKCodes=@( 0 ),

    [Int[]]
    $ContinueCodes=@( 0 ),

    [String]
    $Tag="clamav",

    [Parameter(ValueFromPipeline=$true)]
    $Path

)

    Begin { }

    Process {
        $exe = Get-ExeForClamAV
        $params = @( "--stdout", "--bell", "--suppress-ok-results", "--recursive", ( "{0}" -f $Path.FullName ) )
        $Path | Get-CSFilesExeScanCode -Skip:$Skip -OKCodes:$OKCodes -ContinueCodes:$ContinueCodes -Exe:$exe -ExeParams:$params -Tag:$Tag -Verbose:$Verbose
    }
    
    End { }

}

Function Get-CSFilesExeScanCode {

    [CmdletBinding()]

Param (
    [String[]]
    $Skip=@(),

    [Int[]]
    $OKCodes=@( 0 ),

    [Int[]]
    $ContinueCodes=@( 0 ),

    [String]
    $Exe,

    [String[]]
    $ExeParams,

    [String]
    $Tag=$null,

    [Hashtable]
    $Labels=@{ "Scanning"="Scanning"; "Scanned"="Scanned"; "Scan"="Scan" },

    [Parameter(ValueFromPipeline=$true)]
    $Path

)

    Begin { }

    Process {
        # VARIABLES
        $outPath = $Path
        $sStdOut = $null
        $ExeExitCode = $null
        $ok = @{}

        # CODE
        If ( $Tag -eq $null ) {
            $Tag = ( $Exe | Split-Path -Leaf )
        }

        $outPath | Get-Member -MemberType NoteProperty -Name CSScannedOK |% {
            $ok = ( $ok, $outPath.CSScannedOK | Get-TablesMerged )
        }

        If ( ( $Skip -ieq $tag ).Count -eq 0 ) {
            ( "[{0}] {1}: {2}" -f $tag, $Labels["Scanning"], $outPath.FullName ) | Write-Verbose -InformationAction Continue

            $sStdOut = ( ( & "${Exe}" @ExeParams ) |% { If ( $Verbose ) { $_ | Write-Verbose -InformationAction Continue }; $_ } )

            $ExeExitCode = $LastExitCode
            
            $ok[$tag] = [PSCustomObject] @{ "ExitCode"=$ExeExitCode; "Executed"=$true; "OK"=$OKCodes; "Continue"=$ContinueCodes }

            $outPath | Add-Member -MemberType NoteProperty -Name CSScannedOK -Value $ok -Force -PassThru

            if ( ( $OKCodes -eq $ExeExitCode ).Count -gt 0 ) {
            # Success: At least one item of $OKCodes matches
                ( "[{0}] (ok) {1} of {2} returned {3:N0}" -f ( $tag, $Labels["Scan"], $outPath.FullName, $ExeExitCode ) ) | Write-Verbose
            }
            Else {
            # Failure: no items of $OKCodes match
                ( "[{0}] {1}: {2}" -f $tag, $Labels["Scanned"], $outPath.FullName ) | Write-Warning
                $sStdOut | Write-Warning
            }
        }
        Else {
            ( "[{0}] (ok-SKIPPED) {1}: {2}" -f $tag, $Labels["Scanned"], $outPath.FullName ) | Write-Verbose -InformationAction Continue

            $ok[$tag] = [PSCustomObject] @{ "ExitCode"=$OKCodes[0]; "Executed"=$false; "OK"=$OKCodes; "Continue"=$ContinueCodes }

            $outPath | Add-Member -MemberType NoteProperty -Name CSScannedOK -Value $ok -Force -PassThru
        }
    }

    End { }
}

Function Get-CSScannedFilesErrorCodes {

Param (

    [Switch]
    $All=$false,

    [Parameter(ValueFromPipeline=$true)]
    $Path

)

    Begin { }

    Process {
        $GotSome = $false

        $Path | Get-Member -MemberType NoteProperty -Name CSScannedOK |% {
            $ok = $Path.($_.Name)
            $ok.Keys |% {
                $Key = $_ ; $Line = $ok[$Key].PSObject.Copy()
                If ( -Not $GotSome ) {
                    If ( ( $Line.OK -eq $Line.ExitCode ).Count -eq 0 ) {
                        $Line `
                        | Add-Member -MemberType NoteProperty -Name Path -Value $Path -Force -PassThru `
                        | Add-Member -MemberType NoteProperty -Name Tag -Value $Key -Force -PassThru `

                        $GotSome = $true
                    }
                }
            }
        }
    }

    End { }

}

Function Select-WhereWeShallContinue {
Param ( [Parameter(ValueFromPipeline=$true)] $Item, [switch] $Force=$false, [Int[]] $OKCodes=@( 0 ), [Int[]] $MaybeCodes=@( ) )

    Begin { }

    Process {

        If ( $Item | Test-ShallWeContinue -Force:$Force -OKCodes:$OKCodes -MaybeCodes:$MaybeCodes ) {
            $Item
        }

    }

    End { }

}

Function Read-ShallWeContinueBasedOn {
Param ( [Parameter(ValueFromPipeline=$true)] $Outcome, [switch] $Force=$false, [switch] $Stopped=$false, $MaybeTimeout=30 )

    Begin { }

    Process {
        
        If ( $Outcome ) {
            $ExitCode = $Outcome.ExitCode
            $Tag = $( If ( $Outcome.Tag ) { "[{0}] " -f $Outcome.Tag } Else { "" } )
            
            $Mesg = ( "{0}Exit Code {1:N0}" -f $Tag, $ExitCode )
            $ShouldContinueMaybe = ( -Not $Stopped )
            If ( $ShouldContinueMaybe ) {
                If ( $Force ) {
                    ( "{0}; continuing anyway due to -Force flag" -f $Mesg ) | Write-Warning
                }
                ElseIf ( ( $Outcome.Tag -eq 'clamav' ) -and ( $ExitCode -eq 2 ) ) {
                    $ShouldContinueMaybe = ( & read-yesfromhost-cs.ps1 -Prompt ( "{0}. Continue?" -f $Mesg ) -Timeout:$MaybeTimeout )
                }
                Else {
                    $ShouldContinueMaybe = ( & read-yesfromhost-cs.ps1 -Prompt ( "{0}. Continue?" -f $Mesg ) )
                }
            }
            Else {
                ( "{0}; stopped due to user input." -f $Mesg ) | Write-Warning
            }

            $ShouldContinueMaybe
        }

    }

    End { }

}

Function Test-ShallWeContinue {
Param ( [Parameter(ValueFromPipeline=$true)] $Item, [switch] $Force=$false, [Int[]] $OKCodes=@( 0 ), [Int[]] $MaybeCodes=@( ), $MaybeTimeout=30 )

    Begin { $result = $true }

    Process {
        $ExitCode = $null

        If ( $Item | Get-Member -MemberType NoteProperty -Name CSScannedOK ) {
            $ErrorCodes = ( $Item | Get-CSScannedFilesErrorCodes )
        }
        ElseIf ( ( $Item -is [Int] ) -or ( $Item -is [Long] ) -or ( $Item -is [Array] ) ) {
        # Singleton, treat as an ExitCode, with default convention 0=OK, 1..255=Error
            $ErrorCodes = ( $Item |% { $ExitCode=$_ ; $ok = ( $OKCodes -eq $ExitCode ) ; If ( $ok.Count -eq 0 ) { [PSCustomObject] @{ "ExitCode"=$ExitCode; "OK"=$OKCodes } } } )
        }

        $ShouldWeContinue = "Y"
        $ErrorCodes |% {
            $Outcome = $_
            If ( $Outcome ) {
                $ContinueOK = ( $Outcome | Read-ShallWeContinueBasedOn -Force:$Force -Stopped:( -Not $result ) -MaybeTimeout:$MaybeTimeout )
                $result = ( $result -and $ContinueOK )
            }
        }
    }

    End { $result }

}

Export-ModuleMember -Function Test-CSOutputForValidationErrors
Export-ModuleMember -Function Select-WhereWeShallContinue
Export-ModuleMember -Function Test-ShallWeContinue

Export-ModuleMember -Function Test-CSFilesOK
Export-ModuleMember -Function Select-CSFilesOK
Export-ModuleMember -Function Select-CSFilesOKByClamAV
Export-ModuleMember -Function Get-CSFilesClamAVScanCode
Export-ModuleMember -Function Get-CSFilesExeScanCode
Export-ModuleMember -Function Get-CSScannedFilesErrorCodes

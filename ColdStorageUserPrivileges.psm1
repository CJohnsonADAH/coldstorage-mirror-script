#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################

$global:gColdStorageUserPrivilegesModuleCmd = $MyInvocation.MyCommand
    
    $modSource = ( $global:gColdStorageUserPrivilegesModuleCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

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

Function Get-ColdStorageAccessTestPath {
    '\\ADAHColdStorage\ElectronicRecords\Unprocessed'
}

Function Test-UserHasNetworkAccess {
    If ( Test-Path ( Get-ColdStorageAccessTestPath ) ) {
        $true
    }
    Else {
        $false
    }
}
Function Invoke-SelfWithNetworkAccess {
Param ( $Invocation, $Credentials=$null, [switch] $Loop=$false )

        $Cmd = $Invocation.MyCommand

    $newProcess = new-object System.Diagnostics.ProcessStartInfo( "powershell.exe" );
    $cmdLine = ( '"{0}"' -f $Cmd.Source )
    
    $Params = @{ }
    $Invocation.BoundParameters.Keys |% {
        $Params[ $_ ] = $Invocation.BoundParameters[ $_ ]
    }
    $Params[ 'SU' ] = $true
    
    $Params.Keys |% {
        $ParamDef = $Cmd.Parameters[ $_ ]
        
        $NextArgument = $null
        If ( $ParamDef.SwitchParameter ) {
            If ( -Not ( -Not ( $Params[ $_ ] ) ) ) {
                $NextArgument = ( "-{0}" -f $_ )
            }
        }
        ElseIf ( $Params[ $_ ].GetType() -eq [int] ) {
            $NextArgument = ( "-{0}:{1}" -f $_, $Params[ $_ ].ToString() )
        }
        Else {
            $NextArgument = ( "-{0}:'{1}'" -f $_, $Params[ $_ ].ToString() )
        }

        If ( $NextArgument -ne $null ) {
            $cmdLine = ( "{0} {1}" -f $cmdLine,$NextArgument )
        }

    }
    $newProcess.Arguments = $cmdLine

    If ( $Credentials -eq $null ) {
        # Indicate that the process should be elevated
        $UserName = ( Read-Host -Prompt "User [Administrator]" )
        $Password = ( Read-Host -Prompt "Password" -AsSecureString )
    }
    Else {
        $UserName = ( $Credentials.UserName )
        $Password = ( $Credentials.Password )
    }

    $newProcess.UseShellExecute = $false
    If ( $UserName -match '^\s*$' ) {
        $UserName = 'Administrator'
    }

    $UserDomain = ( ( $UserName -split '[\\]', 2 ) | Select-Object -SkipLast 1 | Select-Object -First 1 )
    $UserName = ( ( $UserName -split '[\\]', 2 ) | Select-Object -Last 1 )

    If ( $UserDomain ) {
        $newProcess.Domain = $UserDomain
    }
    Else {
        If ( -Not ( ( Get-LocalUser ).Name -contains $UserName ) ) {
            $DefaultDomain = "STATE"
            ( "[{0}] '{1}' not a local user name. Assuming domain: {2}" -f $Cmd.Name,$UserName,$DefaultDomain ) | Write-Warning
            $newProcess.Domain = $DefaultDomain
        }
    }
    $newProcess.UserName = $UserName
    $newProcess.Password = $Password

    # Start the new process
    "OKOKOK"|Write-Warning
    $process = ( [System.Diagnostics.Process]::Start($newProcess) )
    If ( $process ) {
        $process.WaitForExit()
        $ExitCode = $process.ExitCode
    }
    Else {
        $ExitCode = 255
        If ( $Loop ) {
            While ( -Not $process ) {
                $nSeconds = 600 ; $iSeconds = $nSeconds
                Do {
                    Write-Progress -Activity "Waiting to retry." -Status $iSeconds -PercentComplete ( ( $nSeconds - $iSeconds ) / $nSeconds )
                    Sleep 1
                    $iSeconds = ( $iSeconds - 1 )
                } While ( $iSeconds -gt 0 )
                Write-Progress -Activity "Waiting to retry." -Status $nSeconds -Completed
                
                $process = ( [System.Diagnostics.Process]::Start($newProcess) )
                If ( $process ) {
                    $process.WaitForExit()
                    $ExitCode = $process.ExitCode
                }
            }

        }

    }
    
    Return $ExitCode

}


Export-ModuleMember -Function Get-ColdStorageAccessTestPath
Export-ModuleMember -Function Test-UserHasNetworkAccess
Export-ModuleMember -Function Invoke-SelfWithNetworkAccess

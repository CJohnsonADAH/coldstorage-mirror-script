#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################

$global:gColdStorageProgressModuleCmd = $MyInvocation.MyCommand
    
    $modSource = ( $global:gColdStorageProgressModuleCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

$global:gProgressNextId = 1001

Class CSProgressMessenger {
    [Int] $Id
    [String] $Activity
    [String] $Status
    [Int] $I
    [Int] $N
    [bool] $CompletedOverride
    [String] $Stream

    CSProgressMessenger( ) {
        $this.Init( $true, $false )
    }

    CSProgressMessenger( $Interactive ) {
        $this.Init( $Interactive, $false )
    }

    CSProgressMessenger( $Interactive, $Batch ) {
        $this.Init( $Interactive, $Batch )
    }

    [void] Init ( $Interactive, $Batch ) {
        $this.Id = ( ${global:gProgressNextId} + 1 )
        $global:gProgressNextId = (${global:gProgressNextId} + 1)

        $this.I = 0
        $this.N = 100

        If ( $Interactive ) {
            $this.SetStream("Progress")
        }
        ElseIf ( $Batch ) {
            $this.SetStream("Output")
        }
        Else {
            $this.SetStream($null)
        }

        $this.CompletedOverride = $false
    }

    [void] SetStream ($Stream) {
        $this.Stream = $Stream
    }

    [void] Redraw() {
        If ( $this.Stream -eq "Progress" ) {
            Write-Progress -Id:($this.Id) -Activity:($this.Activity) -Status:($this.Status) -PercentComplete:($this.percentComplete()) -Completed:($this.Completed())
        }
    }

    [void] Open( [String] $Activity, [String] $Status ) {
        $this.Open( $Activity, $Status, 0 )
    }

    [void] Open( [String] $Activity, [String] $Status, [int] $N ) {
        $this.Activity = $Activity
        If ( $Status ) {
            $this.Status = $Status
        }
        $this.I = 0
        If ( $N -gt 0 ) {
            $this.N = $N
        }
        $this.Redraw()
    }

    [void] Update( [String] $Status ) {
        $this.Update($Status, 1, 0, "")
    }

    [void] Update( [String] $Status, [String] $LogMessage ) {
        $this.Update($Status, 1, 0, $LogMessage)
    }

    [void] Update( [String] $Status, [int] $Step ) {
        $this.Update($Status, $Step, 0, "")
    }

    [void] Update( [String] $Status, [int] $Step, [String] $LogMessage ) {
        $this.Update($Status, $Step, 0, $LogMessage)
    }

    [void] Update( [String] $Status, [int] $Step, [int] $N ) {
        $this.Update($Status, $Step, $N, "")
    }

    [void] Update( [String] $Status, [int] $Step, [int] $N, [String] $LogMessage ) {
        $this.Status = $Status

        If ( $N -gt 0 ) {
            $this.I = $Step
            $this.N = $N
        }
        Else {
            $this.I = $this.I + $Step
        }
        $this.Redraw()

        If ( $LogMessage )  {
            $this.Log($LogMessage)
        }
    }

    [void] Log ( [String] $Status ) {
        
        If ( $this.Stream -eq "Output" ) {
            $Status | Write-Output
        }
        ElseIf ( $this.Stream -eq "Verbose" ) {
            $Status | Write-Verbose
        }
        ElseIf ( $this.Stream -eq "Warning" ) {
            $Status | Write-Warning
        }
        ElseIf ( $this.Stream -eq "Debug" ) {
            $Status | Write-Debug
        }
        ElseIf ( $this.Stream -eq "Host" ) {
            $Status | Write-Host
        }

    }

    [void] Complete() {
        $this.CompletedOverride = $true
        $this.Redraw()
    }

    [double] percentComplete() {
        return ((100.0 * $this.I) / (1.0 * $this.N))
    }

    [bool] Completed() {
        return ( $this.CompletedOverride -or ( $this.percentComplete() -ge 100.0 ) )
    }

}

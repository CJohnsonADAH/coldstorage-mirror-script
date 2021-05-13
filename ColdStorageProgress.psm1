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
    [Object[]] $Segments

    CSProgressMessenger( ) {
        $this.Init( $true, $false )
    }

    CSProgressMessenger( $Interactive ) {
        $this.Init( $Interactive, $false, 100 )
    }

    CSProgressMessenger( $Interactive, $Batch ) {
        $this.Init( $Interactive, $Batch, 100 )
    }

    CSProgressMessenger( $Interactive, $Batch, [int] $N ) {
        $this.Init( $Interactive, $Batch, $N )
    }

    [void] Init ( $Interactive, $Batch, $N=100) {
        $this.Id = ( ${global:gProgressNextId} + 1 )
        $global:gProgressNextId = (${global:gProgressNextId} + 1)

        $this.I = 0
        $this.N = $N

        $this.Segments = @()
        $this.Segments += , @{ "In"=( $this.I ); "I"=( $this.I );  "N"=( $this.N ) }

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
            $Seg = $this.Segment()
            
            ( "I={0}; SEGMENT={1}" -f $this.I,( $Seg | ConvertTo-Json -Compress ) ) | Write-Debug
            
            $SegmentI = ( [Int] $this.I - [Int] $Seg.I )
            $SegmentN = ( 0 + [Int] $Seg.N )
            $FmtParams = ( $SegmentI, $SegmentN, $this.I, $this.N, ($SegmentI + 1), $SegmentN, ($this.I + 1), ($this.N) )

            ( "PARAMS={0}" -f $( $FmtParams | ConvertTo-Json -Compress ) ) | Write-Debug

            Write-Progress -Id:($this.Id) -Activity:($this.Activity) -Status:($this.Status -f $FmtParams) -PercentComplete:($this.percentComplete()) -Completed:($this.Completed())
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
        $resetN = $this.N

        $this.N = 0
        $this.Segments = @()
        $this.InsertSegment( $resetN )

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

            If ( $this.I -gt $this.N ) {
                $this.InsertSegment(1)
            }

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
        $pct = ((100.0 * $this.I) / (1.0 * $this.N))
        If ( ( $pct -lt 0.0 ) -or ( $pct -gt 100.0 ) ) {
            ( "There's a calculation error with the progress bar: {0:N}% complete?!" -f $pct ) | Write-Warning
        }
        return [Math]::Min( [Math]::Abs($pct), 100.0 )
    }

    [bool] Completed() {
        return ( $this.CompletedOverride -or ( $this.percentComplete() -ge 100.0 ) )
    }

    [void] InsertSegment ( [int] $N ) {

        ( "BEFORE INSERT: SEGMENTS={0}" -f ($this.Segments | ConvertTo-Json -Compress) ) | Write-Debug

        If ( $this.Segments.Count -gt 0 ) {

            $Head = $this.SegmentHead()
            $Seg = $this.Segment()
            $hSeg = @{
                "In"=( $Seg.In )
                "Out"=( $this.I )
                "I"=( $Seg.I )
                "N"=( $Seg.N )
            }

            $InsertedOut = ( $this.I + $N )
            $CoveredItems = ( $this.I - $Seg.In )
            $Inserted = @{
                "In"=( $this.I )
                "Out"=( $InsertedOut )
                "I"=( 0 )
                "N"=( $N )
            }
            $Remainder = @{
                "In"=( $InsertedOut )
                "Out"=( ( $InsertedOut ) + ( $Seg.N - $CoveredItems ) )
                "I"=( $this.I - $Seg.In )
                "N"=( $Seg.N )
            }
            $Tail = ( $this.SegmentTail() |% { If ( $_ ) { $o = [PSCustomObject] $_ ; @{ "In"=( $o.In + $N ); "Out"=( $o.Out + $N ); "I"=( $o.I ); "N"=( $o.N ) } } } )

            $this.Segments = @( $Head ) + @( $hSeg, $Inserted, $Remainder ) + @( $Tail )

            ( "AFTER INSERT: SEGMENTS={0}" -f ($this.Segments | ConvertTo-Json -Compress) ) | Write-Debug

        }
        Else {

            $this.Segments = @()
            $this.Segments += , @{ "In"=( $this.I ); "Out"=( $this.N + $N ); "I"=( 0 ); "N"=( $N ) }

        }

        $this.N = $this.N + $N

    }

    [Bool] OutOfBounds ( $Segment ) {
        Return ( $this.I -gt ( $Segment.I + $Segment.N ) )
    }

    [Object] Segment ( ) {

        $Seg = ( $this.Segments |% { [PSCustomObject] $_ } |? { $this.I -ge $_.In } | Select-Object -Last 1 )
        Return [PSCustomObject] $Seg

    }

    [Object[]] SegmentHead ( ) {
        Return ( $this.Segments |? { $o = [PSCustomObject] $_ ; $this.I -ge $o.In } | Select-Object -SkipLast 1 )
    }

    [Object[]] SegmentTail ( ) {
        $Tail = ( $this.Segments |? { $o = [PSCustomObject] $_ ; $this.I -lt $o.In } )
        Return $Tail
    }

}

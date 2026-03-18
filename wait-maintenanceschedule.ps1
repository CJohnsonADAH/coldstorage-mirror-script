Param(
    [String] $By="11:59PM",
    [String] $Label="",
    [switch] $Loop=$false,
    [ScriptBlock] $Job={}
)

$ExitCode = 0

Do {
    $WaitUntil = [DateTime]::Parse( $By )
    $Now = ( Get-Date )
    If ( $WaitUntil -lt $Now ) {
        $WaitUntil = $WaitUntil + [TimeSpan]::FromDays(1)
    }

    $Seconds = ( $WaitUntil - $Now ).TotalSeconds
    
    If ( $Label.Length -gt 0 ) {
        $PromptTemplate = "Initiate scheduled {1} job ({0})"
    }
    Else {
        $PromptTemplate = "Initiate scheduled job ({0})"
    }

    $Execute = ( & read-yesfromhost-cs.ps1 -Prompt:( $PromptTemplate -f $WaitUntil, $Label ) -Timeout:$Seconds )
    If ( $Execute ) {
        & $Job
    }
} While ( $Loop -and $Execute )

Exit $ExitCode

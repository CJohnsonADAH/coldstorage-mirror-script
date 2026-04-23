Param(
    $LiteralPath=$null,
    [switch] $Push=$false,
    [switch] $Pop=$false,
    [switch] $ColdStorage=$false,
    [switch] $Original=$false,
    [switch] $Reflection=$false,
    [switch] $Forward=$false,
    [switch] $Quiet=$false
)

    Function Get-CSScriptDirectory {
    Param ( $File=$null )
        $ScriptPath = ( Split-Path -Parent $PSCommandPath )
        If ( $File -ne $null ) { $ScriptPath = ( Join-Path "${ScriptPath}" -ChildPath "${File}" ) }
        ( Get-Item -Force -LiteralPath "${ScriptPath}" )
    }

# Internal Dependencies - Modules
$bVerboseModules = ( $Debug -eq $true )
$bForceModules = ( ( $Debug -eq $true ) -or ( $psISE ) )

Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageFiles.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageMirrorFunctions.psm1" )

    $ExitCode = 0

    Function Write-SLTMNotice {
    Param(
        [Parameter(ValueFromPipeline=$true)] $Line,
        [switch] $Quiet=$false,
        $ForegroundColor="Yellow",
        $BackgroundColor="Black"
    )

        Begin { }

        Process {
            If ( -Not $Quiet ) {
                "[{0}] {1}" -f ( $global:gCSCommandWithVerb ), $Line | Write-Host -ForegroundColor:$ForegroundColor -BackgroundColor:$BackgroundColor
            }
        }

        End { }
    }

If ( ( $LiteralPath -eq $null ) -or ( $LiteralPath.Count -eq 0 ) ) {
    $Destinations = @( Get-Item -LiteralPath ( ( Get-Location ).Path ) -Force )
}
Else {
    $Destinations = @( $LiteralPath | get-file-cs.ps1 -Object )
}

$Destinations |% {
    $Destination = $_
    If ( ( $Original -or ( $ColdStorage -or $Reflection ) ) -or $Forward ) {
        $Mirror = ( $Destination | get-mirrormatcheditem-cs.ps1 -ColdStorage:$ColdStorage -Reflection:$Reflection -Original:$Original -Forward:$Forward | Get-FileObject )
    }
    Else {
        $Mirror = ( $Destination | get-mirrormatcheditem-cs.ps1 -Other | Get-FileObject )
    }

    If ( $Mirror ) {
        If ( $Push ) {
            "Pushing Location '{0}' onto stack" -f $Mirror.FullName | Write-SLTMNotice -Quiet:$Quiet
            Push-Location -LiteralPath $Mirror.FullName -Verbose
        }
        ElseIf ( $Pop ) {
            "Popping Location from stack" | Write-SLTMNotice -Quiet:$Quiet
            Pop-Location
        }
        Else {
            "Setting Location to '{0}'" -f $Mirror.FullName | Write-SLTMNotice -Quiet:$Quiet
            Set-Location -LiteralPath $Mirror.FullName -Verbose
        }
    }
    Else {
        "Cannot find mirrored Location for '{0}'" -f $Destination.FullName | Write-SLTMNotice -Quiet:$Quiet -ForegroundColor:Red
        $ExitCode = 1
    }
}

Exit $ExitCode

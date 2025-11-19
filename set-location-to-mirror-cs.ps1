Param(
    $LiteralPath=$null,
    [switch] $Push=$false,
    [switch] $Pop=$false,
    [switch] $ColdStorage=$false,
    [switch] $Original=$false,
    [switch] $Reflection=$false
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

If ( ( $LiteralPath -eq $null ) -or ( $LiteralPath.Count -eq 0 ) ) {
    $Destinations = @( Get-Item -LiteralPath ( ( Get-Location ).Path ) -Force )
}
Else {
    $Destinations = @( $LiteralPath | get-file-cs.ps1 -Object )
}

$Destinations |% {
    $Destination = $_
    If ( $Original -or ( $ColdStorage -or $Reflection ) ) {
        $Mirror = ( $Destination | get-mirrormatcheditem-cs.ps1 -ColdStorage:$ColdStorage -Reflection:$Reflection -Original:$Original | Get-FileObject )
    }
    Else {
        $Mirror = ( $Destination | get-mirrormatcheditem-cs.ps1 -Other | Get-FileObject )
    }

    If ( $Mirror ) {
        If ( $Push ) {
            "[{0}] Pushing Location '{1}' onto stack" -f $global:gCSCommandWithVerb, $Mirror.FullName | Write-Host -ForegroundColor Yellow -BackgroundColor Black
            Push-Location -LiteralPath $Mirror.FullName -Verbose
        }
        ElseIf ( $Pop ) {
            "[{0}] Popping Location from stack" -f $global:gCSCommandWithVerb, $Mirror.FullName | Write-Host -ForegroundColor Yellow -BackgroundColor Black
            Pop-Location
        }
        Else {
            "[{0}] Setting Location to '{1}'" -f $global:gCSCommandWithVerb, $Mirror.FullName | Write-Host -ForegroundColor Yellow -BackgroundColor Black
            Set-Location -LiteralPath $Mirror.FullName -Verbose
        }
    }
    Else {
        "[{0}] Cannot find mirrored Location for '{1}'" -f $global:gCSCommandWithVerb, $Location.FullName | Write-Host -ForegroundColor Red -BackgroundColor Black
    }
}

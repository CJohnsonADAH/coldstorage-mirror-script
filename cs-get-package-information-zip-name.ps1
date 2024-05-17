Param(
    [Parameter(ValueFromPipeline=$true)] $Item
)

Begin {

    Function Get-CSScriptDirectory {
    Param ( $File=$null )
        $ScriptPath = ( Split-Path -Parent $PSCommandPath )
        If ( $File -ne $null ) { $ScriptPath = ( Join-Path "${ScriptPath}" -ChildPath "${File}" ) }
        ( Get-Item -Force -LiteralPath "${ScriptPath}" )
    }
    
    # Internal Dependencies - Modules
    $Verbose = ( $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent )
    $Verbose = $( If ( $Verbose -eq $null ) { $false } Else { $Verbose } )
    $Debug = ( $PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent )
    $Debug = $( If ( $Debug -eq $null ) { $false } Else { $Debug } )

    $bVerboseModules = ( $Debug -eq $true )
    $bForceModules = ( ( $Debug -eq $true ) -or ( $psISE ) )
    
    Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ColdStorage-Script-Dir -File "ColdStorageZipArchives.psm1" )

}

Process {
    $Item | Get-FileObject |% {
        $File = $_
        [PSCustomObject] @{
            "File"=($File.FullName);
            "Prefix"=($File | Get-ZippedBagNamePrefix );
            "Container"=($File | Get-ZippedBagsContainer).FullName
        }
    }
}

End {
}

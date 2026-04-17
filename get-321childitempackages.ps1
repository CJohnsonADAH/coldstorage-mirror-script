Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    [int] $Depth=0,
    [int] $MaxDepth=999
)

Begin {
    $ExitCode = 0

    $global:g321LocationPackagesCmd = $MyInvocation.MyCommand

        $modSource = ( $global:g321LocationPackagesCmd.Source | Get-Item -Force )
        $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageData.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageRepositoryLocations.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageBagItDirectories.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageInteraction.psm1" )

    If ( $Depth -ge $MaxDepth ) {
        $ExitCode = 255
    }

    Function Get-321LocationPackages {
    Param(
        [Parameter(ValueFromPipeline=$true)] $Location,
        [int] $Depth=0,
        [int] $MaxDepth=999
    )

        Begin { }

        Process {
            If ( Test-Path -LiteralPath:$Location.FullName -PathType:Container ) {

                If ( $Location | Test-BagItFormattedDirectory ) {
                    $Location | Get-ItemPackage -At
                }
                Else {
                    $LooseFiles = ( Get-ChildItem -LiteralPath:$Location.FullName -File -Force | Get-ItemPackage -At )
                    If ( $Depth -lt $MaxDepth ) {
                        $Subdirectories = ( Get-ChildItem -LiteralPath:$Location.FullName -Directory -Force |? { $_.Name -notlike '.*' } | Get-321LocationPackages -Depth:( $Depth + 1 ) -MaxDepth:$MaxDepth )
                    }
                    Else {
                        $ExitCode = 255
                        "[{0}] MaxDepth exceeded: {1}" -f ( CSDbg -Function:$MyInvocation ), ( $Location.FullName | ConvertTo-Json -Compress ) | Write-Warning
                        $Subdirectories = @( )
                    }

                    @( $LooseFiles ) + @( $Subdirectories ) | Write-Output
                }
            }
            ElseIf ( Test-Path -LiteralPath:$Location.FullName -PathType:Leaf ) {
                $Location | Get-ItemPackage -At
            }

        }

        End { }

    }

}

Process {

    If ( $Depth -lt $MaxDepth ) {
        
        $Item | Get-FileObject | Get-321LocationPackages -Depth:$Depth -MaxDepth:$MaxDepth

    }
    
}

End {
    Exit $ExitCode
}

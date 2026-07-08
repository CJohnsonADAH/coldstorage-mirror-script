Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    [switch] $NoBags,
    [switch] $NoSingletons,
    [switch] $NoUnpackagedSingletons,
    [switch] $NoLeafContainers,
    [switch] $Profile,
    [String[]] $Exclude=@( "ZIP" )
)

Begin {

    $ExitCode = 0

    $global:g321PreservationPackageCandidatesCmd = $MyInvocation.MyCommand

        $modSource = ( $global:g321PreservationPackageCandidatesCmd.Source | Get-Item -Force )
        $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageData.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageRepositoryLocations.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageBagItDirectories.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )
}

Process {
    
    If ( $Item -ne $null ) {
    
        $Container = ( $Item | Get-FileObject )
        
        If ( -Not ( $NoBags ) ) {
            Get-ChildItem -LiteralPath:$Container.FullName -Directory -Recurse -Force |? { ( $_.Name -notlike '.*' ) -and ( $_.FullName -notlike '*\.*\*' ) } |? { $_.Name -notin @( $Exclude ) } |? {
                ( $_.Name -eq 'data' )
            } |% {
                $_.Parent
            } |? {
                ( $_ | Test-BagItFormattedDirectory )
            } |? {
                If ( $Profile ) {
                    Write-Progress -Id:068 -Activity:"Screening" -Status:( '[{0}: {1}] Collecting bagged directories: {2}' -f ( (Get-Date) - $tN[-1] ), $tN[-1], $_.FullName )
                }
                -Not ( $_ | Test-BagItFormattedDirectoryContent )
            }
        }

        If ( -Not ( $NoSingletons ) ) {
            Get-ChildItem -LiteralPath:$Container.FullName -Directory -Recurse -Force |? { ( $_.FullName -notlike '*\.*\*' ) } |? { $_.Name -notin @( $Exclude ) } |? {
                ( $_.Name -eq '.bagged' )
            } |% {
                If ( $Profile ) {
                    Write-Progress -Id:068 -Activity:"Screening" -Status:( '[{0}: {1}] Collecting packaged singletons: {2}' -f ( (Get-Date) - $tN[-1] ), $tN[-1], $_.FullName )
                }

                If ( $NoUnpackagedSingletons ) {
                    $PackagedSingletons = ( Get-ChildItem -LiteralPath:$_.FullName -File -Force |? { $_.Name -like '*.package.json' } )               
                    $PackagedSingletons | Get-321LooseFileFromSidecarFile

                    Get-ChildItem -LiteralPath:$_.FullName -Directory -Recurse -Force |? {
                        ( $_.Name -eq 'data' )
                    } |% {
                        $_.Parent
                    } |? {
                        ( $_ | Test-BagItFormattedDirectory )
                    } |? {
                        -Not ( $_ | Test-BagItFormattedDirectoryContent )
                    }
                }
                Else { 
                    Get-ChildItem -LiteralPath:$_.Parent.FullName -File -Force
                }

            } | Get-ItemPackage -At -Force
        }

        If ( -Not ( $NoLeafContainers ) ) {

            Get-ChildItem -LiteralPath:$Container.FullName -Directory -Recurse -Force |? { ( $_.FullName -notlike '*\.*\*' ) } |? { $_.Name -notin @( $Exclude ) } |? {
                $_.FullName -notlike '*\data\*'
            } |? { 
                $_.Name -ne '.bagged'
            } |? {
                -Not ( $_ | Test-BagItFormattedDirectoryContent )
            } |? {
                $aFiles = ( Get-ChildItem -LiteralPath:$_.FullName -File -Force |? { $_.Name -ne 'Thumbs.db' } | Select-Object -First:1 )
                $aDirs = ( Get-ChildItem -LiteralPath:$_.FullName -Directory -Force | Select-Object -First:1 )
                ( ( ( $aFiles | Measure-Object ).Count -gt 0 ) -and ( ( $aDirs | Measure-Object ).Count -eq 0 ) ) | Write-Output
            }

        }

    }

}

End {
    Exit $ExitCode
}

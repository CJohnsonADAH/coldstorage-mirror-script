Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    [switch] $Resolve=$false,
    $Algorithm='*'
)

Begin {
    $ExitCode = 0

    $global:gChecksumSidecarCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gChecksumSidecarCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )

}

Process {

    $o = ( $Item | Get-FileObject )
    If ( $o ) {

        If ( Test-Path -LiteralPath:$o.FullName -PathType:Leaf ) {
            
            $Name = $o.Name

            $Parent = ( $o | Get-ItemFileSystemParent )
            $ContainerNames = ( Get-BaggedCopyContainerSubdirectories )
            
            $Containers = ( $ContainerNames |% { $Parent.FullName | Join-Path -ChildPath $_ } )
            [Array]::Reverse( $Containers )
            
            $Containers |% {
                $CandidateContainer = $_
                $CandidateName = ( "{0}.{1}" -f ( $Name -replace '[\[\]]','_' ), $Algorithm )
                $Candidate = ( $CandidateContainer | Join-Path -ChildPath $CandidateName )

                "[{0}] SIDECAR CANDIDATE: {1}" -f ( Get-CSDebugContext -Function:$MyInvocation ), $Candidate | Write-Verbose

                If ( $Resolve ) {
                    If ( Test-Path -LiteralPath:$CandidateContainer -PathType:Container ) {
                        Push-Location -LiteralPath:$CandidateContainer
                        If ( Test-Path -Path:$CandidateName -PathType:Leaf ) {
                            Get-Item -Path:$CandidateName -Force |? {
                                ( $Algorithm -eq 'tag' ) -or ( $_.Name -notlike '*.tag' )
                            } |? {
                                ( $_.Name -notlike '*.json' )
                            } |% { $_.FullName } | Write-Output
                        }
                        Pop-Location
                    }
                }
                Else {
                    $Candidate
                }

            }

        }
        Else {
            "[{0}] Test-Path -LiteralPath:'{1}' -PathType:Leaf failed; I don't know what to do!" -f ( Get-CSDebugContext -Function:$MyInvocation ), $o.FullName | Write-Error
        }

    }
    Else {

            "[{0}] {1} | Get-FileObject failed; I don't know what to do!" -f ( Get-CSDebugContext -Function:$MyInvocation ), $Item | Write-Error

    }

}

End {
    Exit $ExitCode
}

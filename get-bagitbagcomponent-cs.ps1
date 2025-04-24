Param(
    [switch] $Payload=$false,
    [switch] $Manifests=$false,
    [switch] $Force=$false,
    $Subdirectory=$null,
    $Manifest=$null,
    [Parameter(ValueFromPipeline=$true)] $Directory
)

Begin {
    Function Get-FileObject {

        [CmdletBinding()]

    Param( [Parameter(ValueFromPipeline=$true)] $File )

        Begin { }

        Process {
            $oFile = $null
            If ( ( $File -is [String] ) -and ( $File.length -gt 0 ) ) {

                If ( Test-Path -LiteralPath "${File}" ) {
                    $oFile = ( Get-Item -Force -LiteralPath "${File}" )
                }

            }
            Else {
                $oFile = $File
            }

            $oFile
        }

        End { }

    }

    Function Get-BagManifestContainer {
    Param( [Parameter(ValueFromPipeline=$true)] $Bag )

        Begin { }

        Process {
            If ( $Bag -ne $null ) {
                $dataSubdirPath = ( $Bag.FullName | Join-Path -ChildPath "data" )
                $bagSubdirPath = ( $Bag.FullName | Join-Path -ChildPath ".bag" )

                If ( Test-Path -LiteralPath $bagSubdirPath ) {
                    $ManifestsDir = ( $bagSubdirPath | Get-FileObject )
                }
                Else {
                    $ManifestsDir = ( $Dir )
                    If ( Test-Path -LiteralPath $dataSubdirPath -PathType Container ) {
                        $ManifestsDir | Add-Member -MemberType NoteProperty -Name BagItComponentExcludes -Value ( $dataSubdirPath | Get-FileObject ) -Force
                    }
                }

                If ( $ManifestsDir -ne $null ) {
                    $ManifestsDir
                }
            }
        }

        End { }

    }

    $ExitCode = 0
}

Process {
    If ( $Directory -ne $null ) {

        $Dir = ( $Directory | Get-FileObject )

        $dataSubdirPath = ( $Dir.FullName | Join-Path -ChildPath "data" )
        $bagSubdirPath = ( $Dir.FullName | Join-Path -ChildPath ".bag" )

        $bagItTxt = ( $Dir.FullName | Join-Path -ChildPath "bagit.txt" )
        If ( -Not ( Test-PAth -LiteralPath $bagItTxt ) ) {
            $bagItTxt = ( $bagSubdirPath | Join-Path -ChildPath "bagit.txt" )
        }

        If ( Test-Path -LiteralPath $bagItTxt ) {
            "identified as likely a bagit-formatted directory" | Write-Debug
        }
        Else {
            "bagit.txt not found, this is unlikely to be a BagIt-formatted directory" | Write-Warning
        }

        If ( $Payload ) {

            $PayloadDir = $null
            If ( Test-Path -LiteralPath $dataSubdirPath -PathType Container ) {
                $PayloadDir = ( $dataSubdirPath | Get-FileObject )
            }
            ElseIf ( Test-Path -LiteralPath $bagSubdirPath -PathType Container ) {
                $PayloadDir = ( $Dir )
                $PayloadDir | Add-Member -MemberType NoteProperty -Name BagItComponentSingleDot -Value ( "data" ) -Force
                $PayloadDir | Add-Member -MemberType NoteProperty -Name BagItComponentExcludes -Value ( $bagSubdirPath | Get-FileObject ) -Force
            }

            If ( $PayloadDir -ne $null ) {
                $PayloadDir
            }
            Else {
                $ExitCode = 1
            }

        }

        $ManifestsDir = ( $Dir | Get-BagManifestContainer )
        If ( $Manifests ) {
            If ( $ManifestsDir -ne $null ) {
                $ManifestsDir
            }
            Else {
                $ExitCode = 1
            }

        }

        If ( $Subdirectory -ne $null ) {
            If ( $ManifestsDir -ne $null ) {
                $o = ( Get-ChildItem -LiteralPath $ManifestsDir.FullName -Directory |? { $_.Name -like $Subdirectory } )
                If ( $o ) {
                    $o
                }
                ElseIf ( $Force ) {
                    $o = ( New-Item -ItemType Directory -Path ( Join-Path $ManifestsDir.FullName -ChildPath $Subdirectory ) )
                    $o
                }
            }
            Else {
                $ExitCode = 2
            }
        }
        If ( $Manifest -ne $null ) {
            If ( $ManifestsDir -ne $null ) {
                Get-ChildItem -LiteralPath $ManifestsDir.FullName -File |? { $_.Name -like ( 'manifest-{0}.txt' -f $Manifest ) }
            }
            Else {
                $ExitCode = 2
            }
        }


    }

}

End {
    Exit $ExitCode
}

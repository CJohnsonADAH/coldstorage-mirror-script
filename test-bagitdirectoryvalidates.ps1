Param(
    [Parameter(ValueFromPipeline=$true)] $Bag,
    [switch] $PassThru=$false,
    [Parameter(ValueFromRemainingArguments=$true)] $Items
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

    Function Get-BagItInfoTable {
    Param( [Parameter(ValueFromPipeline=$true)] $Bag )

        Begin {
            $bagInfoFileName = "bag-info.txt"
        }
        
        Process {
            $bagInfoFile = ( Join-Path -Path:( $Bag.FullName ) -ChildPath:$bagInfoFileName )
            "INFO: {0}" -f $bagInfoFile | Write-Debug
            $o = @{ }
            Get-Content $bagInfoFile |% {
                $Key, $Value = ( "$_" -split "[:]\s*",2 )
                $o[ $Key ] = $Value
            }
            $o
        }

        End {
        }

    }

    Function Get-BagItInfo {
    Param( [Parameter(ValueFromPipeline=$true)] $Bag, $Name )
        Begin { }

        Process {
            $o = ( $Bag | Get-BagItInfoTable )
            $o.Keys |% { "{0}={1}" -f $_, $o[ $_ ] } | Write-Debug
            If ( $o.ContainsKey( $Name ) ) {
                $o[ $Name ]
            }
            Else {
                $Name | Write-Warning
            }

        }

        End { }
    }

    Function Tee-BagItManifestValidationMessage {
    Param( [Parameter(ValueFromPipeline=$true)] $Message )

        Begin { }

        Process {
            ( "{0} - INFO - Validating manifest in file {1}" -f ( Get-Date -Format "yyyy-MM-dd HH:mm:ss" ), $Message ) | Write-Verbose
            $Message
        }

        End { }
    }

    Function Test-BagItDirectoryValidates {
    Param( [Parameter(ValueFromPipeline=$true)] $Bag )
        
        Begin {
            $Required = @{
                "Leaf"=@( "bagit.txt", "bag-info.txt" );
                "Container"=@( "data" )
            }
            
        }

        Process {
            
            $Unsullied = $true

            # Is this a directory?
            If ( -Not ( Test-Path -LiteralPath:( $Bag.FullName ) -PathType:Container ) ) {
                "NOT A DIRECTORY DUMMY" | Write-Error
                $Unsullied = $false
            }

            If ( $Unsullied ) {

                $Required.Keys |% {
                    $RequiredItems = $Required[ $_ ]
                    $RequiredType = $_
                    
                    $RequiredItems |% {
                        If ( $Unsullied ) {
                            $req = ( Join-Path -Path:( $Bag.FullName ) -ChildPath:$_ )
                            "{0}: {1}" -f $RequiredType,$req | Write-Debug
                            If ( -Not ( Test-Path -LiteralPath:$req -PathType:$RequiredType ) ) {
                                "COULD NOT FIND {0} {1} !!" -f $RequiredType,$req | Write-Error
                                $Unsullied = $false
                            }
                        }
                    }
                }
            }

            If ( $Unsullied ) {
                "Bag: {0}" -f $Bag.FullName | Write-Debug

                $Payload = ( Join-Path $Bag.FullName -ChildPath:"data" )
                $Oxum = ( $Bag | Get-BagItInfo -Name:"Payload-Oxum" )
                
                If ( $Oxum ) {
                    "Oxum: {0}" -f $Oxum | Write-Debug
                    "Payload: {0}" -f $Payload | Write-Debug
                }

                Push-Location $Bag.FullName
                $TagManifests = ( Get-ChildItem -File -Path:"tagmanifest-*.txt" )
                If ( $TagManifests.Count -gt 0 ) {
                    $Unsullied = ( $Unsullied -and ( $TagManifests | Tee-BagItManifestValidationMessage | test-bagitmanifestvalidates.ps1 ) )
                }

                If ( $Unsullied ) {
                    $Manifests = ( Get-ChildItem -File -Path:"manifest-*.txt" )
                    If ( $Manifests.Count -gt 0 ) {
                        $Unsullied = ( $Unsullied -and ( $Manifests | Tee-BagItManifestValidationMessage | test-bagitmanifestvalidates.ps1 -Payload:$Payload -PayloadOxum:$Oxum ) )
                    }
                }

                Pop-Location

                $Unsullied | Write-Output

            }

        }

        End { }
    }

    $ExitCode = 0
    $Unsullied = $true

}

Process {
    If ( $Bag -ne $null ) {
        $Bag | Get-FileObject |% {
        
            "Test-BagItDirectoryValidates: {0}" -f $_.FullName | Write-Debug

            $Validated = ( $_ | Test-BagItDirectoryValidates )
            $Unsullied = ( $Unsullied -and $Validated )

            If ( $PassThru ) {
                If ( $Validated ) {
                    $_ | Write-Output
                }
            }
            Else {
                $Validated | Write-Output
            }

            If ( -Not $Validated ) {
                If ( $ExitCode -eq 0 ) {
                    $ExitCode = 1
                }
            }

        }
    }
}

End {
    If ( $Items.Count -gt 0 ) {

        $Items | Get-FileObject |% {

            "Test-BagItDirectoryValidates: {0}" -f $_.FullName | Write-Debug            
            $Validated = ( $_ | Test-BagItDirectoryValidates )
            $Unsullied = ( $Unsullied -and $Validated )

            If ( $PassThru ) {
                If ( $Validated ) {
                    $_ | Write-Output
                }
            }
            Else {
                $Validated | Write-Output
            }

            If ( -Not $Validated ) {
                If ( $ExitCode -eq 0 ) {
                    $ExitCode = 1
                }
            }

        }

    }

    Exit $ExitCode
}


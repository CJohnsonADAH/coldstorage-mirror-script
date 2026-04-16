Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    $Algorithms=@( "sha256", "sha512" ),
    [switch] $Quiet=$false,
    [switch] $PassThru=$false
)

Begin {
    $ExitCode = 0

    $global:gAddBagItContainerHardlinkCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gAddBagItContainerHardlinkCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )

    Function Get-ChecksumSidecarAlgorithmsFromFileNames {
    Param( [Parameter(ValueFromPipeline=$true)] $Sidecar, $File, [switch] $Hashtable=$false )

        Begin {
            If ( $Hashtable ) {
                $Output = @{ }
            }
        }

        Process {
            $o = ( $Sidecar | Get-FileObject )

            $FileName = ( $File.Name -replace '[\[\]]','_' )
            $reFileName = ( '^({0})' -f [Regex]::Escape( $File.Name ) )

            $Suffix = ( $o.Name -replace $reFileName,'' )
            $Algorithm = ( $Suffix -split '[.]' |? { $_.Length -gt 0 } | Select-Object -Last:1 )
            
            If ( $Hashtable ) {
                If ( -Not $Output.ContainsKey( $Algorithm ) ) {
                    $Output[ $Algorithm ] = @( )
                }
                $Output[ $Algorithm ] = @( $Output[ $Algorithm ] ) + @( $o )
            }
            Else {
                $Algorithm | Write-Output
            }

        }

        End {
            If ( $Hashtable ) {

                $Output | Write-Output

            }
        }
    }

    Function Format-TextFileWithoutBOM {
    Param( [Parameter(ValueFromPipeline=$true)] $File )

        Begin { }

        Process {

            $Reader = $File.OpenRead()
            $byteBuffer = ( New-Object System.Byte[] 3 )
            $BOMsignature = @( [byte] 239, [byte] 187, [byte] 191 )
            $bytesRead = $Reader.Read( $byteBuffer, 0, 3 )

            $eqResult = ( $byteBuffer -eq $BOMSignature )
            $diff = ( Compare-Object -ReferenceObject:$BOMsignature -DifferenceObject:$byteBuffer -SyncWindow:0 )
            If ( ( $bytesRead -eq $BOMsignature.Count ) -and ( -not ( $diff -as [bool] ) ) ) {

                $FullName = $File.FullName
                $tempFile = [System.IO.Path]::GetTempFileName()

                $Writer = [System.IO.File]::OpenWrite($tempFile)
                $Reader.CopyTo($Writer)
                $Writer.Dispose()
                $Reader.Dispose()

                Move-Item -Path $tempFile -Destination $FullName -Force

            }
            Else {
                $Reader.Dispose()
            }
    
        }

        End { }

    }

    Function ConvertFrom-ItemPackageMetadata {
    Param( [Parameter(ValueFromPipeline=$true)] $Item )

        Begin { }

        Process {
            $Output = @{ }

            $meta = ( $Item | Get-ItemPackageMetadataFile )
            If ( $meta ) {

                    $BagContainer = $null
                    $Checksums = @{ }

                    $BagContainer = ( $Item | Get-ItemPackageMetadata -Name:"Bag-Directory" )
                    $Checksums = ( $Item | Get-ItemPackageMetadata -Name:"Bag-TagManifests" )

                    $Output[ "BagContainer" ] = $BagContainer
                    $Output[ "Checksums" ] = $Checksums
                    
                    $Output | Write-Output

            }
            Else {

                "[{0}] Package '{1}' has no Item Package Metadata File ({2})" -f ( Get-CSDebugContext -Function:$MyInvocation ), ( $Item | Get-FileLiteralPath ), ( $Item | Get-ItemPackageMetadataFilePath ) | Write-Verbose

            }
        }

        End { }

    }

    Function ConvertFrom-TagFileText {
    Param( [Parameter(ValueFromPipeline=$true)] $Item )

        Begin { }

        Process {
            $Output = @{ }

            $BagContainer = $null
            $Checksums = @{ }

            $o = ( $Item | Get-FileObject )
            $Text = ( Get-Content -LiteralPath:$o.FullName )
            $Text |% {
                If ( $_ -match '^[#]\s*(\S.*\S)' ) {
                    $BagContainer = $Matches[1]
                }
                Else {
                    $Algorithm, $Hash, $FileName = ( $_ -split '\s+',3 )
                    
                    If ( -Not $Checksums.ContainsKey( $FileName ) ) {
                        $Checksums[ $FileName ] = @{ }
                    }
                    If ( -Not $Checksums[ $FileName ].ContainsKey( $Algorithm ) ) {
                        $Checksums[ $FileName ][ $Algorithm ] = @( )
                    }
                    $Checksums[ $FileName ][ $Algorithm ] += @( $Hash )
                }
            }

            $Output[ "BagContainer" ] = $BagContainer
            $Output[ "Checksums" ] = $Checksums
            
            $Output | Write-Output
        }

        End { }
    }

}

Process {
    $Sidecars = ( $Item | get-checksumsidecar-cs.ps1 -Algorithm:"*" -Resolve )
    If ( $Sidecars.Count -gt 0 ) {

        # Check whether a tag file is available
        $Tag = @{ }
        $TagCar = ( $Item | Get-ItemPackageMetadataFile )
        If ( $TagCar.Count -gt 0 ) {
            $Tag = ( $Item | ConvertFrom-ItemPackageMetadata )
        }
        Else {
            # If a tag file is not available, try to create a tagfile
            $Item | add-checksumsidecartag-cs.ps1

            $TagCar = ( $Item | Get-ItemPackageMetadataFile )
            If ( $TagCar.Count -gt 0 ) {
                $Tag = ( $Item | ConvertFrom-ItemPackageMetadata )
            }

        }

        $LastWriteTime = ( $Sidecars | Get-FileObject |% { $_.LastWriteTime } | Sort-Object -Descending | Select-Object -First:1 )
        $Container = ( $Sidecars | Select-Object -First:1 |% { ( Get-Item -LiteralPath:$_ -Force ).Directory } )

        If ( -Not ( $Tag.ContainsKey( 'BagContainer' ) ) ) {
            $FileName = ( $Item | Get-PathToBaggedCopyOfLooseFile -Timestamp:$LastWriteTime )
        }
        Else {
            $FileName = ( $Tag[ 'BagContainer' ] )
        }

        $BagContainerPath = ( $Container.FullName | Join-Path -ChildPath:$FileName )
        If ( -Not ( Test-Path -LiteralPath:$BagContainerPath ) ) {
            $BagContainer = ( New-Item -ItemType:Directory -Path:$BagContainerPath )
        }
        Else {
            $BagContainer = ( Get-Item -LiteralPath:$BagContainerPath -Force )
        }

        Push-Location -LiteralPath:$BagContainer.FullName
        
        If ( -Not ( Test-Path -LiteralPath:"data" ) ) {
            $Payload = ( New-Item -ItemType:Directory -Path:"data" )
        }
        Else {
            $Payload = ( Get-Item -LiteralPath:"data" -Force )
        }
        
        # Create required bagit.txt and bag-info.txt elements
        $BagInfoFiles = [ordered] @{
            "bagit.txt"=@{
                "Path"=( $BagContainer.FullName | Join-Path -ChildPath:( "bagit.txt" ) )
                "Data"=[ordered] @{
                    "BagIt-Version"="0.97"
                    "Tag-File-Character-Encoding"="UTF-8"
                }
            }
            "bag-info.txt"=@{
                "Path"=( $BagContainer.FullName | Join-Path -ChildPath:( "bag-info.txt" ) )
                "Data"=[ordered] @{
                    "Bag-Software-Agent"=( "{0} v. 2026.0326" -f $global:gAddBagItContainerHardlinkCmd.Name )
                    "Bagging-Date"=( Get-Date -Format:"yyyy-MM-dd" )
                    "Payload-0xum"=( "{0}.{1}" -f $Item.Length, 1 )
                }
            }
        }
        $BagInfoFiles.Keys |% {
            $InfoFile = $BagInfoFiles[ $_ ]
            If ( -Not ( Test-Path -LiteralPath:( $InfoFile[ 'Path' ] ) ) ) {
                $BagInfoItem = ( New-Item -ItemType:File -Path:$InfoFile[ "Path" ] )
            }
            Else {
                $BagInfoItem = ( Get-Item -LiteralPath:$InfoFile[ "Path" ] -Force )
                Clear-Content -LiteralPath:$BagInfoItem
            }

            $InfoFile[ "Data" ].Keys |% {
                $Key, $Value = $_, $InfoFile[ "Data" ][ $_ ]
                ( "{0}: {1}" -f $Key, $Value ) | Out-File -Encoding:utf8 -LiteralPath:$BagInfoItem.FullName -Append
            }
            Get-Item -LiteralPath:$BagInfoItem.FullName -Force | Format-TextFileWithoutBOM
        }

        # Generate the tagmanifest files, if data is available
        $TagManifests = @{ }

        If ( $Tag.ContainsKey( 'Checksums' ) ) {
            
            # This will be pulled from JSON metadata, and so needs to be converted from object to hashtable
            $Tag[ 'Checksums' ] | Get-Member -MemberType:NoteProperty |% {
                
                $Prop1 = ( $_.Name )
                $TaggedFileName = $Prop1
                $TaggedFile = ( $Tag[ 'Checksums' ].$Prop1 )
                
                $TaggedFile | Get-Member -MemberType:NoteProperty |% {
                    
                    $Prop2 = $_.Name
                    $TaggedAlgorithm = $Prop2
                    $TaggedChecksums = $TaggedFile.$Prop2

                    If ( -Not ( $TagManifests.ContainsKey( $TaggedAlgorithm ) ) ) {
                        $TagManifests[ $TaggedAlgorithm ] = @( )
                    }
                    $TagManifests[ $TaggedAlgorithm ] += @( @{ "File"=( 'sidecar::{0}' -f $TaggedFileName ) ; "Hash"=$TaggedChecksums } )

                }

            }

        }

        $TagAlgorithms = @() + @( $TagManifests.Keys )
        $TagAlgorithms |% {
            $TaggedAlgorithm = $_
            $BagInfoFiles.Keys |% {
                $InfoFile = $BagInfoFiles[ $_ ]
                $InfoItem = ( Get-Item -LiteralPath:$InfoFile[ 'Path' ] -Force )
                $InfoFileHash = ( Get-FileHash -LiteralPath:$InfoItem.FullName -Algorithm:$TaggedAlgorithm )
                $TagManifests[ $TaggedAlgorithm ] += @( @{ "File"=$InfoItem.Name ; "Hash"=$InfoFileHash.Hash.ToLower() } )
            }
        }
        $TagManifests.Keys | % {
            $TagManifestFileName = ( 'tagmanifest-{0}.txt' -f $_ )
            $TagManifestFile = ( $BagContainer | Join-Path -ChildPath $TagManifestFileName )
            If ( -Not ( Test-Path -LiteralPath:( $TagManifestFile ) ) ) {
                $BagInfoItem = ( New-Item -ItemType:File -Path:$TagManifestFileName )
            }
            Else {
                $BagInfoItem = ( Get-Item -LiteralPath:$TagManifestFile -Force )
                Clear-Content -LiteralPath:$TagManifestFile
            }

            $TagManifests[ $_ ] |% {
                $Line = $_
                If ( $Line[ 'File' ] -match '^sidecar::(.*)' ) {
                    $SidecarFilePath = ( $Container.FullName | Join-Path -ChildPath $Matches[1] )
                    $SidecarFileAlgorithm = ( $SidecarFilePath | Get-ChecksumSidecarAlgorithmsFromFileNames -File:$Item )
                    $TaggedFileName = ( 'manifest-{0}.txt' -f $SidecarFileAlgorithm )
                }
                Else {
                    $TaggedFileName = $Line[ 'File' ]
                }
                
                "{0}  {1}" -f ( $Line[ 'Hash' ] -join "|" ), $TaggedFileName | Out-File -Encoding:utf8 -LiteralPath:$TagManifestFile -Append
            }
        }

        # Copy the sidecar files over to be manifest files

        $AlgoTable = ( $Sidecars | Get-ChecksumSidecarAlgorithmsFromFileNames -File:$Item -Hashtable )
        $AlgoTable.Keys |% {
            $Algorithm = $_
            $AlgoTable[ $Algorithm ] |% {
                $SidecarPath = $_
                $ManifestPath = ( $BagContainer.FullName | Join-Path -ChildPath:( "manifest-{0}.txt" -f $Algorithm ) )
                
                If ( -Not ( Test-Path -LiteralPath:( $ManifestPath ) ) ) {
                    New-Item -ItemType:HardLink -Path:$ManifestPath -Target:$SidecarPath |% { "[{0}] Bagging {1}, created link to {2} manifest: {3}" -f ( Get-CSDebugContext -Function:$MyInvocation ), $Item.FullName, $Algorithm, $ManifestPath | Write-Verbose }
                }
                Else {
                    Get-Item -LiteralPath:$ManifestPath -Force |% { "[{0}] Bagging {1}, found existing link to {2} manifest: {3}" -f ( Get-CSDebugContext -Function:$MyInvocation ), $Item.FullName, $Algorithm, $ManifestPath | Write-Verbose }
                }
            }
        }

        # Copy the package JSON metadata over into the bag container
        
        $MetaFile = ( $Item | Get-ItemPackageMetadataFile )
        If ( $MetaFile ) {
            
            $PackageJson = ( $BagContainer.FullName | Join-Path -ChildPath:"package.json" )
            If ( -Not ( Test-Path -LiteralPath:$PackageJson ) ) {
                New-Item -ItemType:HardLink -Path:$PackageJson -Target:$MetaFile.FullName |% { "[{0}] Bagged {1}, created link to metadata: {2}" -f ( Get-CSDebugContext -Function:$MyInvocation ), $Item.FullName, $_.FullName | Write-Verbose }
            }
            Else {
                Get-Item -LiteralPath:$PackageJson -Force |% { "[{0}] Bagged {1}, found existing link to metadata: {2}" -f ( Get-CSDebugContext -Function:$MyInvocation ), $Item.FullName, $_.FullName | Write-Verbose }
            }

        }

        # Create the payload directory, containing only this file
        $HardLinkPath = ( $Payload.FullName | Join-Path -ChildPath:$Item.Name )
        If ( -Not ( Test-Path -LiteralPath:( $HardLinkPath ) ) ) {
            New-Item -ItemType:HardLink -Path:$HardLinkPath -Target:( [WildcardPattern]::Escape( $Item.FullName ) ) |% { "[{0}] Bagged {1}, created link to payload: {2}" -f ( Get-CSDebugContext -Function:$MyInvocation ), $_.FullName, $Item.FullName | Write-Verbose }
        }
        Else {
            Get-Item -LiteralPath:$HardLinkPath -Force |% { "[{0}] Bagged {1}, found existing link to payload: {2}" -f ( Get-CSDebugContext -Function:$MyInvocation ), $_.FullName, $Item.FullName | Write-Verbose }
        }

        #Get-Item $BagContainer.FullName | out-bagitformatteddirectory-cs.ps1 -PassThru:$PassThru ; $bagExit = $LASTEXITCODE
        Pop-Location

        If ( $bagExit -gt 0 ) {
            "[{0}] out-bagitformatteddirectory-cs.ps1 exited with error code {1:N0}" -f ( Get-CSDebugContext -Function:$MyInvocation ), $bagExit | Write-Error
            $ExitCode = $bagExit
        }
        ElseIf ( $PassThru ) {
            $BagContainer | Write-Output
        }
        ElseIf ( -Not $Quiet ) {
            "OK-BagIt: {0} (hardlink)" -f $HardLinkPath | Write-Output
        }

    }
    Else {
        "[{0}] Could not find checksum sidecars for {1}!" -f ( Get-CSDebugContext -Function:$MyInvocation ), $Item.FullName | Write-Warning
        $ExitCode = 1
    }
}

End {
    Exit $ExitCode
}

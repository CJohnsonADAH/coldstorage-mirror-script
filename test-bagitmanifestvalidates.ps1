Param(
    $Algorithm=$null,
    $Payload=$null,
    $PayloadOxum=$null,
    [switch] $PassThru=$false
)

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

Function Get-BIFileChecksumItem {
Param( [Parameter(ValueFromPipeline=$true)] $Item )

    Begin { }

    Process {
        If ( $Item -is [hashtable] ) {
            "HASH!!!" | Write-Warning

            $oItem = ( Get-Item -LiteralPath:( $Item[ 'File' ] ) -Force -ErrorAction:SilentlyContinue )
            $oItem | Add-Member -MemberType NoteProperty -Name Hash -Value:( $Item[ 'Checksum' ] ) -Force
        }
        ElseIf ( $Item | Get-Member -Name:Hash ) {

            If ( $Item | Get-Member -Name:FullName ) {

                $oItem = $Item

            }
            ElseIf ( $Item | Get-Member -Name:Path ) {

                $oItem = ( Get-Item -LiteralPath:( $Item.Path ) -Force -ErrorAction:SilentlyContinue )
                $oItem | Add-Member -MemberType NoteProperty -Name Hash -Value:( $Item.Hash ) -Force

            }


        }

        If ( $oItem ) {
            $oItem.FullName
            [PSCustomObject] @{
                "Algorithm"=$oItem.Algorithm;
                "Hash"=$oItem.Hash.ToUpper();
                "Path"=$oItem.FullName;
                "Timestamp"=$oItem.Timestamp
            }
        }

    }

    End {
    }

}

Function Get-BIFileChecksumsForValidation {
Param( [Parameter(ValueFromPipeline=$true)] $Item, $Algorithm='MD5' )

    Begin { }

    Process {

        $FilePath, $Checksum = ( Get-BIFileChecksumItem $Item )
        $oItem = ( Get-Item -LiteralPath:$FilePath -Force )
        $oItem | Add-BIFileChecksum -Algorithm:$Checksum.Algorithm -Recorded:$Checksum
        $oItem | Add-BIFileChecksum -Algorithm:$Checksum.Algorithm # -Compute

        $oItem

    }

    End { }

}

Function Test-BIFileChecksumValidates {
Param( [Parameter(ValueFromPipeline=$true)] $Item, $Algorithm='MD5', [switch] $PassThru=$false )

    Begin { }

    Process {

        $Validating = ( $Item | Get-BIFileChecksumsForValidation -Algorithm:$Algorithm )

        $Validates = $null

        $Validating.BagItChecksums.Keys |% {
            If ( $Validates -eq $null ) {
                $Validates = $true
            }

            $Sums = ( $Validating.BagItChecksums[ $_ ] )
            
            If ( $Sums -isnot [System.Array] ) {
                $Sums = @( $Sums )
            }

            "{0} CHECKSUMS: {1}" -f $_, ( ( $Sums |% { $_.Hash } ) -join "; " ) | Write-Debug
            
            $Base = ( $Sums | Select-Object -First 1 )
            $Sums |% {
                $Validates = ( $Validates -and ( $_.Hash -ieq $Base.Hash ) )
            }

        }

        If ( $PassThru ) {
            $Validating | Add-Member -MemberType NoteProperty -Name "Validated" -Value $Validates -PassThru
        }
        Else {
            $Validates
        }

    }

    End {
    }

}

Function Add-BIFileChecksum {
Param( [Parameter(ValueFromPipeline=$true)] $Item, [switch] $PassThru=$false, $Recorded=$null, $Algorithm='MD5' )

    Begin { }

    Process {

        $MemberName = "BagItChecksums"
        $Checksums = @{ }
        If ( $Item | Get-Member -Name $MemberName ) {
            $Checksums = $Item.BagItChecksums
        }
        If ( -Not $Checksums.ContainsKey( $Algorithm ) ) {
            $Checksums[ $Algorithm ] = @( )
        }

        If ( $Recorded -ne $null ) {
                $ComputedSum = $Recorded
                $ComputedSum | Add-Member -MemberType NoteProperty -Name "TimestampAdded" -Value ( Get-Date )
        }
        Else {

            $ComputedSum = ( Get-FileHash -LiteralPath:( $Item.FullName ) -Algorithm:$Algorithm )
            If ( $ComputedSum ) {
                $ComputedSum | Add-Member -MemberType NoteProperty -Name "Timestamp" -Value ( Get-Date )
            }
        }
        
        If ( $ComputedSum ) {
        
            If ( $Checksums[ $Algorithm ] -isnot [System.Array] ) {
                $Checksums[ $Algorithm ] = @( $Checksums[ $Algorithm ] ) + @( $ComputedSum )
            }
            ElseIf ( $Checksums[ $Algorithm ].Count -eq 0 ) {
                $Checksums[ $Algorithm ] = $ComputedSum
            }
            Else {
                $Checksums[ $Algorithm ] += @( $ComputedSum )
            }

        }

        $Item | Add-Member -MemberType NoteProperty -Name $MemberName -Value $Checksums -Force
        If ( $PassThru ) {
            $Item
        }

    }

    End { }

}

Function Get-BIManifestLineItem {
Param( [Parameter(ValueFromPipeline=$true)] $Line, $Algorithm="MD5", $Context='.' )


    Begin {
        
        If ( Test-Path -LiteralPath:$Context -PathType Container ) {
            $Container = ( Get-Item -LiteralPath:$Context -Force )
        }
        Else {
            Write-Error -Message "CONTAINER PATH DOES NOT EXIST"
        }

    }

    Process {
        $Checksum, $RelPath = ( $Line -split '\s+',2 )
        
        $aRelPath = ( $RelPath -split '/' )
        $absPath = $Container.FullName ; $aRelPath |% { $absPath = ( Join-Path -Path:$absPath -ChildPath:$_  ) }

        $Item = ( Get-Item -LiteralPath:$absPath -Force )
        $Item | Add-Member -MemberType NoteProperty -NAme Algorithm -Value $Algorithm -Force
        $Item | Add-Member -MemberType NoteProperty -Name Hash -Value $Checksum -Force
        $Item | Add-Member -MemberType NoteProperty -Name Timestamp -Value ( $Item.LastWriteTime ) -Force

        $Item

    }

    End {
    }

}

Function Test-BIManifestLineValidates {
Param( [Parameter(ValueFromPipeline=$true)] $Line, $Context='.', $Algorithm='MD5', [switch] $PassThru=$false )

    Begin {
        
        If ( Test-Path -LiteralPath:$Context -PathType Container ) {
            $Container = ( Get-Item -LiteralPath:$Context -Force )
        }
        Else {
            Write-Error -Message "CONTAINER PATH DOES NOT EXIST"
        }

    }

    Process {
        
        $Line | Get-BIManifestLineItem -Algorithm:$Algorithm | Tee-BagItValidationMessage | Test-BIFileChecksumValidates -Algorithm:$Algorithm -PassThru:$PassThru

    }

    End {
    }

}

Function Test-BIManifestFileValidates {
Param( [Parameter(ValueFromPipeline=$true)] $File, $Payload=$null, $PayloadOxum=$null, $Algorithm=$null, [switch] $PassThru )

    Begin { 
        $Perfect = $true
    }

    Process {
        $oFile = Get-FileObject( $File )
        If ( $oFile ) {
            $sAlgorithm = $Algorithm
            If ( $sAlgorithm -eq $null ) {
                If ( $oFile.Name -imatch '^(.*)manifest-([A-Z0-9]+)[.]txt' ) {
                    $sAlgorithm = $Matches[2]
                }
            }

            $sParent = $oFile.Directory.FullName
            ( "MANIFEST FILE: {0} ALGORITHM: {1} CONTEXT: {2}" -f $oFile.FullName,$sAlgorithm,$sParent ) | Write-Debug
            
            If ( $Payload ) {

                $oPayloadContainer = Get-FileObject( $Payload )
                $aoPayload = ( Get-ChildItem -LiteralPath:( $oPayloadContainer.FullName ) -Force -File -Recurse )
                $I = ( Get-Content -LiteralPath:( $oFile.FullName ) | Measure-Object ).Count
                $N = ( $aoPayload | Measure-Object ).Count
                $nSize = ( $aoPayload | Measure-Object -Sum -Property Length ).Sum

                $OxumBytes, $OxumFiles = ( $PayloadOxum -split "[.]", 2 )
                $nOxumBytes = [Int64]::Parse( $OxumBytes )
                $nOxumFiles = [Int64]::Parse( $OxumFiles )

                $Perfect = ( $Perfect -and ( $I -eq $N ) )
                $Perfect = ( $Perfect -and ( $N -eq $nOxumFiles ) )
                $Perfect = ( $Perfect -and ( $nSize -eq $nOxumBytes ) )

                If ( -Not $Perfect ) {
                    "ITEMS: {0:N0} lines, {1:N0} files ({2:N0}B), {3:N0} ({4:N0}B)  expected" -f $I, $N, $nSize, $nOxumFiles, $nOxumBytes | Write-Error
                }

            }

            If ( $Perfect ) {

                # Perform the line-by-line checksum validation
                Get-Content -LiteralPath:( $oFile.FullName ) |% {
                    $Line = "$_"
                    Write-Progress -Activity "Validating" -Status:$Line

                    $OK = ( $Line | Test-BIManifestLineValidates -Context:$sParent -Algorithm:$sAlgorithm -PassThru:$PassThru )
                    If ( $PassThru ) {
                        $OK
                    }
                    Else {
                        $Perfect = ( $Perfect -and $OK )
                    }
                }

            }

        }
    }

    End {
        Write-Progress -Activity "Validating" -Completed
        If ( -Not $PassThru ) {
            $Perfect
        }
    }
}

Function Tee-BagItValidationMessage {
Param( [Parameter(ValueFromPipeline=$true)] $Message )

    Begin { }

    Process {
        ( "{0} - INFO - Verifying checksum for file {1}" -f ( Get-Date -Format "yyyy-MM-dd HH:mm:ss" ), $Message.FullName ) | Write-Verbose
        $Message
    }

    End { }
}

$Input | Test-BIManifestFileValidates -Algorithm:$Algorithm -Payload:$Payload -PayloadOxum:$PayloadOxum -PassThru:$PassThru


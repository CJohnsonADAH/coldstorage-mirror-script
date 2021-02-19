#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################

Function My-Script-Directory {
Param ( $Command, $File=$null )

    $Source = ( $Command.Source | Get-Item -Force )
    $Path = ( $Source.Directory | Get-Item -Force )

    If ( $File -ne $null ) {
        $Path = ($Path.FullName + "\" + $File)
    }

    $Path
}

Import-Module $( My-Script-Directory -Command $MyInvocation.MyCommand -File "ColdStorageSettings.psm1" )
Import-Module $( My-Script-Directory -Command $MyInvocation.MyCommand -File "ColdStorageRepositoryLocations.psm1" )

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Get-CloudStorageBucket {
Param( [Parameter(ValueFromPipeline=$true)] $Package, $Repository=@( ) )

Begin { }

Process {

    $oPackage = ( Get-FileObject -File $Package )
    $oRepository = ( Get-FileRepositoryProps -File $oPackage )
    If ( $oRepository ) {
        $sRepository = $oRepository.Repository
    }

    Switch ( $sRepository ) {
        'Processed' {
            $RepositorySlug = $sRepository.ToLower()
            "er-collections-${RepositorySlug}" | Write-Output
        }
        'Unprocessed' {
            $RepositorySlug = $sRepository.ToLower()
            "er-collections-${RepositorySlug}" | Write-Output
        }
        'Masters' {
            $RepositorySlug = $sRepository.ToLower()
            $ContainingDirectory = $( If ( $oPackage.Directory ) { $oPackage.Directory } ElseIf ( $oPackage.Parent ) { $oPackage.Parent } )

            If ( $ContainingDirectory | Test-ZippedBagsContainer ) {
                Push-Location ( $oRepository.Location.FullName )
                $Prefix = $oRepository.Prefix
                $RelativePath = ( $oPackage.Name -replace "^${Prefix}","" )
                Pop-Location
            }
            Else {
                Push-Location ( $oRepository.Location.FullName )
                $RelativePath = ( $ContainingDirectory.FullName | Resolve-Path -Relative )
                Pop-Location
            }

            $DirectorySlug = ( $RelativePath.ToLower() -replace "[^a-z0-9]+","-" )
            $DirectorySlug = ( $DirectorySlug -replace "(^-+|-+$)","" )

            "da-${RepositorySlug}-${DirectorySlug}" | Write-Output
        }
    }

}

End {

    $Repository |% {
        $Location = Get-ColdStorageZipLocation -Repository:$_
        If ( $Location ) {
            $Location | Get-CloudStorageBucket
        }
    }

}

}

Function Get-CloudStorageListing {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $Unmatched=$false, $Side=@("local","cloud"), [switch] $ReturnObject )

Begin { $bucketFiles = @{ }; }

Process {

    $oFile = Get-FileObject -File $File
    $sFile = $oFile.FullName
    $Bucket = ($sFile | Get-CloudStorageBucket)
    If ( $Bucket -eq $null ) {
        Write-Warning ( "Get-CloudStorageListing: could not determine bucket for {0}" -f $sFile )
    }
    Else{
    
        If ( $sFile ) {
            If ( Test-Path -LiteralPath $sFile -PathType Container ) {
                $Files = ( Get-ChildItem -LiteralPath $sFile -Filter "*.zip" )
            }
            Else {
                $Files = @( Get-FileObject -File $sFile )
            }
        }

        If ( -Not $bucketFiles.ContainsKey($Bucket) ) {
            $bucketFiles[$Bucket] = @( )
        }
        $bucketFiles[$Bucket] = $bucketFiles[$Bucket] + $Files
    }
}

End {
    $bucketFiles.Keys |% {
        $Bucket = $_
        $Files = $bucketFiles[$Bucket]

        If ( $Files.Count -gt 1 ) {
            Write-Debug ( "& {0} s3api list-objects-v2 --bucket '{1}'" -f $( Get-ExeForAWSCLI ),$Bucket )
            $jsonReply = $( & $( Get-ExeForAWSCLI ) s3api list-objects-v2 --bucket "${Bucket}" )
        }
        Else {
            $FileName = $Files.Name
            Write-Debug ( "& {0} s3api list-objects-v2 --bucket '{1}' --prefix '{2}'" -f $( Get-ExeForAWSCLI ),$Bucket,$FileName )
            $jsonReply = $( & $( Get-ExeForAWSCLI ) s3api list-objects-v2 --bucket "${Bucket}" --prefix "$FileName" )
        }
    }

    If ( -Not $Unmatched ) {
        $Side = @("local", "cloud")
    }

    Write-Debug ( "Side(s): {0}" -f ( $Side -join ", " ) )

    If ( $jsonReply ) {
        $oReply = ( $jsonReply | ConvertFrom-Json )

        If ( $oReply ) {

            If ( $oReply.Contents ) {

            $ObjectKeys = ( $oReply.Contents |% { $_.Key } )
            $ObjectObjects = ( $oReply.Contents |% { $sKey = $_.Key; @{ "${sKey}"=$_ } } )
            $sHeader = $null

            If ( $Side -ieq "local" ) {
                Write-Debug "[vs-cloud:${Bucket}] Local side"
                If ( $Unmatched -And ( $Side.Count -gt 1 ) ) {
                    $sHeader = "`r`n=== ADAHColdStorage ==="
                }
                $Files |% {
                    $Match = ( @( ) + @( $ObjectKeys ) ) -ieq $_.Name
                    If ( $Unmatched -xor ( $Match.Count -gt 0 ) ) {
                        If ( $ReturnObject ) {
                            $CloudCopy = ( $Match |% { $sKey = $_; $ObjectObjects.$sKey } )
                            $_ | Add-Member -MemberType NoteProperty -Name "CloudCopy" -Value $CloudCopy -Force -PassThru
                        }
                        Else {
                            If ( $sHeader ) { $sHeader; $sHeader = $null }
                            $_.Name
                        }
                    }
                }
            }

            $FileNames = ( $Files | Get-ItemPropertyValue -Name "Name" ) 
            If ( $Unmatched -and ( $Side -ieq "cloud" ) ) {
                Write-Debug "[vs-cloud:${Bucket}] Cloud side"
                If ( $Side.Count -gt 1 ) {
                    $sHeader = "`r`n=== Cloud Storage (AWS) ==="
                }
                $oReply.Contents |% {
                    $Match = ( @( ) + @( $FileNames ) ) -ieq $_.Key
                    If ( $Match.Count -eq 0 ) {
                        If ( $ReturnObject ) {
                            $_
                        }
                        Else {
                            If ( $sHeader ) { $sHeader; $sHeader = $null }
                            $_.Key
                        }
                    }
                }
            }

            }
            Else {
                Write-Warning ( "[cloud:${Bucket}] could not find contents in JSON reply: {0}; object:" -f $jsonReply )
                Write-Warning $oReply
            }

        }
        Else {
            Write-Warning ( "[cloud:${Bucket}] could not parse JSON reply: {0}" -f $jsonReply )
        }
    }
    Else {
        Write-Warning ( "[cloud:${Bucket}] null JSON reply: {0}" -f $jsonReply )
    }

}

}

Function Add-PackageToCloudStorageBucket {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $WhatIf=$false )

    Begin { If ( $WhatIf ) { $sWhatIf = "--dryrun" } Else { $sWhatIf = $null } }

    Process {

        $oFile = Get-FileObject -File $File
        $sFile = $oFile.FullName
        $Bucket = ($sFile | Get-CloudStorageBucket)

        If ( $sFile ) {
            If ( $Bucket ) {
                # AWS-CLI does not cope well with long path names even if Windows is configured to handle them.
                # Workaround solution, from https://forums.aws.amazon.com/thread.jspa?threadID=322302&tstart=100 :
                # Use the Win32 direct-to-filesystem bypass prefix \\?\
                #
                # More details: <https://docs.microsoft.com/en-us/windows/win32/fileio/naming-a-file#win32-file-namespaces>
                # on Win32 namespace prefixes and \\?\ in particular. Solution from 
                If ( $sFile.Length -ge 260 ) {
                    $sFile = ( '\\?\{0}' -f $sFile )
                }

                & $( Get-ExeForAWSCLI ) s3 cp "${sFile}" "s3://${Bucket}/" --storage-class DEEP_ARCHIVE ${sWhatIf}
            }
            Else {
                Write-Warning ( "[to cloud] Could not identify bucket: {0}" -f $File )
            }
        }
        Else {
            Write-Warning ( "[to cloud] No such file: {0}" -f $File )
        }

    }

    End { }

}

Export-ModuleMember -Function Get-CloudStorageBucket
Export-ModuleMember -Function Get-CloudStorageListing
Export-ModuleMember -Function Add-PackageToCloudStorageBucket

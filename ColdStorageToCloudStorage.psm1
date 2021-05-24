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
Import-Module $( My-Script-Directory -Command $MyInvocation.MyCommand -File "ColdStorageFiles.psm1" )
Import-Module $( My-Script-Directory -Command $MyInvocation.MyCommand -File "ColdStorageRepositoryLocations.psm1" )

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Get-CloudStorageBucketNamePart {
Param( [Parameter(ValueFromPipeline=$true)] $Item )

    Begin { }

    Process {
        If ( $Item | Get-Member -MemberType NoteProperty -Name "FullName" ) {
            $sItem = $Item.FullName
        }
        Else {
            $sItem = ( "{0}" -f $Item )
        }

        $sItem = ( $sItem.ToLower() -replace "[^a-z0-9]+","-" )
        $sItem = ( $sItem -replace "(^-+|-+$)","" )
        $sItem
    }

    End { }
}

Function Get-CloudStorageBucket {
Param( [Parameter(ValueFromPipeline=$true)] $Package, $Repository=@( ), [switch] $Force=$false )

Begin { }

Process {

    $oPackage = ( Get-FileObject -File $Package )
    $oRepository = ( Get-FileRepositoryProps -File $oPackage )
    If ( $oRepository ) {
        $sRepository = $oRepository.Repository
    }
    $Props = ( $oPackage | Get-ItemColdStorageProps -Order Nearest -Cascade )
    
    If ( $Props.ContainsKey("Bucket") -and ( -Not $Force ) ) {
        $packageName = ( $oPackage.Name )
        $packageSlug = ( ( $packageName.ToLower() ) -replace "[^A-Za-z0-9\-]+","-" )
        ( $Props["Bucket"] -f $packageName,$packageSlug ) | Write-Output
    }
    Else {
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
                $SectionSlug = "da"

                $ContainingDirectory = $( If ( $oPackage.Directory ) { $oPackage.Directory } ElseIf ( $oPackage.Parent ) { $oPackage.Parent } )

                # OPTION 1. Is this item CONTAINED WITHIN a Zipped Bags Container? If so, try to extract a default from the ZIP file name
                If ( $ContainingDirectory | Test-ZippedBagsContainer ) {
                    $Prefix = $oRepository.Prefix
                    $RelativePath = ( $oPackage.Name -replace "^${Prefix}","" )
                }
                ElseIf ( Test-Path -LiteralPath $oPackage.FullName -PathType Container ) {
                
                    $RelativePath = ( $ContainingDirectory.FullName | Resolve-PathRelativeTo -Base:$oRepository.Location )

                # OPTION 2. Is this item a preservation package? If so, its bucket is based on its parent.
                    If ( $oPackage | Get-ItemPackage ) {
                        $RelativePath = ( $ContainingDirectory.FullName | Resolve-PathRelativeTo -Base:$oRepository.Location )
                    }

                # OPTION 3. Does this item contain preservation packages? If so, its bucket is based on itself.
                    ElseIf ( $oPackage | Get-ChildItemPackages ) {
                        $RelativePath = ( $oPackage.FullName | Resolve-PathRelativeTo -Base:$oRepository.Location )
                    }

                }
                Else {
                    $RelativePath = ( $ContainingDirectory.FullName | Resolve-PathRelativeTo -Base:$oRepository.Location )
                }

                $SectionSlug = ( $SectionSlug | Get-CloudStorageBucketNamePart )
                $RepositorySlug = ( $sRepository | Get-CloudStorageBucketNamePart )
                $DirectorySlug = ( $RelativePath | Get-CloudStorageBucketNamePart )

                ( "{0}-{1}-{2}" -f $SectionSlug,$RepositorySlug,$DirectorySlug ) |% { If ( $_.Length -lt 64 ) { $_ } Else { $_.Substring(0, 60) + "--" + $_.Substring($_.Length-1, 1)  } } |  Write-Output
            }
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

Function New-CloudStorageBucket {
Param( [Parameter(ValueFromPipeline=$true)] $Bucket )

    Begin { $AWS = Get-ExeForAWSCLI }

    Process {
        If ( $AWS ) {
            If ( $Bucket ) {
                # Let's check whether or not this Bucket already exists.
                $JSON = ( & "${AWS}" s3api get-bucket-versioning --bucket "${Bucket}" 2>$null )
                $errAWS = $LastExitCode

                If ( $errAWS -gt 0 ) {
                    
                    $JSON = ( & "${AWS}" s3api create-bucket --acl private --bucket "${Bucket}" )
                    $errAWS = $LastExitCode
                    
                    If ( $errAWS -eq 0 ) {
                        $hBucketResults = @{
                            "URI"=( "s3://{0}" -f "${Bucket}" )
                            "Create"=( $JSON | ConvertFrom-Json )
                        }

                        $JSON = ( & "${AWS}" s3api put-bucket-versioning --bucket "${Bucket}" --versioning-configuration "Status=Enabled" )
                        $errAWS = $LastExitCode

                        If ( $errAWS -eq 0 ) {
                            $oBucketResult = ( $JSON | ConvertFrom-Json )
                            If ( -Not $oBucketResult ) {
                                $oBucketResult = "Enabled"
                            }
                            $hBucketResults["Versioning"] = $oBucketResult
                        }
                        Else {
                            Write-Warning "[New-CloudStorageBucket] Failed to set versioning on bucket '${Bucket}': ${JSON}"
                        }

                        $JSON = ( & "${AWS}" s3api put-public-access-block --bucket "${Bucket}" --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" )
                        $errAWS = $LastExitCode

                        If ( $errAWS -eq 0 ) {
                            $oBucketResult = ( $JSON | ConvertFrom-Json )
                            If ( -Not $oBucketResult ) {
                                $oBucketResult = "Blocked"
                            }
                            $hBucketResults["PublicAccess"] = $oBucketResult
                        }
                        Else {
                            Write-Warning "[New-CloudStorageBucket] Failed to set versioning on bucket '${Bucket}': ${JSON}"
                        }

                        [PSCustomObject] $hBucketResults | Write-Output

                    }
                    Else {
                        Write-Warning "[New-CloudStorageBucket] Failed to create bucket '${Bucket}': ${JSON}"
                    }
                }
                Else {
                    Write-Warning "[New-CloudStorageBucket] Bucket '${Bucket}' already exists."
                }

            }
        }
    }

    End { If ( -Not $AWS ) { Write-Error "[New-CloudStorageBucket] aws CLI tool not found!" } }

}

Function Get-CloudStorageBucketProperties {
Param( [Parameter(ValueFromPipeline=$true)] $Bucket )

    Begin { $AWS = Get-ExeForAWSCLI }

    Process {
        If ( $AWS ) {
            If ( $Bucket ) {

                $errAWSMesg = $( $JSON = ( & "${AWS}" s3api get-bucket-versioning --bucket "${Bucket}" ) ) 2>&1
                $errAWS = $LastExitCode

                If ( $errAWS -eq 0 ) {
            
                    $hBucketResults = @{
                        "URI"=( "s3://{0}" -f "${Bucket}" )
                        "Versioning"=( $JSON | ConvertFrom-Json )
                    }

                    $oBucketResult = ( $JSON | ConvertFrom-Json )
                    $hBucketResults["Versioning"] = $oBucketResult.Status

                    $JSON = ( & "${AWS}" s3api get-public-access-block --bucket "${Bucket}" )
                    $errAWS = $LastExitCode

                    If ( $errAWS -eq 0 ) {
                        $oBucketResult = ( $JSON | ConvertFrom-Json )
                        If ( $oBucketResult ) {
                            $bBlockPublicAcls = $oBucketResult.PublicAccessBlockConfiguration.BlockPublicAcls
                            $hBucketResults["PublicAccess"] = $( If ( $bBlockPublicAcls ) { "Blocked" } Else { "Not Blocked" } )
                        }                                
                    }
                    Else {
                        Write-Warning "[Get-CloudStorageBucketProperties] Failed to get public access block on bucket '${Bucket}': ${JSON}"
                    }

                    [PSCustomObject] $hBucketResults | Write-Output

                }
                Else {
                    Write-Warning "[Get-CloudStorageBucketProperties] No such bucket as '${Bucket}' in AWS: ${errAWSMesg} [JSON=${JSON}]"
                }

            }

        }

    }

    End { If ( -Not $AWS ) { Write-Error "[New-CloudStorageBucket] aws CLI tool not found!" } }

}

Function Get-CloudStorageURI {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {

        $Key = $File
        $Bucket = $null
        
        $oFile = $File
        If ( $oFile -is [Hashtable] ) {
            $oFile = [PSCustomObject] $oFile
        }

        If ( $oFile ) {

            If ( $oFile | Get-Member -MemberType NoteProperty -Name Key ) {
                $Key = ( $oFile.Key )
            }
            ElseIf ( $oFile | Get-Member -MemberType NoteProperty -Name CloudCopy ) {
                $Key = ( $oFile.CloudCopy.Key )
                $Bucket = ( $oFile.CloudCopy.Bucket )
            }
            ElseIf ( $oFile | Get-Member -MemberType Property -Name FullName ) {
                $Key = ( $oFile.Name )
            }

            If ( $Bucket -eq $null ) {
                If ( $oFile | Get-Member -MemberType NoteProperty -Name Bucket ) {
                    $Bucket = ( $oFile.Bucket )
                }
                ElseIf ( $oFile | Get-Member -MemberType Property -Name FullName ) {
                    $Bucket = ( $oFile | Get-CloudStorageBucket )
                }
            }

            $Scheme = "s3"

            If ( ( $Key -ne $null ) -and ( $Bucket -ne $null ) ) {
                ( "{0}://{1}/{2}" -f $Scheme,$Bucket,$Key ) | Write-Output
            }

        }

    }

    End { }

}

Function Get-CloudStorageListing {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $Unmatched=$false, $Side=@("local","cloud"), [switch] $ReturnObject, [switch] $Recurse=$false, [switch] $All=$false, [string] $Context="Get-CloudStorageListing" )

Begin { $bucketFiles = @{ }; $AWS = $( Get-ExeForAWSCLI ); }

Process {

    $oFile = $null
    $File | Get-ItemPackageForCloudStorageBucket -Recurse:$Recurse -ShowWarnings:$Context |% {
        $oFile = $_
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
}

End {
    $bucketFiles.Keys |% {
        $Bucket = $_
        $Files = $bucketFiles[$Bucket]

        If ( ( $All ) -or ( $Files.Count -ne 1 ) ) {
            Write-Debug ( "& {0} s3api list-objects-v2 --bucket '{1}'" -f ${AWS},$Bucket )
            $jsonReply = $( & ${AWS} s3api list-objects-v2 --bucket "${Bucket}" ) ; $awsExitCode = $LastExitCode
        }
        Else {
            $FileName = $Files.Name
            Write-Debug ( "& {0} s3api list-objects-v2 --bucket '{1}' --prefix '{2}'" -f ${AWS},$Bucket,$FileName )
            $jsonReply = $( & ${AWS} s3api list-objects-v2 --bucket "${Bucket}" --prefix "$FileName" ) ; $awsExitCode = $LastExitCode
        }

        If ( -Not $Unmatched ) {
            $Side = @("local", "cloud")
        }

        Write-Debug ( "Side(s): {0}" -f ( $Side -join ", " ) )

        $sContext = ( "[{0}:{1}] " -f $global:gCSScriptName,$Bucket )

        If ( $jsonReply ) {
            $oCloudContents = $null
            $isDataGood = $false
            $oReply = ( $jsonReply | ConvertFrom-Json )
            If ( $oReply ) {
                If ( $oReply.Contents ) {
                    $oCloudContents = $oReply.Contents
                    $isDataGood = $true
                }
                Else {
                    ( "${sContext}could not find contents in JSON reply: {0}; object:" -f $jsonReply ) | Write-Warning
                    $oReply | Write-Warning
                }
            }
            Else {
                ( "${sContext}could not parse JSON reply: {0}" -f $jsonReply ) | Write-Warning
            }
        }
        Else {
            $oCloudContents = @( )
            $isDataGood = ( $awsExitCode -eq 0 )
        }

        If ( $isDataGood ) {

            $ObjectKeys = ( $oCloudContents |% { $_.Key } )
            $ObjectObjects = ( $oCloudContents |% { $o = $_ ; $o | Add-Member -MemberType NoteProperty -Name Bucket -Value "${Bucket}" ; $sKey = $o.Key; @{ "${sKey}"=$o } } )
            $sHeader = $null

            If ( $All ) {
                
                If ( $ReturnObject ) {
                    $ObjectObjects
                }
                Else {
                    $ObjectKeys
                }

            }
            Else {

                If ( $Side -ieq "local" ) {
                    Write-Debug "${sContext}Local side"
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
                    "${sContext}Cloud side" | Write-Debug
                    If ( $Side.Count -gt 1 ) {
                        $sHeader = "`r`n=== Cloud Storage (AWS) ==="
                    }
                    $oCloudContents |% {
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

        }
        Else {
            Write-Warning ( "[cloud:${Bucket}] AWS CLI processing error: {0}" -f $awsExitCode )
        }

    }
}

}

Function Get-ItemPackageForCloudStorageBucket {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $Recurse=$false, $ShowWarnings=$null )

    Begin { }

    Process {
        $Items = ( $File | Get-ItemPackageZippedBag -Recurse:$Recurse )
        If ( $Items ) {
            $Items
        }
        ElseIf ( $ShowWarnings ) {
            ( "[{0}{1}] Could not find preservation package: {2}" -f $ShowWarnings,$( If ( $Recurse ) { " -Recurse" } Else { "" } ),$File ) | Write-Warning
        }
    }

    End { }

}

Function Add-PackageToCloudStorageBucket {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $WhatIf=$false, [switch] $Recurse=$false )

    Begin { $AWS = $( Get-ExeForAWSCLI ); If ( $WhatIf ) { $sWhatIf = "--dryrun" } Else { $sWhatIf = $null } }

    Process {

        $oFile = $null
        $File | Get-ItemPackageForCloudStorageBucket -Recurse:$Recurse -ShowWarnings:("{0} to cloud" -f $global:gCSScriptName) |% {
            $oFile = $_
            $sFile = $oFile.FullName
            $Bucket = ($sFile | Get-CloudStorageBucket)

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

                & ${AWS} s3 cp "${sFile}" "s3://${Bucket}/" --storage-class DEEP_ARCHIVE ${sWhatIf}
            }
            Else {
                Write-Warning ( "[{0} to cloud] Could not identify bucket: {1}" -f $global:gCSScriptName,$File )
            }
        }

    }

    End { }

}

Function Stop-CloudStorageUploadsToBucket {
Param ( [Parameter(ValueFromPipeline=$true)] $Bucket, [switch] $Batch=$false, [switch] $WhatIf=$false )

    Begin { If ( $WhatIf ) { $sWhatIf = "--dryrun" } Else { $sWhatIf = $null } }

    Process {

        $sMultipartUploadsJSON = ( & $( Get-ExeForAWSCLI ) s3api list-multipart-uploads --bucket "${Bucket}" )
        $oMultipartUploads = $( $sMultipartUploadsJSON | ConvertFrom-Json )
        $oMultipartUploads.Uploads |% {
            $Key = $_.Key
            $UploadId = $_.UploadId
            If ( $Key -and $UploadId ) {
                If ( $Batch ) {
                    Write-Warning "ABORT {$Key}, # ${UploadId} ..."
                    $cAbort = 'Y'
                }
                Else {
                    $cAbort = ( Read-Host -Prompt "ABORT ${Key}, # ${UploadId}? (Y/N)" )
                }
                If ( $cAbort[0] -ieq 'Y' ) {
                    If ( $WhatIf ) {
                        ( "& {0} {1} {2} {3} {4} {5} {6} {7} {8}" -f $( Get-ExeForAWSCLI ),"s3api","abort-multipart-upload","--bucket","${Bucket}","--key","${Key}","--upload-id","${UploadId}" ) | Write-Output
                    }
                    Else {
                        & $( Get-ExeForAWSCLI ) s3api abort-multipart-upload --bucket "${Bucket}" --key "${Key}" --upload-id "${UploadId}"
                    }
                }
            }
        }

    }

    End { }

}

Function Stop-CloudStorageUploads {
Param ( [Parameter(ValueFromPipeline=$true)] $Package, [switch] $Batch=$false, [switch] $WhatIf=$false )

    Begin {
        $Buckets = @{ }
    }

    Process {
        If ( $Package ) {
            $MaybeBucket = ( Get-FileObject($Package) | Get-CloudStorageBucket )
            If ( $MaybeBucket ) {
                $Buckets[$MaybeBucket] = $true
            }
        }
        Else {
            ( "[{0}] Could not determine cloud storage bucket for item: '{1}'" -f $global:gCSCommandWithVerb,$Package ) | Write-Warning
        }
    }

    End {
        $Buckets.Keys | Stop-CloudStorageUploadsToBucket -Batch:$Batch -WhatIf:$WhatIf
    }

}


Export-ModuleMember -Function Get-CloudStorageBucketNamePart
Export-ModuleMember -Function Get-CloudStorageBucket
Export-ModuleMember -Function New-CloudStorageBucket
Export-ModuleMember -Function Get-CloudStorageURI
Export-ModuleMember -Function Get-CloudStorageBucketProperties
Export-ModuleMember -Function Get-CloudStorageListing
Export-ModuleMember -Function Get-ItemPackageForCloudStorageBucket
Export-ModuleMember -Function Add-PackageToCloudStorageBucket
Export-ModuleMember -Function Stop-CloudStorageUploadsToBucket
Export-ModuleMember -Function Stop-CloudStorageUploads

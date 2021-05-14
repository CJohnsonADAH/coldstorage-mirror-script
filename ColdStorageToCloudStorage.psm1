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

Function Get-CloudStorageListing {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $Unmatched=$false, $Side=@("local","cloud"), [switch] $ReturnObject, [switch] $Recurse=$false, [string] $Context="Get-CloudStorageListing" )

Begin { $bucketFiles = @{ } }

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

        If ( $Files.Count -ne 1 ) {
            Write-Debug ( "& {0} s3api list-objects-v2 --bucket '{1}'" -f $( Get-ExeForAWSCLI ),$Bucket )
            $jsonReply = $( & $( Get-ExeForAWSCLI ) s3api list-objects-v2 --bucket "${Bucket}" ) ; $awsExitCode = $LastExitCode
        }
        Else {
            $FileName = $Files.Name
            Write-Debug ( "& {0} s3api list-objects-v2 --bucket '{1}' --prefix '{2}'" -f $( Get-ExeForAWSCLI ),$Bucket,$FileName )
            $jsonReply = $( & $( Get-ExeForAWSCLI ) s3api list-objects-v2 --bucket "${Bucket}" --prefix "$FileName" ) ; $awsExitCode = $LastExitCode
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
            $ObjectObjects = ( $oCloudContents |% { $sKey = $_.Key; @{ "${sKey}"=$_ } } )
            $sHeader = $null

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

    Begin { If ( $WhatIf ) { $sWhatIf = "--dryrun" } Else { $sWhatIf = $null } }

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

                & $( Get-ExeForAWSCLI ) s3 cp "${sFile}" "s3://${Bucket}/" --storage-class DEEP_ARCHIVE ${sWhatIf}
            }
            Else {
                Write-Warning ( "[{0} to cloud] Could not identify bucket: {1}" -f $global:gCSScriptName,$File )
            }
        }

    }

    End { }

}

Export-ModuleMember -Function Get-CloudStorageBucketNamePart
Export-ModuleMember -Function Get-CloudStorageBucket
Export-ModuleMember -Function New-CloudStorageBucket
Export-ModuleMember -Function Get-CloudStorageListing
Export-ModuleMember -Function Get-ItemPackageForCloudStorageBucket
Export-ModuleMember -Function Add-PackageToCloudStorageBucket

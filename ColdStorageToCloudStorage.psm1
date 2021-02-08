﻿#############################################################################################################
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
    $RepositoryPath = ( Get-FileRepository -File $oPackage )
    If ( $RepositoryPath ) {
        $oRepository = Get-FileObject -File $RepositoryPath
        $sRepository = $oRepository.Name
    }

    If ( $sRepository -match '(Processed|Unprocessed)$' ) {
        $RepositorySlug = $sRepository.ToLower()
        "er-collections-${RepositorySlug}" | Write-Output
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
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $Unmatched=$false )

Begin { $bucketFiles = @{ }; }

Process {

    $oFile = Get-FileObject -File $File
    $sFile = $oFile.FullName
    $Bucket = ($sFile | Get-CloudStorageBucket)

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

End {
    $bucketFiles.Keys |% {
        $Bucket = $_
        $Files = $bucketFiles[$Bucket]

        If ( $Files.Count -gt 1 ) {
            $jsonReply = $( & aws s3api list-objects-v2 --bucket "${Bucket}" )
        }
        Else {
            $FileName = $Files.Name
            $jsonReply = $( & aws s3api list-objects-v2 --bucket "${Bucket}" --prefix "$FileName" )
        }
    }

    If ( $jsonReply ) {
        $oReply = ( $jsonReply | ConvertFrom-Json )

        If ( $oReply ) {
            $ObjectKeys = ( $oReply.Contents |% { $_.Key } )
            $sHeader = $null
            If ( $Unmatched ) {
                $sHeader = "=== ADAHColdStorage ==="
            }
            $Files |% {
                $Match = ( @( ) + @( $ObjectKeys ) ) -ieq $_.Name
                If ( $Unmatched -xor ( $Match.Count -gt 0 ) ) {
                    If ( $sHeader ) { $sHeader; $sHeader = $null }
                    $_.Name
                }
            }

            $FileNames = ( $Files | Get-ItemPropertyValue -Name "Name" ) 
            If ( $Unmatched ) {
                $sHeader = "=== Cloud Storage (AWS) ==="
                $oReply.Contents |% {
                    $Match = ( @( ) + @( $FileNames ) ) -ieq $_.Key
                    If ( $Match.Count -eq 0 ) {
                        If ( $sHeader ) { $sHeader; $sHeader = $null }
                        $_.Key
                    }
                }
            }

        }
    }

    #FIXME: In -Diff mode ($Unmatched), also show objects in AWS bucket that do not match anything on ColdStorage???
}

}

Function Add-PackageToCloudStorageBucket {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $Unmatched=$false )

    Begin { }

    Process {

        $oFile = Get-FileObject -File $File
        $sFile = $oFile.FullName
        $Bucket = ($sFile | Get-CloudStorageBucket)

        If ( $sFile ) {
            If ( $Bucket ) {
                & $( Get-AWSCLIExe ) s3 cp "${sFile}" "s3://${Bucket}/" --storage-class DEEP_ARCHIVE
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
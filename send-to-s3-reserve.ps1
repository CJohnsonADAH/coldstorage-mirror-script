Param(
    [Parameter(ValueFromPipeline=$true)] $Source=$null,
    $Bucket=$null,
    $Region="us-east-1",
    [switch] $WhatIf
)

Begin { }

Process {

    If ( Test-Path -LiteralPath $Source.FullName -PathType Container ) {
    
        If ( $Bucket ) {
            $s3Name = ( "${Bucket}" ).ToLower()
        }
        Else {
            $s3Name = ( Read-Host -Prompt "Bucket Name" )
        }
        $s3Slug = ( "${s3Name}" -replace '[^A-Za-z0-9]+','-' )
        $s3Slug = ( "${s3Slug}" -replace '^(-)+','' )
        $s3Region = $Region
        $s3StorageClass = "DEEP_ARCHIVE"
        $DryRun = "--dryrun"

        If ( $s3Slug ) {
            $s3BucketUrl = ( "s3://{0}" -f $s3Slug )

            If ( -Not $WhatIf ) {
                & aws.exe s3 mb "${s3BucketUrl}" --region "${s3Region}" $( If ( $WhatIf ) { $DryRun } ); $awsExit = $LASTEXITCODE
            }
            Else {
                '& aws.exe s3 mb "{0}" --region "{1}" {2}' -f "${s3BucketUrl}","${s3Region}",$( If ( $WhatIf ) { $DryRun } ) | Write-Host -ForegroundColor Yellow
                $awsExit = 0
            }

            If ( $awsExit -eq 0 ) {
                $s3ReserveUrl = ( "{0}/reserve" -f $s3BucketUrl )
                If ( & read-yesfromhost-cs.ps1 -Prompt "Copy files into ${s3ReserveUrl}?" ) {
                    & aws.exe s3 cp $Source.FullName "${s3BucketUrl}" --storage-class "${s3StorageClass}" --recursive $( If ( $WhatIf ) { $DryRun } ) ; $awsExit = $LASTEXITCODE
                }
            }
        }
    }
}

End { }

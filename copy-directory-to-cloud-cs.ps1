Param(
    $Item=$null,
    $Bucket=$null,
    [switch] $WhatIf=$false,
    [switch] $Batch=$false
)

If ( $Bucket -eq $null ) {
    If ( -Not $Batch ) {
        $Bucket = ( Read-Host -Prompt "s3 Bucket" )
    }
}

If ( $Bucket -ne $null ) {
    $s3Url = ( "s3://{0}/reserve" -f $Bucket )
    $s3Url | Write-Warning
    & aws s3 ls "${s3Url}"
    
    If ( $Item -ne $null ) {
        If ( $WhatIf ) {
            & aws s3 cp --dryrun --recursive $Item $s3Url --storage-class DEEP_ARCHIVE 
        }
        Else {
            & aws s3 cp --recursive $Item $s3Url --storage-class DEEP_ARCHIVE 
        }
    }
    Else {
        "I HAVE NO ITEM TO COPY TO" | Write-Error
    }

}
Else {
    "I HAVE NO BUCKET TO UPLOAD TO" | Write-Error
}

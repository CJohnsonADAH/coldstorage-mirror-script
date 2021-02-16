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

Import-Module $( My-Script-Directory -Command $MyInvocation.MyCommand -File "ColdStorageFiles.psm1" )
Import-Module $( My-Script-Directory -Command $MyInvocation.MyCommand -File "ColdStorageRepositoryLocations.psm1" )
Import-Module $( My-Script-Directory -Command $MyInvocation.MyCommand -File "ColdStorageBaggedChildItems.psm1" )

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Format-Bytes {
Param (
    [Parameter(ValueFromPipeline=$true)] $Bob,
    $Number=$null,
    $OrderMagnitude=$null,
    [Int] $DecimalDigits=2
)

    Begin {
        $inNumber = $null
        $inOrder = $null
    }

    Process {
        If ( $Bob -is [ValueType] ) {
            $inNumber = [Float] $Bob
        }
        If ( $Number -ne $null ) {
            $inNumber = $Number
        }

        If ( $Bob -is [String] ) {
            $inOrder = [String] $Bob
        }
        If ( $OrderMagnitude -ne $null ) {
            $inOrder = $OrderMagnitude
        }

        $Unit = ( $inOrder.ToUpper() -replace '^(.?)I?B$','$1' )

        $Magnitude = $inNumber
        $Digits = 0
        If ( $Unit.Length -gt 0 ) {
            $Magnitude = ( $inNumber / ([Int64] 0+"1${Unit}B") )
            $Digits = $DecimalDigits
        }
        $HumanReadable = ( "{0:N${Digits}} {1}" -f ( $Magnitude, $inOrder ) )

        @{ Magnitude=${Magnitude}; Unit=${inOrder}; HumanReadable=${HumanReadable} }
    }

    End { }
}

Function Format-BytesHumanReadable {
Param ( [Parameter(ValueFromPipeline=$true)] [ValidateNotNullOrEmpty()] [Float] $Number, [Int] $DecimalDigits=2, [Float] $MinimumMagnitude=1.0, [switch] $ReturnAltnerate=$false, [switch] $ReturnObject=$false )

    Begin { $aSizes = 'B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB' }

    Process {
        $Output = ( $aSizes | Format-Bytes -DecimalDigits:$DecimalDigits -Number:$Number | Where-Object -Property Magnitude -GE $MinimumMagnitude )

        If ( $ReturnAlternate ) {
            $Output = ( $Output | Select-Object -First 1 -Last 1 )
        }
        Else {
            $Output = ( $Output | Select-Object -Last 1 )
        }

        If ( $ReturnObject ) {
            $Output
        }
        Else {
            ( $Output ).HumanReadable
        }

    }

    End { }
}

Function Get-RepositoryStats {
Param ( [Parameter(ValueFromPipeline=$true)] $Repository, $Count=1, [switch] $Batch=$false )

Begin { $oTable = @( ); $i = 0 }

Process {
    $sRepo = $Repository
    If ( -Not $Batch ) {
        Write-Progress -Id 101 -Activity "Scanning Repositories" -Status $sRepo -PercentComplete ($i*100.0/$Count)
        If ( $i -lt $Count ) {
            $i = $i + 1
        }

        Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status "Getting locations" -PercentComplete 0
    }

    $Location = Get-FileObject -File ( Get-ColdStorageLocation -Repository $Repository )
    $ZipLocation = ( Get-ColdStorageZipLocation -Repository $Repository )

    #If ( -Not $Batch ) {
    #    Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status "Counting files" -PercentComplete 20
    #}
    
    #$nFiles = ( Get-ChildItem -LiteralPath $Location.FullName -Recurse | Measure-Object ).Count

    If ( -Not $Batch ) {
        Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status "Counting packages" -PercentComplete 20
    }

    $aPackages = ( $Location | Get-ChildItemPackages -Recurse )
    $mPackages = ( $aPackages| Measure-Object -Property CSPackageContents -Sum )
    $nPackages = $mPackages.Count
    $nPackagedFiles = $mPackages.Sum
    
    $mFileSize = ( $aPackages | Measure-Object -Property CSPackageFileSize -Sum )
    $nFileSize = $mFileSize.Sum

    $mBagged = ( $aPackages | Measure-Object -Property CSPackageBagged -Sum )
    $nBagged = ( $mBagged ).Sum

    If ( -Not $Batch ) {
        Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status "Counting zipped bags" -PercentComplete 40
    }

    If ( $ZipLocation ) {
        $mZipped = ( Get-ChildItem -LiteralPath $ZipLocation.FullName | Measure-Object -Sum Length)
        $nZipped = $mZipped.Count
        $nZippedSize = $mZipped.Sum
    }
    Else {
        ( "{0} ZIP LOCATION: {1} DOES NOT EXIST." -f $sRepo,$ZipLocation ) | Write-Warning
        $nZipped = 0
    }

    #Write-Verbose ( "ZIP: {0}" -f $ZipLocation )
    
    If ( -Not $Batch ) {
        Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status "Counting bags in cloud storage" -PercentComplete 75
    }
    $bucket = ( $ZipLocation | Get-CloudStorageBucket )

    #Write-Verbose ( "BUCKET: {0}" -f $bucket )

    $nInCloud = 0
    If ( $bucket ) {
        If ( -Not $Batch ) {
            Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status ("Counting bags in cloud storage [{0}]" -f $bucket) -PercentComplete 80
        }
        $mInCloud = ( $ZipLocation | Get-CloudStorageListing -ReturnObject | Measure-Object -Sum Length )
        $nInCloud = $mInCloud.Count
        $nInCloudSize = $mInCloud.Sum
    }

    If ( -Not $Batch ) {
        Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status "Counting bags" -PercentComplete 60
    }

    #$aBagged = ( Get-BaggedChildItem -LiteralPath $Location.FullName )

    #$aBagged | Write-Verbose

    #$nBagged = $aBagged.Count

    If ( -Not $Batch ) {
        Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status "Writing object" -PercentComplete 100
   }

    $oRow = ( @{} | Select-Object @{n='Location';e={ $sRepo }},
        @{n='Packages';e={ $nPackages }},
        @{n='Files';e={ "{0:N0}" -f $nPackagedFiles }},
        @{n='FileSize';e={ $( $nFileSize | Format-BytesHumanReadable  ) }},
        @{n='Bagged';e={ $nBagged }},
        @{n='Zipped';e={ $nZipped }},
        @{n='ZippedSize'; e={ $nZippedSize | Format-BytesHumanReadable }},
        @{n='Cloud';e={ $nInCloud }},
        @{n='CloudSize'; e={ $nInCloudSize | Format-BytesHumanReadable }}
    )
    $oTable = $oTable + @( $oRow )

    If ( -Not $Batch ) {
        Write-Progress -Id 102 -Activity "Scanning ${sRepo}" -Status "Writing object" -PercentComplete 100 -Completed
    }
}

End {
    $oTable
    If ( -Not $Batch ) {
        Write-Progress -Id 101 -Activity "Scanning Repositories" -Completed
    }
 }

}

Export-ModuleMember -Function Get-RepositoryStats
Export-ModuleMember -Function Format-Bytes
Export-ModuleMember -Function Format-BytesHumanReadable

Param(
    [Parameter(ValueFromPipeline=$true)] $Package,
    [switch] $Batch=$false,
    [switch] $NoMirror=$false,
    [int] $InputTimeout=60,
    $InputDefault="N"
)

Begin {
    $global:gColdStorageSyncToPreservationCmd = $MyInvocation.MyCommand

        $modSource = ( $global:gColdStorageSyncToPreservationCmd.Source | Get-Item -Force )
        $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageUserPrivileges.psm1" ) -Force

    $Interactive = ( -Not $Batch )

}

Process {
    If ( $Package | test-cs-package-is ) {

        If ( ( -Not $NoMirror ) -and ( $Package | test-cs-package-is -Unmirrored ) ) {

            $DoIt = $Batch
            If ( ( -Not $DoIt ) -and $Interactive ) {
                $DoIt = ( read-yesfromhost-cs.ps1 -Prompt ( "CONFIRM: Mirror package {0}?" -f $Package.Name ) -Timeout:$InputTimeout -DefaultInput:N -DefaultTimeout:60 -DefaultAction:"leave unmirrored" )
            }
            If ( $DoIt ) {
                $Package | & coldstorage mirror -Items
            }
        }

        $PassThru = $false
        $SkipOver = $false
        If ( $Package | test-cs-package-is -Unbagged ) {
            $DefaultYN = $( If ( $PassThru ) { "Y" } Else { $InputDefault } )
            $DefaultLeaveDo = $( If ( $PassThru ) { "bag package" } Else { "leave unbagged" } )
            $TimeoutYN = $( If ( $PassThru ) { 10 } Else { $InputTimeout } )

            $PassThru = $false
            $SkipOver = $true
        
            $DoIt = $Batch
            If ( ( -Not $DoIt ) -and $Interactive ) {
                If ( ( $InputTimeout -lt 0 ) -and ( $Package.Name -like '*.pdf' ) ) {
                    $DefaultYN = "Y"
                    $TimeoutYN = 10
                }

                $DoIt = ( read-yesfromhost-cs.ps1 -Prompt ( "CONFIRM: Bag up package {0}?" -f $Package.Name ) -Timeout:$TimeoutYN -DefaultInput:$DefaultYN -DefaultTimeout:10 -DefaultAction:$DefaultLeaveDo )
            }
            If ( $DoIt ) {
                $Package | & coldstorage bag -Items
                $Package = ( $Package | & coldstorage packages -Items -Bagged -Mirrored -Zipped -InCloud )
                $PassThru = $true
                $SkipOver = $false
            }
        }
        If ( -Not $SkipOver -and ( $PassThru -or ( $Package | test-cs-package-is -Unzipped ) ) ) {
            $DefaultYN = $( If ( $PassThru ) { "Y" } Else { $InputDefault } )
            $DefaultLeaveDo = $( If ( $PassThru ) { "zip package" } Else { "leave unzipped" } )
            $TimeoutYN = $( If ( $PassThru ) { 10 } Else { $InputTimeout } )

            $PassThru = $false
            $SkipOver = $true

            $DoIt = $Batch
            If ( ( -Not $DoIt ) -and $Interactive ) {
                $DoIt = ( read-yesfromhost-cs.ps1 -Prompt ( "CONFIRM: Zip package {0}?" -f $Package.Name ) -Timeout:$TimeoutYN -DefaultInput:$DefaultYN -DefaultTimeout:10 -DefaultAction:$DefaultLeaveDo )
            }
            If ( $DoIt ) {
                $Package | & coldstorage zip -Items
                $Package = ( $Package | & coldstorage packages -Items -Bagged -Mirrored -Zipped -InCloud )
                $PassThru = $true
                $SkipOver = $false
            }
        }
        If ( -Not $SkipOver -and ( $PassThru -or ( $Package | test-cs-package-is -NotInCloud ) ) ) {
            $DefaultYN = $( If ( $PassThru ) { "Y" } Else { $InputDefault } )
            $DefaultLeaveDo = $( If ( $PassThru ) { "upload to cloud" } Else { "leave not in cloud" } )
            $TimeoutYN = $( If ( $PassThru ) { 10 } Else { $InputTimeout } )

            $PassThru = $false
            $SkipOver = $true


            $DoIt = $Batch
            If ( ( -Not $DoIt ) -and $Interactive ) {
                $DoIt = ( read-yesfromhost-cs.ps1 -Prompt ( "CONFIRM: Upload {0} to cloud?" -f $Package.Name ) -Timeout:$TimeoutYN -DefaultInput:$DefaultYN -DefaultTimeout:10 -DefaultAction:$DefaultLeaveDo )
            }
            If ( $DoIt ) {
                $Package | & coldstorage to cloud -Items
                $Package = ( $Package | & coldstorage packages -Items -Bagged -Mirrored -Zipped -InCloud )
                $PassThru = $true
                $SkipOver = $false
            }
        }
    
        If ( $DoIt ) {
            $Package | write-packages-report-cs.ps1 | Write-Host -ForegroundColor Green -BackgroundColor Black
        }
    }
}

End {
}

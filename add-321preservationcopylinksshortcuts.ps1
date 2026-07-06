Param(
    [Parameter(ValueFromPipeline=$true)] $Package,
    $Output='string',
    [switch] $Confirm
)

Begin {
    $ExitCode = 0

    $global:g321PreservationCopyLinksCmd = $MyInvocation.MyCommand

        $modSource = ( $global:g321PreservationCopyLinksCmd.Source | Get-Item -Force )
        $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageData.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageRepositoryLocations.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageBagItDirectories.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )

    $AWS = ( Get-ExeForAWSCLI )

    Function New-321PreservationCopyShortcutFile {
    Param ( [string] $TargetPath, [string] $ShortcutPath )
        "LNK: {0} -> {1}!" -f $ShortcutPath, $TargetPath|Write-Verbose
        
        $WshShell = New-Object -COMObject WScript.Shell
        
        $Shortcut = $WshShell.CreateShortcut( $ShortcutPath )
        $Shortcut.TargetPath = $TargetPath
        $Shortcut.Save()

        If ( Test-Path -LiteralPath:$Shortcut.FullName -PathType:Leaf ) {
            
            Get-Item -LiteralPath:$Shortcut.FullName -Force | Write-Output

        }
    }

}

Process {
    $Package321 = ( $Package | & get-itempackage-cs.ps1 -Check321 )

    $Rpt = [ordered] @{ }
    
    $Rpt[ 'Copy-1' ] = $Package321.FullName
    If ( $Package321.CSPackageCanonicalLocation ) {
        $sCanonicalLocation = $Package321.CSPackageCanonicalLocation

        $Root = $null
        If ( Test-Path -LiteralPath:$sCanonicalLocation -PathType:Container ) {
            $Root = ( Get-Item -LiteralPath:$sCanonicalLocation -Force ).Root
        }
        ElseIf ( Test-Path -LiteralPath:$sCanonicalLocation -PathType:Leaf ) {
            $Root = ( Get-Item -LiteralPath:$sCanonicalLocation -Force ).Directory.Root
        }

        $Rpt[ 'Copy-1' ] = [PSCustomObject] @{ "SHARE"=$Root; "DESTINATION"=$Package321.CSPackageCanonicalLocation }
    }

    $Copy2 = $null
    If ( $Package321.CSPackageMirrorCopy ) {
        $Copy2 = $Package321.CSPackageMirrorCopy

        $Root = $null
        If ( Test-Path -LiteralPath:$Copy2.FullName -PathType:Container ) {
            $Root = ( $Copy2.Root )
        }
        ElseIf ( Test-Path -LiteralPath:$Copy2.FullName -PathType:Leaf ) {
            $Root = ( $Copy2.Directory.Root )
        }

        $Rpt[ 'Copy-2' ] = [PSCustomObject] @{ "SHARE"=$Root; "DESTINATION"=$Copy2.FullName }
    }

    $s3Uri = $null
    If ( $Package321.CloudCopy ) {
        $s3Uri = ( $Package321 | Get-CloudStorageURI )
        $Rpt[ 'Copy-3' ] = [PSCustomObject] @{ "SHARE"=( 's3://{0}' -f ( $Package321 | Get-CloudStorageBucket ) ); "DESTINATION"=$s3Uri }
    }

    $Rpt.Keys |% {
        "{0} [{1}]: {2}" -f $_.ToUpper(), $Rpt[ $_ ].SHARE, $Rpt[ $_ ].DESTINATION | Write-Verbose
        
        $sShortcutPath = $null

        If ( $Package321 | Test-BagItFormattedDirectory ) {
            $sShortcutTarget = $Rpt[ $_ ].DESTINATION
            $sShortcutName = ( "Copy-{0}.lnk" -f ( ( ( $Rpt[ $_ ].SHARE -replace '^([^0-9A-Za-z]+)','' ) -replace '([^0-9A-Za-z]+)$','' ) -replace '([^0-9A-Za-z]+)','-' ) )
            
            $sShortcutContainer = ( $Package321.FullName | Join-Path -ChildPath:"preservation-copies" )
            If ( -Not ( Test-Path -LiteralPath:$sShortcutContainer -PathType:Container ) ) { 
                $oShortcutContainer = ( New-Item -ItemType:Directory -Path:$sShortcutContainer )
                $sShortcutContainer = $oShortcutContainer.FullName
            }
            If ( Test-Path -LiteralPath:$sShortcutContainer -PathType:Container ) {
                $sShortcutPath = ( $sShortcutContainer | Join-Path -ChildPath:$sShortcutName )
            }
        }
        ElseIf ( $Package321 | Test-LooseFile ) {
            
            If ( $Rpt[ $_ ].DESTINATION -like 's3://*' ) {
                $sShortcutTarget = $Rpt[ $_ ].DESTINATION
                $sShortcutName = ( "{0}.Copy-{1}.lnk" -f $Package321.Name, ( ( ( $Rpt[ $_ ].SHARE -replace '^([^0-9A-Za-z]+)','' ) -replace '([^0-9A-Za-z]+)$','' ) -replace '([^0-9A-Za-z]+)','-' ) )
            }
            Else {
                $sShortcutTarget = ( $Rpt[ $_ ].DESTINATION | Get-321LooseFileChecksumSidecarsContainer )
                $sShortcutName = ( "Copy-{0}.lnk" -f ( ( ( $Rpt[ $_ ].SHARE -replace '^([^0-9A-Za-z]+)','' ) -replace '([^0-9A-Za-z]+)$','' ) -replace '([^0-9A-Za-z]+)','-' ) )
            }
            
            $sShortcutContainer = ( $Package321 | Get-321LooseFileChecksumSidecarsContainer )
            If ( Test-Path -LiteralPath:$sShortcutContainer -PathType:Container ) {
                
                $sShortcutPath = ( $sShortcutContainer | Join-Path -ChildPath:$sShortcutName )
            
            }
        }
        If ( $sShortcutPath -ne $null ) {
            New-321PreservationCopyShortcutFile -TargetPath:$sShortcutTarget -ShortcutPath:$sShortcutPath
        }
    }

}

End {
    Exit $ExitCode
}

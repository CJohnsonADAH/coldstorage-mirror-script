Param(
    $FullAt=$null,
    [switch] $Batch=$false,
    [switch] $Q=$false,
    [switch] $ER=$false,
    [switch] $Loop=$false,
    $Path=@()
)

$global:gColdStorageMirrorCheckupCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gColdStorageMirrorCheckupCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageRepositoryLocations.psm1" )

Function Test-DirectoryIsBaked {
    Param ( [Parameter(ValueFromPipeline=$true)] $File, [Int] $At )

    Begin { }

    Process {
        If ( $File -ne $null ) {
            Write-Progress -Id 502 -Activity "Measuring" -Status $_.FullName
            $N = ( Get-ChildItem -LiteralPath $File.FullName -Force | Measure-Object )
            Write-Progress -Id 502 -Activity "Measuring" -Completed

            $File | Add-Member -MemberType NoteProperty -Name CSMCFileCount -Value $N.Count -Force
            ( $N.Count -ge $At )

        }
    }

    End { }
}

Function Get-ItemFileCount {
Param( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        If ( $File -ne $null ) {
            If ( $_ | Get-Member -Name CSMCFileCount ) {
                $_.CSMCFileCount | Write-Output
            }
            Else {
                $N = ( Get-ChildItem -LiteralPath $_.FullName -Force | Measure-Object )
                $N.Count | Write-Output
            }
        }
    }

    End { }
}

Function Invoke-CSMirrorCheckup {
    Param ( $BakedAt=$null, [switch] $Batch=$false )

    Begin {
        $modSource = ( $global:gColdStorageMirrorCheckupCmd.Source | Get-Item -Force )
        $modPath = ( $modSource.Directory | Get-Item -Force )
        $cmdCSScript = ( $modPath.FullName | Join-Path -ChildPath "coldstorage.ps1" )
        $cmdCSGetPackages = ( $modPath.FullName | Join-Path -ChildPath "coldstorage-get-packages.ps1" )
    }

    Process {
        $_ | Write-Warning
        $oRepository = ( $_ | & "${cmdCSScript}" repository -Items )
        $oPackages = ( Get-Item $_.FullName | & "${cmdCSGetPackages}" -At -Items )
        If ( $oPackages.Count -gt 0 ) {
            $_
        }
        Else {
            $aoPackages = @{ }
            & "${cmdCSGetPackages}" -Items $_ |% { Write-Progress -Activity "Scanning (Phase I)" -Status $_.FullName ; $aoPackages[$_.FullName] = $_ }
            $isDirectoryWithPackages = ( $aoPackages.Keys.Count -gt 0 )

            Get-ChildItem -LiteralPath $_.FullName |% {
                If ( $_ | Test-ColdStoragePropsDirectory ) {
                    # NOOP
                }
                ElseIf ( $aoPackages.ContainsKey( $_.FullName ) ) {
                    # NOOP
                }
                ElseIf ( ( $isDirectoryWithPackages -and ( Test-Path -LiteralPath $_.FullName -PathType Container ) ) -and ( $oRepository.Repository -eq 'Unprocessed' ) ) {
                    ( "ER-UNPROCESSED: {0}" -f $_.FullName ) | Write-Warning
                }
                ElseIf ( $isDirectoryWithPackages -and ( Test-Path -LiteralPath $_.FullName -PathType Container ) ) {

                    $Props = ( $_ | Get-ItemColdStorageProps )
                    $nBakedAt = $BakedAt
                    If ( $nBakedAt -eq $null ) {
                        $nBakedAt = $Props.PackageCount
                    }
                    If ( $nBakedAt -eq $null ) {
                        $nBakedAt = 500
                    }

                    Write-Progress -Activity "Scanning (Phase II)" -Status $_.FullName

                    $DoBag = $false
                    $DoMirror = $false

                    If ( $_ | Test-DirectoryIsBaked -At:$nBakedAt ) {
                        $DoBag = ( [bool] $Batch )
                        $DoMirror = ( [bool] $Batch )
                        If ( -Not $Batch ) {
                            $N = ($_ | Get-ItemFileCount )
                            $PromptStatus = ( "BAKED: {0} ({1:N0} FILE{2} >= {3:N0})" -f $_.FullName,$N,$( If ( $N -eq 1 ) { "" } Else { "S" } ),$nBakedAt )
                            $DoBag = ( & read-yesfromhost-cs.ps1 -Prompt:( "{0}`r`n{1}" -f $PromptStatus,"CONFIRM: coldstorage bag -Bundle?" ) -Timeout:20.0 -DefaultAction "coldstorage bag -Bundle" )
                            $DoMirror = $DoBag
                        }
                    }
                    Else {
                        $DoBag = $false
                        $DoMirror = ( [bool] $Batch )
                        If ( -Not $Batch ) {
                            $N = ($_ | Get-ItemFileCount )
                            $PromptStatus = ( "STILL COOKIN': {0} ({1:N0} FILE{2} < {3:N0})" -f $_.FullName,$N,$( If ( $N -eq 1 ) { "" } Else { "S" } ),$nBakedAt )
                            $DoMirror = ( & read-yesfromhost-cs.ps1 -Prompt:( "{0}`r`n{1}" -f $PromptStatus,"CONFIRM: coldstorage mirror?" ) -Timeout:20.0 -DefaultAction "coldstorage mirror" )
                        }
                    }

                    If ( $DoBag ) {
                        & coldstorage bag -Bundle -Items $_.FullName -PassThru | & coldstorage zip -Items -PassThru | & coldstorage to cloud -Items
                    }
                    If ( $DoMirror ) {
                        & coldstorage mirror -Items $_.FullName -RoboCopy
                    }

                }
                Else {
                    ( "I HAVE NO IDEA WHAT TO DO: {0}" -f $_.FullName ) | Write-Warning
                }
            }
        }
    }

    End {
    }
}

# ... abandoned from a never-really-implemented "coldstorage ripe" command, intended for assessing additions to Digital Assets for mirroring, or bundling, or...
# Function Where-Item-Is-Ripe {
# Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $ReturnObject=$false )
#
# Begin { $timestamp = Get-Date }
#
# Process {
#    $oFile = Get-FileObject -File $File
#    $span = ( ( $timestamp ) - ( $oFile.CreationTime ) )
#    If ( ( $span.Days ) -ge ( $RipeDays ) ) {
#        If ( $ReturnObject ) {
#            $oFile
#        }
#        Else {
#            $oFile.FullName
#        }
#    }
# }

End { }

}

$Automat = $false
$ContinueLoop = $Loop
Do {
    If ( $Loop ) {
        "LOOP: {0}" -f ( Get-Date )
    }

    If ( $ER ) {
        $Automat = $true
        Push-Location H:\ElectronicRecords\Unprocessed
    
        "ER-Unprocessed: {0}" -f ( Get-Date )
        & coldstorage.ps1 packages -Zipped -Mirrored -InCloud -Items . |% {
            Write-Progress $_.FullName
            If ( -Not ( $_.CSPackageMirrored ) ) { $_ | & coldstorage mirror -Items }
            If ( ( $_.CloudCopy -eq $null ) -or ( $_.CloudCopy.Count -eq 0 ) ) { & coldstorage zip -Items -PassThru $_.FullName | & coldstorage to cloud -Items }
        }

        Pop-Location
    }

    If ( $Q ) {
        $Automat = $true

        Push-Location H:\Digitization\Masters\Q_numbers
        Get-Item Master,Altered |% {
            "DA-Q {0}: {1}" -f $_.Name,( Get-Date )
            Push-Location $_.FullName ;
            &coldstorage-mirror-checkup.ps1 ;
            Pop-Location
        }
        Pop-Location
    }

    If ( $Loop ) {
        "/LOOP: {0}" -f ( Get-Date )
        $ContinueLoop = ( & read-yesfromhost-cs.ps1 -Prompt "Continue mirror looping?" -DefaultAction "continue" -Timeout:60.0 )
        Sleep 10
    }

} While ( $ContinueLoop )

If ( -Not $Automat ) {
    $allObjects = @( $Input ) + @( $Path )
    If ( $allObjects.Count -eq 0 ) {
        $allObjects = @( Get-Item -LiteralPath ( ( Get-Location ).Path ) )
    }

    $aPaths = ( $allObjects |% { $o = ( $_ | Get-FileObject ) ; If ( ( $o -is [Object] ) -and ( $o | Get-Member -Name "FullName" ) ) { $o } Else { Write-Warning ( "FAILED: {0}" -f $_ ) } } )
    $aPaths |? { -Not ( $_.Name -like '.*' ) } | Invoke-CSMirrorCheckup -BakedAt:$FullAt -Batch:$Batch
}
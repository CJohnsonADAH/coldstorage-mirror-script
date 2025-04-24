Param(
    $FullAt=$null,
    [switch] $Batch=$false,
    [switch] $Q=$false,
    [switch] $ER=$false,
    [switch] $Loop=$false,
    [switch] $SU=$false,
    [switch] $Catchup=$false,
    [switch] $Validate=$false,
    $InputTimeout=60,
    $Path=@()
)

$global:gColdStorageMirrorCheckupCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gColdStorageMirrorCheckupCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageRepositoryLocations.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageUserPrivileges.psm1" )

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
    Param ( $BakedAt=$null, [switch] $Batch=$false, [switch] $SU=$false, [switch] $Validate=$false )

    Begin {
        $modSource = ( $global:gColdStorageMirrorCheckupCmd.Source | Get-Item -Force )
        $modPath = ( $modSource.Directory | Get-Item -Force )
        $cmdCSScript = ( $modPath.FullName | Join-Path -ChildPath "coldstorage.ps1" )
        $cmdCSGetPackages = ( $modPath.FullName | Join-Path -ChildPath "coldstorage-get-packages.ps1" )
    }

    Process {
        ( "[Invoke-CSMirrorCheckup] Process: {0}" -f "$_" ) | Write-Verbose
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

                    Write-Progress -Activity "Scanning (Phase II)" -Status $_.FullName

                    $DoBag = $false
                    $DoMirror = $false

                    If ( $_ | test-readytobundle-cs.ps1 ) {
                        $DoBag = ( [bool] $Batch )
                        $DoMirror = ( [bool] $Batch )
                        If ( -Not $Batch ) {
                            $N = ($_ | Get-ItemFileCount )
                            $PromptStatus = ( "BAKED: {0} ({1:N0} FILE{2})" -f $_.FullName,$N,$( If ( $N -eq 1 ) { "" } Else { "S" } ) )
                            $DoBag = ( & read-yesfromhost-cs.ps1 -Prompt:( "{0}`r`n{1}" -f $PromptStatus,"CONFIRM: coldstorage bag -Bundle?" ) -Timeout:20.0 -DefaultAction "coldstorage bag -Bundle" )
                            $DoMirror = $DoBag
                        }
                    }
                    Else {
                        $DoBag = $false
                        $DoMirror = ( [bool] $Batch )
                        If ( -Not $Batch ) {
                            $N = ($_ | Get-ItemFileCount )
                            $PromptStatus = ( "STILL COOKIN': {0} ({1:N0} FILE{2})" -f $_.FullName,$N,$( If ( $N -eq 1 ) { "" } Else { "S" } ) )
                            $DoMirror = ( & read-yesfromhost-cs.ps1 -Prompt:( "{0}`r`n{1}" -f $PromptStatus,"CONFIRM: coldstorage mirror?" ) -Timeout:20.0 -DefaultAction "coldstorage mirror" )
                        }
                    }

                    If ( $DoBag ) {
                        & coldstorage bag -Bundle -Items $_.FullName -PassThru | & coldstorage zip -Items -PassThru | & coldstorage to cloud -Items
                    }
                    If ( $DoMirror ) {
                        & coldstorage mirror -Items $_.FullName -RoboCopy -Scheduled
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
#
#End { }

# }

Function Get-CSRepositoryLogFile {
Param ( [Parameter(ValueFromPipeline=$true)] $Dir )

    $Container = ( Join-Path $Dir -ChildPath ".coldstorage\logs" )
    If ( -Not ( Test-Path $Container -PathType Container ) ) {
        If ( -Not ( Test-Path $Container ) ) {
            $ContainerItem = ( New-Item $Container -ItemType:Directory -Confirm -Force )
        }
        Else {
            Get-Item $Container | Write-Warning
            "I HAVE NO IDEA WHAT TO DO!!!" | Write-Error
            Exit 255
        }
    }

    ( Join-Path $Container -ChildPath "mirror-checkup.log" ) | Write-Output

}

$Invoc = $MyInvocation
$cmd = $Invoc.MyCommand
If ( -Not ( Test-UserHasNetworkAccess ) ) {
    If ( $SU ) {
        $cmdName = $cmd.Name
        $loc = ( Get-ColdStorageAccessTestPath )
        "[{0}] Unable to acquire network access to {1}" -f $cmdName,$loc | Write-Error
        Exit 255
    }
    Else {
        $retval = ( Invoke-SelfWithNetworkAccess -Invocation:$Invoc -Loop:$Loop )

        Exit $retval
    }
}
Else {
    ( "[{0}] User has network access to {1}; good to go!" -f $cmd.Name,( Get-ColdStorageAccessTestPath ) ) | Write-Verbose
}

$Automat = $false
$ContinueLoop = $Loop

$dirQNumbers = "H:\Digitization\Masters\Q_numbers"
$dirSC = "H:\Digitization\Masters\Supreme_Court"
$dirERUnprocessed = "H:\ElectronicRecords\Unprocessed"
$dirERProcessed = "H:\ElectronicRecords\Processed"

$ERProcessed_LogFile = ( $dirERProcessed | Get-CSRepositoryLogFile )

Do {
    If ( $Loop ) {
        "LOOP: {0}" -f ( Get-Date ) | Write-Host
    }

    If ( $ER ) {
        $Automat = $true
        Push-Location $dirERProcessed

        $T0 = ( Get-Date )

        If ( $Q ) {
            $ProcessedWindow=20
            $ProcessedTimeout=( New-TimeSpan -Minutes:30 )
        }
        Else {
            $ProcessedWindow=60
            $ProcessedTimeout=( New-TimeSpan -Minutes:60 )
        }


        $ERProcessed_Dirs = @()
        $LogWriteWindow = ( $T0 - ( [DateTime]::Parse("1/1/1970 00:00") ) )
        If ( Test-Path -LiteralPath $ERProcessed_LogFile ) {
            $ERProcessed_Dirs = ( Get-Content -LiteralPath $ERProcessed_LogFile -ErrorAction SilentlyContinue |? { "$_" -notmatch '^[#]' } )
            $LogWriteWindow = ( $T0 - ( Get-Item -LiteralPath $ERProcessed_LogFile ).CreationTime )
        }

        If ( $LogWriteWindow.Days -gt 0 ) {        
            ( "# Started {0} (N={1})" -f ( Get-Date ), $ProcessedWindow ) > $ERProcessed_LogFile
        }
        Else {
            ( "# Continued {0} (N={1})" -f ( Get-Date ), $ProcessedWindow ) >> $ERProcessed_LogFile
        }

        "ER-Processed: {0} ({1})" -f ( $T0 ),$ProcessedWindow | Write-Host
        
        & report-status-erprocessed.ps1 -Directories:$ProcessedWindow -Timeout:$ProcessedTimeout -RandomOrder -Progress -LogFile:$ERProcessed_LogFile -PassThru | & sync-cs-packagetopreservation.ps1 -InputTimeout:$InputTimeout
        
        $TN = ( Get-Date )
        Write-Progress -Activity "Scanning ER-Processed" -Completed ; ( $TN- $T0 )
        
        Pop-Location

        Push-Location $dirERUnprocessed
    
        "ER-Unprocessed: {0}" -f ( Get-Date )
        & coldstorage.ps1 packages -Zipped -Mirrored -InCloud -Items . |% {
            Write-Progress $_.FullName
            If ( -Not ( $_.CSPackageMirrored ) ) { $_ | & coldstorage mirror -Items -Force }
            If ( ( $_.CloudCopy -eq $null ) -or ( $_.CloudCopy.Count -eq 0 ) ) { & coldstorage zip -Items -PassThru $_.FullName | & coldstorage to cloud -Items }
        }

        Pop-Location


    }

    If ( $Q ) {
        $Automat = $true

        Push-Location $dirQNumbers
        Get-Item Master,Altered |% {
            "DA-Q {0}: {1}" -f $_.Name,( Get-Date ) | Write-Host -ForegroundColor White -BackgroundColor Black
            Push-Location $_.FullName
            & coldstorage-mirror-checkup.ps1 -SU:$SU -Validate:$Validate -InputTimeout:$InputTimeout
            Pop-Location
        }
        Pop-Location

        Push-Location $dirSC
        "DA-SC: {0}" -f ( Get-Date ) | Write-Host -ForegroundColor White -BackgroundColor Black
        & coldstorage.ps1 packages -Zipped -Mirrored -InCloud -Items . |? { Test-Path -LiteralPath $_.FullName -PathType Container } |% {
            Write-Progress -Activity "Preservation Checkup" -Status ( "{0}" -f ( $_ | & write-packages-report-cs.ps1 ) ) 
            $_ | & sync-cs-packagetopreservation.ps1 -InputTimeout:$InputTimeout
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
    $aPaths |? { -Not ( $_.Name -like '.*' ) } | Invoke-CSMirrorCheckup -BakedAt:$FullAt -Batch:$Batch -Validate:$Validate
}
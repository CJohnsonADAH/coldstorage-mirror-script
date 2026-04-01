<#
out-baggedpackage-cs.ps1

.SYNOPSIS
Enclose a preservation package of digital content into a BagIt-formatted preservation package.

.DESCRIPTION
Given a loose file or a directory of digital content, enclose that within a BagIt-formatted preservation package following ADAHColdStorage packaging conventions.

If the input is a directory, the output will be a directory in the same location containing BagIt manifest files and the original content enclosed in a payload directory called "data".

If the input is a loose file, the output will be a BagIt-formatted directory located within the same parent container, containing a copy of the loose file enclosed in a payload directory called "data".

Formerly known as: Do-Bag-Loose-File

.PARAMETER LiteralPath
Specifies the loose file or the directory to enclose within a BagIt-formatted package.

.PARAMETER PassThru
If present, output the location of the BagIt-formatted package into the pipeline after completing the bagging.

.PARAMETER Progress
If provided, provides a [CSProgressMessenger] object to manage progress and logging output from the process.
#>

Param(
    [Parameter(ValueFromPipeline=$true)] $LiteralPath,
    [switch] $PassThru=$false,
    [switch] $Shadow=$false,
    $Context=$null
)

Begin {

    $global:gOutBaggedPackageCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gOutBaggedPackageCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageInteraction.psm1" )

    Function Get-CommandWithVerb {
    Param( [Parameter(ValueFromPipeline=$true)] $Context )

        Begin { }

        Process {
            If ( $Context -ne $null ) {
                $Context | Write-Output
            }
            ElseIf ( $global:gCSCommandWithVerb ) {
                $global:gCSCommandWithVerb | Write-Output
            }
            Else {
                $global:gOutBaggedPackageCmd.Name | Write-Output
            }
        }

        End { }

    }

    $ExiCode = 0
    $cmd = ( $Context | Get-CommandWithVerb )

}

Process {

    If ( -Not $LiteralPath ) {
        "[{0}] parameter LiteralPath seems to be empty" -f $cmd | Write-Warning
    }
    Else {

        $Item = ( $LiteralPath | Get-FileObject )

        # If this is a single (loose) file, then we will create either sidecar files or a parallel counterpart directory
        If ( Test-Path -LiteralPath:$Item.FullName -PathType:Leaf ) {

            If ( -Not $Shadow ) {
                "sha256","sha512" |% {
                    $Item | add-checksumsidecar-cs.ps1 -Algorithm:$_
                }
                $Item | add-checksumsidecartag-cs.ps1
            }
            Else {
                Push-Location -LiteralPath $Item.DirectoryName

                $OriginalFileName = $Item.Name
                $OriginalFullName = $Item.FullName
                $FileName = ( $Item | Get-PathToBaggedCopyOfLooseFile )

                $BagDir = ( Get-Location | Add-BaggedCopyContainer | Join-Path -ChildPath "${FileName}" )
                If ( -Not ( Test-Path -LiteralPath $BagDir ) ) {
                    $oBagDir = ( New-Item -Type Directory -Path $BagDir )
                    $BagDir = $( If ( $oBagDir ) { $oBagDir.FullName } Else { $null } )
                }

                If ( Test-Path -LiteralPath $BagDir -PathType Container ) {
                
                    # Move the loose file into its containing counterpart directory. We'll re-link it to its old directory later.
                    Move-Item -LiteralPath $Item -Destination $BagDir

                    # Now rewrite the counterpart directory as a BagIt-formatted preservation package
                    $BagDir | out-bagitformatteddirectory-cs.ps1 -PassThru:$PassThru -Progress:$Progress ; $bagExit = $LASTEXITCODE
                    If ( $bagExit -eq 0 ) {

                        # If all went well, then hardlink a reference at the loose file's old location to the new BagIt directory payload
                        $DataDir = ( "${BagDir}" | Join-Path -ChildPath "data" )
                        $Payload = ( "${DataDir}" | Join-Path -ChildPath "${OriginalFileName}" )
                        If ( Test-Path -LiteralPath "${Payload}" ) {
                        
                            New-Item -ItemType HardLink -Path "${OriginalFullName}" -Target "${Payload}" | %{ "[$cmd] Bagged ${BagDir}, created link to payload: $_" | Write-Verbose }
	        
                            # Set file attributes to ReadOnly -- bagged copies should remain immutable
                            Set-ItemProperty -LiteralPath "${OriginalFullName}" -Name IsReadOnly -Value $true
                            Set-ItemProperty -LiteralPath "${Payload}" -Name IsReadOnly -Value $true

                        }
                        Else {
                            ( "[$cmd] BagIt process completed OK, but ${cmd} could not locate BagIt payload: '{0}'" -f "${Payload}" ) | Write-Error
                        }

                    }

                }
                Else {
                    ( "[$cmd] Could not create or locate counterpart directory for BagIt to operate on: '{0}'" -f "${BagDir}" ) | Write-Error
                }

                Pop-Location
            }

        }

        # If this is a directory, then we run BagIt directly over the directory.
        ElseIf ( Test-Path -LiteralPath:$Item.FullName -PathType:Container ) {
            $LiteralPath | out-bagitformatteddirectory-cs.ps1 -Verbose:$Verbose -PassThru:$PassThru -Progress:$Progress
        }

        Else {
            ( "[$cmd] Preservation package not found: '{0}'" -f $LiteralPath ) | Write-Warning
        }
    }
}

End {
    Exit $ExitCode
}
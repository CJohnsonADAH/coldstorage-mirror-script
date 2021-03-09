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

$global:gADPNetModuleCmd = $MyInvocation.MyCommand

Import-Module -Verbose:$false Posh-SSH

Import-Module -Verbose:$false  $( My-Script-Directory -Command $global:gADPNetModuleCmd  -File "ColdStorageSettings.psm1" )
Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gADPNetModuleCmd -File "ColdStorageRepositoryLocations.psm1" )
Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gADPNetModuleCmd -File "ColdStorageZipArchives.psm1" )

#############################################################################################################
## PUBLIC FUNCTIONS: CREDENTIALS TO CONNECT TO DROP SERVER ##################################################
#############################################################################################################

Function Get-DropServerAuthority {

    $address = ( Get-ColdStorageSettings -Name "Drop-Server-SFTP" )
    
    ( $address -split "@",2 ) | Write-Output

}

Function Get-DropServerHost {

    ( Get-DropServerAuthority )[1]

}

Function Get-DropServerUser {

    ( Get-DropServerAuthority )[0]

}

Function Get-DropServerPassword {
Param ( [string] $SFTPHost )

    $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $utf8 = New-Object -TypeName System.Text.UTF8Encoding
    $hash = [System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($SFTPHost)))

    $FileName = "${hash}.txt"
    $Txt = $( My-Script-Directory -Command $global:gADPNetModuleCmd -File "${FileName}" )

    If ( Test-Path -LiteralPath $Txt ) {
        ( Get-Content -LiteralPath $Txt ).Trim()
    }

}

#############################################################################################################
## PUBLIC FUNCTIONS: Prepare ADPNet/LOCKSS manifest HTML documents ##########################################
#############################################################################################################

Function Get-ADPNetStartDir {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    Get-ZippedBagNamePrefix -File $File | Write-Output
}

End { }

}

Function Get-ADPNetStartURL {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { $hrefPrefix = Get-ColdStorageSettings -Name "Drop-Server-URL" }

Process {
    $hrefPath = ( $File | Get-ADPNetStartDir )
    ( "{0}/{1}/" -f $hrefPrefix, $hrefPath ) | Write-Output
}

End { }

}

Function Get-LOCKSSManifestPath {
Param( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    $sFile = Get-FileLiteralPath -File $File
    "${sFile}\manifest.html" | Write-Output
}

End { }
}

Function Get-LOCKSSManifest {
Param( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    
    $sFile = Get-FileLiteralPath -File $File

    If ( Test-Path -LiteralPath $sFile ) {

        $manifest = ( $sFile | Get-LOCKSSManifestPath )
        Get-FileObject -File $manifest | Write-Output

    }

}

End { }
}

Function Add-LOCKSSManifestHTML {
Param( $Directory, [string] $Title, [switch] $Force=$false )

    if ( $Directory -eq $null ) {
        $Path = ( Get-Location )
    } else {
        $Path = ( $Directory )
    }

    $TitlePrefix = Get-ColdStorageSettings -Name "Institution"

    if ( Test-Path -LiteralPath "${Path}" ) {
        $UNC = ( Get-Item -Force -LiteralPath "${Path}" | Get-UNCPathResolved -ReturnObject )
        $oManifest = ( $UNC | Get-LOCKSSManifest )
        If ( ( $oManifest ) -and ( -Not $Force ) ) {
            Write-Warning ( "[manifest:${Directory}] manifest.html already exists for this AU ({0} bytes, created {1}). Use -Force flag to force it to be regenerated." -f $oManifest.Length, $oManifest.CreationTime )
        }
        Else {

            $NL = [Environment]::NewLine

            $htmlStartLink = ( '<a href="{0}">{1}</a>' -f $( $Path | Get-ADPNetStartURL ), $Title )
            $imgSrcBaseHref = ( "{0}/{1}" -f ( Get-ColdStorageSettings -Name "Drop-Server-URL" ), "assets/images" )
            $imgSrc = ( "{0}/{1}" -f $imgSrcBaseHref,"lockss-small.png" )

            $htmlLOCKSSBadge = ( '<img src="{0}" alt="LOCKSS" width="108" height="108" />' -f $imgSrc )
            $htmlLOCKSSPermission = 'LOCKSS system has permission to collect, preserve, and serve this Archival Unit.'
            
            $htmlBody = ( (
                "<p>${htmlStartLink}</p>",
                "<p>${htmlLOCKSSBadge} ${htmlLOCKSSPermission}</p>",
                ""
            ) -Join "${NL}" )
            
            $htmlTitle = ( "{0}: {1}" -f $TitlePrefix, $Title )

            $htmlOut = (
                (
                    (
                "<!DOCTYPE html>",
                "<html>",
                "<head>",
                "<title>{0}</title>",
                "</head>",
                "<body>",
                "<h1>{0}</h1>",
                "{1}",
                "</body>",
                "</html>",
                ""
                    ) -join "${NL}"
                ) -f $htmlTitle, $htmlBody
            )

            $htmlOut | Out-File -FilePath ( $UNC | Get-LOCKSSManifestPath ) -NoClobber:(-Not $Force) -Encoding utf8
        }
    }
}



#############################################################################################################
## PUBLIC FUNCTIONS: PACKAGES INTO LOCKSS ARCHIVAL UNITS (AUs) ##############################################
#############################################################################################################

Function Get-ADPNetAUTitle {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Process {
    $oFile = Get-FileObject -File $File

    # Fully qualified file system path to the containing parent
    $sFilePath = $oFile.Parent.FullName
    
    # Fully qualified UNC path to the containing parent
    $oFileUNCPath = ( $sFilePath | Get-UNCPathResolved -ReturnObject )
    $sFileUNCPath = $oFileUNCPath.FullName

    # Slice off the root directory up to the node name of the repository container
    $oRepository = Get-FileObject -File ( $oFileUNCPath | Get-FileRepositoryLocation )
    $sRepository = $oRepository.FullName
    $sRepositoryNode = ( $oRepository.Parent.Name, $oRepository.Name ) -join "-"

    $reUNCRepo = [Regex]::Escape($sRepository)
    $sPathRelativeToRepo = ( $sFileUNCPath -ireplace "^${reUNCRepo}\\+","" )
    
    $RepositoryNodes = Get-ColdStorageSettings -Name "AU-Titles"

    $Title = $null
    If ( $RepositoryNodes.${sRepositoryNode} ) {
        $sFileName = $oFile.Name
        $Node = $RepositoryNodes.${sRepositoryNode}

        $Node.PSObject.Properties | ForEach {
            $Wildcard = ( $_.Name | ConvertTo-ColdStorageSettingsFilePath )
            $Props = $_.Value -split "//"

            ( "[${global:gCSScriptName} manifest] Checking AU Title rule: {0} -> {1}" -f $Wildcard, $Props ) | Write-Verbose
            
            If ( ".\${sPathRelativeToRepo}\${sFileName}" -like $Wildcard ) {
                $Pattern = $Props[0]
                $Process = ( $Props[1] -split "/" )[0..1]

                $sSlug = $oFile.NAme -replace $Process
                $Title = $Pattern -f ( $sSlug )
            }

        }

    }
    
    If ( $Title ) {
        $Title | Write-Output
    }
}

}

####


Function Add-ADPNetAUToDropServerStagingDirectory {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {

        $Location = ( Get-Item -LiteralPath $File )
            
        $sLocation = $Location.FullName

        If ( -Not ( $Location | Get-LOCKSSManifest ) ) {

            $sTitle = ( $Location | Get-ADPNetAUTitle )
            If ( -Not $sTitle ) {
                $sTitle = ( Read-Host -Prompt "AU Title [${Location}]" )
            }

            Add-LOCKSSManifestHTML -Directory $File -Title $sTitle -Force:$Force

        }

        ( $Location | Set-DropServerFolder )

    }

    End { }

}

Function New-DropServerSession {

    $User = Get-DropServerUser
    $PWord = ConvertTo-SecureString -String ( Get-DropServerPassword -SFTPHost ( Get-DropServerHost ) ) -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord

    New-SFTPSession -ComputerName ( Get-DropServerHost ) -Credential ( $Credential )
}

Function Set-DropServerFolder {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin {
    $session = ( New-DropServerSession )
}

Process {
    $oFile = ( Get-FileObject -File $File )
    $sFile = $oFile.FullName

    If ( $session ) {
        If ( Test-BagItFormattedDirectory -File $sFile ) {

            If ( $oFile | Get-LOCKSSManifest ) {

                $RemoteRoot = "/drop_au_content_in_here"
                Set-SFTPLocation -SessionId $session.SessionId -Path "${RemoteRoot}"

                $RemoteDestination = ( $oFile | Get-ADPNetStartDir )
                Get-SFTPChildItem -SessionId $session.SessionId -Path $RemoteRoot |% {

                    If ( $_.Name -ieq "${RemoteDestination}" ) {
                        $RemoteBase = $_
                    }
                }


                If ( Test-SFTPPath -SFTPSession:$session -Path:$RemoteDestination ) { # Already uploaded; sync.
                    Write-Verbose "[drop:$sFile] already exists; sync with local copy."
                    $oFile | Sync-DropServerAU -SFTPSession:$session -RemoteRepository:$RemoteRoot
                }
                Else {
                    Write-Verbose "[drop:$sFile] not yet staged; add local copy"
                    $oFile | Add-DropServerAU -SFTPSession:$session -RemoteRepository:$RemoteRoot
                }

            }
            Else {
                Write-Warning "[drop:$sFile]: Requires LOCKSS manifest.html file. Use: & coldstorage manifest -Items '${sFile}'"
            }

        }
        Else {

            Write-Warning "[drop:$sFile]: Requires bagit formatting. Use: & coldstorage bag -Items '${sFile}'"

        }
    }
    Else {

        Write-Warning "[drop:$sFile]: SFTP connection failed."
        Write-Error $session

    }

}

End {
    If ( $session ) {
        $removed = ( Remove-SFTPSession -SessionId $session.SessionId )
    }
}

}

Function Add-DropServerAU {
    Param ( [Parameter(ValueFromPipeline=$true)] $LocalFolder, $SFTPSession, $RemoteRepository )

    Begin { }

    Process {
        $sLocalFullName = $LocalFolder.FullName
        $sRemotePath = ( $LocalFolder | Get-ADPNetStartDir )
        Set-SFTPFolder -SessionId:($SFTPSession.SessionId) -LocalFolder:$sLocalFullName -RemotePath:$sRemotePath
    }

    End { }

}

Function Sync-DropServerAU {
Param ( [Parameter(ValueFromPipeline=$true)] $LocalFolder, $SFTPSession, $RemoteRepository )

Begin { }

Process {
    $RemoteDestination = ( $LocalFolder | Get-ADPNetStartDir )
    Get-SFTPChildItem -SessionId:($SFTPSession.SessionId) -Path:$RemoteRepository |% {

        If ( $_.Name -ieq "${RemoteDestination}" ) {
            $RemoteBase = $_
        }

    }

    Get-SFTPChildItem -SessionId $session.SessionId -Recursive -Path $RemoteDestination |% {
        $RemoteFile = $_
        $LocalFile = ( $_ | Get-ADPNetFileLocalPath -Session:$session -LocalBase:$LocalFolder -RemoteBase:$RemoteBase )
        $RemoteAttr = Get-SFTPPathAttribute -SessionId $session.SessionId -Path $RemoteFile.FullName
            
        $LocalLength = $LocalFile.Length
        $RemoteLength = $RemoteAttr.Size
            
        $WrittenLater = ( $LocalFile.LastWriteTime -gt $RemoteAttr.LastWriteTime )
        $SizesDiffer = ( $LocalFile.Length -ne $RemoteAttr.Size )
        If ( $RemoteAttr.IsRegularFile ) {
            If ( $WrittenLater -or $SizesDiffer ) {
                $FileName = $LocalFile.Name
                Write-Warning "${FileName} differs. Local copy: ${LocalLength}; Remote: ${RemoteLength}"
                $RemotePath = ( $RemoteFile.FullName -split "/" )
                $RemoteParent = ( $RemotePath[0..($RemotePath.Count-2)] ) -join "/"
                Set-SFTPItem -SFTPSession:$session -Path:($LocalFile.FullName) -Destination:($RemoteParent) -Force -Verbose
            }
        }
    }

}

End { }
}

Function Get-ADPNetFileLocalPath {
Param ( [Parameter(ValueFromPipeline=$true)] $RemoteFile, $Session, $LocalBase, $RemoteBase )

Begin { }

Process {
    $reRemoteBase = [Regex]::Escape($RemoteBase.FullName)
    $remoteRelative = ( $RemoteFile.FullName -replace "^${reRemoteBase}/","" ) -replace "[/]","\"
    $LocalizedFileName = ( $LocalBase.FullName + "\${remoteRelative}" )
    If ( Test-Path -LiteralPath $LocalizedFileName ) {
        Get-Item -Force -LiteralPath $LocalizedFileName | Write-Output
    }
}

End { }
}

Export-ModuleMember -Function Get-DropServerAuthority
Export-ModuleMember -Function Get-DropServerHost
Export-ModuleMember -Function Get-DropServerUser
Export-ModuleMember -Function Get-DropServerPassword

Export-ModuleMember -Function Add-ADPNetAUToDropServerStagingDirectory
Export-ModuleMember -Function New-DropServerSession
Export-ModuleMember -Function Set-DropServerFolder
Export-ModuleMember -Function Add-DropServerAU
Export-ModuleMember -Function Sync-DropServerAU
Export-ModuleMember -Function Get-ADPNetFileLocalPath

Export-ModuleMember -Function Get-ADPNetAUTitle
Export-ModuleMember -Function Get-ADPNetStartDir
Export-ModuleMember -Function Get-ADPNetStartURL
Export-ModuleMember -Function Get-LOCKSSManifestPath
Export-ModuleMember -Function Get-LOCKSSManifest
Export-ModuleMember -Function Add-LOCKSSManifestHTML

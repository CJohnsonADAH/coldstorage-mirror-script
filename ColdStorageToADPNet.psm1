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
Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gADPNetModuleCmd -File "LockssPluginProperties.psm1" )

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
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $Parameterize=$false )

Begin { $hrefPrefix = ( "{0}/" -f ( Get-ColdStorageSettings -Name "Drop-Server-URL" ).TrimEnd("/") ) }

Process {
    $hrefPath = ( $File | Get-ADPNetStartDir )
    If ( $Parameterize ) {
        @{ base_url=$hrefPrefix; directory=$hrefPath }
    }
    Else {
        ( "{0}{1}/" -f $hrefPrefix, $hrefPath )
    }
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

Function Get-LOCKSSManifestBadgeImage {
Param( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        ( "{0}/{1}" -f ( Get-ColdStorageSettings -Name "Drop-Server-URL" ).TrimEnd("/"), "assets/images" )
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
            $imgSrcBaseHref = ( $Path | Get-LOCKSSManifestBadgeImage )
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

Function Write-ADPNetAUReport {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $sAUTitle = ( $File | Get-ADPNetAUTitle )
        $sInstitution = ( Get-ColdStorageSettings -Name "Institution" )

        $sPluginJar = ( Get-ColdStorageSettings -Name "ADPNet-Plugin-Jar" )
        $oPackage = ( $File | Get-ItemPackage -Recurse:$Recurse -ShowWarnings:$ShowWarnings )

        $nBytes = $oPackage.CSPackageFileSize
        $nFiles = $oPackage.CSPackageContents
        $sFileSizeReadable = ( "{0}" -f ( $nBytes | Format-BytesHumanReadable ) )

        $sFileSizeBytes = ( "{0:N0} byte{1}" -f $nBytes,$( If ( $nBytes -ne 1 ) { "s" } Else { "" } ) )
        $sFileSizeFiles = ( "{0:N0} file{1}" -f $nFiles,$( If ( $nFiles -ne 1 ) { "s" } Else { "" } ) )
        $sFileSize = ( "{0} ({1}, {2})" -f $sFileSizeReadable,$sFileSizeBytes,$sFileSizeFiles )

        $sFromPeer = ( Get-ColdStorageSettings -Name "ADPNet-Node" )
        $sToPeer = $null # FIXME: stub this for the moment

        $Book = ( $File | Get-ADPNetStartUrl -Parameterize )
        $pluginParams = ( $sPluginJar | Get-ADPNetPlugins | Get-ADPNetPluginDetails -Interpolate:$Book )

        $sAUStartURL = ( $pluginParams["au_start_url"] |% { $_ } )
        $sAUManifest = ( $pluginParams['au_manifest'] |% { $_ } )

        $hashAU = @{
            'Ingest Title'=( "{0}: {1}" -f $sInstitution,$sAUTitle );
            'File Size'=( $sFileSize );
            'Plugin JAR'=( $sPluginJar );
            'Plugin ID'=( $pluginParams["plugin_identifier"] |% { $_ } );
            'Plugin Name'=( $pluginParams["plugin_name"] |% { $_ } );
            'Plugin Version'=( $pluginParams["plugin_version"] |% { $_ } );
            'au_name'=( $pluginParams["au_name"] |% { $_ } );
            'au_start_url'=( $pluginParams["au_start_url"] |% { $_ } );
        }
        If ( $sAUStartURL ) {
            $hashAU['Start URL']=( $sAUStartURL )
        }
        If ( $sAUManifest ) {
            $hashAU['Manifest URL']=( $sAUManifest )
        }

        $pluginParams["plugin_config_props"] |% {
            $sName = ( "{0}" -f $_.displayName )
            $sKey = ( "{0}" -f $_.key )
            If ( $Book.ContainsKey($sKey) ) {
                $hashAU[$sName] = ( '{0}="{1}"' -f $sKey,$Book[$sKey] )

                If ( -Not ( $hashAU.ContainsKey("parameters") ) ) {
                    $hashAU["parameters"] = @()
                }
                $OrderedPair = @( $sKey, $Book[$sKey] )
                $hashAU["parameters"] += , $OrderedPair

            }
        }

        If ( $sFromPeer ) {
            $hashAU['From Peer']=( $sFromPeer )
        }
        If ( $sToPeer) {
            $hashAU['To Peer']=( $sToPeer )
        }
        $jsonPacket = ( $hashAU | ConvertTo-Json -Compress )

        "INGEST INFORMATION AND PARAMETERS:"
        "----------------------------------"
        $hashAU.Keys |% {
            If ( -Not ( $_ -match "(.*)_(.*)" ) ) {
                If ( $hashAU[$_] -is [String] ) {
                    ("{0}: `t{1}" -f $_.ToUpper(), $hashAU[$_])
                }
            }
        }
        ""
        ( "JSON PACKET: {0}" -f $jsonPacket )

    }

    End { }

}

#############################################################################################################
## PUBLIC FUNCTIONS: TRANSFER LOCKSS ARCHIVAL UNTIS (AUs) TO DROP SERVER VIA SFTP ###########################
#############################################################################################################

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


Function Get-LockssBoxAuthority {

    $address = ( Get-ColdStorageSettings -Name "Lockss-Box-SFTP" )
    
    ( $address -split "@",2 ) | Write-Output

}

Function Get-LockssBoxHost {

    ( Get-LockssBoxAuthority )[1]

}

Function Get-LockssBoxUser {

    ( Get-LockssBoxAuthority )[0]

}

Function Get-ColdStoragePasswordFile {
Param ( [string] $SFTPIdentity )

    $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $utf8 = New-Object -TypeName System.Text.UTF8Encoding
    $hash = [System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($SFTPIdentity)))

    $IdParts = ( $SFTPIdentity -split "@",2 )
    
    $FileName = "${hash}.txt"
    $Txt = $( My-Script-Directory -Command $global:gADPNetModuleCmd -File "${FileName}" )
    If ( Test-Path -LiteralPath $Txt ) {
        Get-Item -LiteralPath $Txt -Force
    }
    Else {
        Write-Warning ( "NO SUCH FILE: {0}" -f $Txt )
        $Credential = ( Get-Credential -Message ( "Credentials to connect to {0}" -f $SFTPIdentity ) -UserName ( $IdParts[0] ) )
        $Credential.Password | ConvertFrom-SecureString > $Txt
        Get-Item -LiteralPath $Txt -Force
    }

}

Function Get-LockssBoxPassword {
Param ( [string] $SFTPIdentity="" )
    
    $IdParts = Get-LockssBoxAuthority
    If ( $SFTPIdentity.Length -eq 0 ) {
        $SFTPIdentity = ( ( $IdParts ) -join "@" )
    }

    $File = Get-ColdStoragePasswordFile -SFTPIdentity:$SFTPIdentity
    If ( $File ) {
        $Txt = ( Get-Content -LiteralPath $File.FullName )
        $SecurePassword = ( $Txt | ConvertTo-SecureString -ErrorAction SilentlyContinue )
        If ( $SecurePassword -eq $null ) {
            $Credential = ( Get-Credential -Message ( "Credentials to connect to {0}" -f $SFTPIdentity ) -UserName ( $IdParts[0] ) )
            $Credential.Password | ConvertFrom-SecureString > $File.FullName
            $Credential.Password
        }
        Else {
            $SecurePassword
        }
    }

}
Function New-LockssBoxSession {

    $User = Get-LockssBoxUser
    $Pass = Get-LockssBoxPassword
    If ( $Pass -eq $null ) {
        
    }
    ElseIf ( $Pass.GetType() -eq [String] ) {
        $PWord = ConvertTo-SecureString -String ( $Pass ) -AsPlainText -Force
    }
    Else {
        $PWord = $Pass
    }
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord

    New-SFTPSession -ComputerName ( Get-LockssBoxHost ) -Credential ( $Credential )
}

Function Sync-ADPNetPluginsPackage {

    Param ( [Parameter(ValueFromPipeline=$true)] $LocalFolder, $Session )

    Begin { }

    Process {
        $sLocalFullName = $LocalFolder.FullName
        $sRemotePathURI = ( Get-ColdStorageSettings -Name "ADPNet-Plugin-Package" )
        $uriRemotePath = [uri] $sRemotePathURI
        $sRemoteHost = $uriRemotePath.Host
        $sRemotePath = $uriRemotePath.AbsolutePath

        If ( $session.Connected ) {
            Write-Verbose ( "{0} {1} {2} {3}" -f "Get-SFTPItem",'-SFTPSession:$SftpSession',"-Path:${sRemotePath}","-Destination:${sLocalFullName}" )
            Get-SFTPItem -SFTPSession:$Session -Path:${sRemotePath} -Destination:${sLocalFullName} -Verbose
        }
        Else {
            Write-Warning "[Sync-ADPNetPluginsPackage] Connection failure: SFTP session not connected."
        }

    }

    End { }

}

Function Get-ADPNetPlugins {
Param( [Parameter(ValueFromPipeline=$true)] $URL )

    Begin {
        $Location = ( Get-ColdStorageSettings -Name "ADPNet-Plugin-Cache" | ConvertTo-ColdStorageSettingsFilePath )
        $oLocation = ( Get-Item -LiteralPath $Location -Force )
        $aJarList = Get-ChildItem -LiteralPath $oLocation.FullName -Recurse
    }

    Process {
        $aJarList |% {
            $Accepted = ( $_.Name -like '*.jar' )

            If ( $URL -ne $null ) {
                If ( ( $URL -eq "." ) -or ( $URL -eq "default" ) -or ( $URL -eq '$_' ) ) {
                    $URL = ( Get-ColdStorageSettings -Name "ADPNet-Plugin-Jar" )
                }

                $u = [uri] $URL
                $sJarPath = ( $u.AbsolutePath | ConvertTo-ColdStorageSettingsFilePath )
                $sJarFileName = ( ( $sJarPath -split "\\" ) | Select-Object -Last 1 )

                $Accepted = ( $Accepted -and ( $_.Name -eq $sJarFileName ) )
            }
 
            If ( $Accepted ) {
                $_
            }
        }
    }

    End { }

}

Function Get-ADPNetPluginDetails {
Param( [Parameter(ValueFromPipeline=$true)] $Plugin, $Interpolate=$null )

    Begin { }

    Process {
        $Plugin | Expand-ADPNetPlugin | Get-LockssPluginXML -ReturnObject | ConvertTo-LockssPluginProperties -Interpolate:$Interpolate
    }

    End { }

}

Function Expand-ADPNetPlugin {
Param( [Parameter(ValueFromPipeline=$true)] $JAR )

    Begin { $Location = ( Get-ColdStorageSettings -Name "ADPNet-Plugin-Cache" | ConvertTo-ColdStorageSettingsFilePath ) }

    Process {
        $sDestination = ( "{0}\{1}" -f ( Get-Item -LiteralPath $Location -Force).FullName,"Expanded" )

        If ( -Not ( Test-Path -LiteralPath $sDestination ) ) {
            $Destination = ( New-Item -Path $sDestination -ItemType Directory -Verbose )
        }
        Else {
            $Destination = ( Get-Item -Force -LiteralPath $sDestination )
        }

        $oJAR = Get-FileObject($JAR)
        $OutputName = ( $oJAR.Name -replace "[^A-Za-z0-9]+","-" )
        $sZip = ( "{0}\{1}" -f $Destination.FullName,$OutputName )

        # Copy the jar
        Get-ChildItem -LiteralPath $Destination.FullName |% { If ( $_.Name -like '*.zip' ) { If ( $_.Name -ne $OutputName ) { Remove-Item $_.FullName -Verbose } } }

        If ( -Not ( Test-Path -LiteralPath $sZip ) ) {
            Copy-Item -LiteralPath $oJAR.FullName -Destination $sZip -Verbose
        
            # Pour out the jar into the workspace
            Expand-Archive -LiteralPath $sZip -DestinationPath $Destination.FullName
        }
        Get-ChildItem -LiteralPath $Destination.FullName -Recurse
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
Export-ModuleMember -Function Write-ADPNetAUReport
Export-ModuleMember -Function Get-ADPNetADPNet
Export-ModuleMember -Function Get-ADPNetStartDir
Export-ModuleMember -Function Get-ADPNetStartURL
Export-ModuleMember -Function Get-LOCKSSManifestPath
Export-ModuleMember -Function Get-LOCKSSManifest
Export-ModuleMember -Function Add-LOCKSSManifestHTML

Export-ModuleMember -Function Get-ColdStoragePasswordFile
Export-ModuleMember -Function Get-LockssBoxAuthority
Export-ModuleMember -Function Get-LockssBoxHost
Export-ModuleMember -Function Get-LockssBoxUser
Export-ModuleMember -Function Get-LockssBoxPassword
Export-ModuleMember -Function New-LockssBoxSession
Export-ModuleMember -Function Get-ADPNetPlugins
Export-ModuleMember -Function Get-ADPNetPluginDetails
Export-ModuleMember -Function Sync-ADPNetPluginsPackage 
Export-ModuleMember -Function Expand-ADPNetPlugin

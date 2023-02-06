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

Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gADPNetModuleCmd -File "ColdStorageSettings.psm1" )
Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gADPNetModuleCmd -File "ColdStorageFiles.psm1" )
Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gADPNetModuleCmd -File "ColdStorageStats.psm1" )
Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gADPNetModuleCmd -File "ColdStoragePackagingConventions.psm1" )
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

Function Get-ADPNetReportFileName {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $oFile = Get-FileObject($File)
        $sRemotePath = ( $oFile | Get-ADPNetStartDir )

        ( "{0}.au.txt" -f $sRemotePath ) | Write-Output
    }

    End { }

}

Function Get-ADPNetReportURL {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $Parameterize=$false )

    Begin { $hrefPrefix = ( "{0}/" -f ( Get-ColdStorageSettings -Name "Drop-Server-URL" ).TrimEnd("/") ) }

    Process {
        $hrefPath = ( $File | Get-ADPNetReportFileName )
        If ( $Parameterize ) {
            @{ base_url=$hrefPrefix; filename=$hrefPath }
        }
        Else {
            ( "{0}{1}" -f $hrefPrefix, $hrefPath )
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

Function Get-LOCKSSManifestHTML {
Param ( [Parameter(ValueFromPipeline=$true)] $Path, [string] $Title, [string] $TitlePrefix="" )

    Begin { }

    Process {
        $htmlOut = $null

        $ServiceURL = Get-ColdStorageSettings -Name "Make-LOCKSS-Manifest-Service"

        If ( $ServiceURL ) {
            $AU = ( $Path | Get-ADPNetAUTable -ForService )

            $oReq = Invoke-WebRequest -Uri $ServiceURL -Method "POST" -Body ( [PSCustomObject] @{
                institution_code = $AU['Institution Code']
                institution_name = $AU['Institution Name']
                au_title = $AU['AU Title']
                au_directory = $AU['AU Directory']
                au_file_size = $AU['File Size']
                drop_server = $AU['Drop Server']
                lockss_plugin = $AU['Plugin JAR']
                lockss_plugin_id = $AU['Plugin ID']
                lockss_plugin_name = $AU['Plugin Name']
                lockss_plugin_version = $AU['Plugin Version']
                display_format = "text/html"
                CreateManifest = "CREATE FILE: manifest.html"
            } )
            If ( $oReq ) {
                If ( $oReq.StatusCode -eq 200 ) {
                    $htmlOut = $oReq.Content
                }
            }
        }

        If ( -Not $htmlOut ) {
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
        }

        $htmlOut | Write-Output

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
            $Path | Get-LOCKSSManifestHTML -Title:$Title -TitlePrefix:$TitlePrefix | Out-File -FilePath ( $UNC | Get-LOCKSSManifestPath ) -NoClobber:(-Not $Force) -Encoding utf8
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
    
    # Is there a PowerShell script in this item's .coldstorage directory?
    $PropsDirs = ( $File | Get-ItemPropertiesDirectoryLocation -Name ".coldstorage" -Order Highest -All )
    $ADPNetScripts = ( $PropsDirs | Join-Path -ChildPath "to-adpnet*.ps1" | Get-ChildItem )

    If ( $ADPNetScripts.Count -gt 0 ) {
        $Consumed = 0
        $ADPNetScripts |% { $Script = $_; $OriginalTitle = $oFile.Name ; $Title = $OriginalTitle ; If ( -Not $Consumed ) { $Title = ( $Title | & "${Script}" get au title -Package $oFile -Original "${OriginalTitle}" ); $Consumed = $LastExitCode; }  }
    }
    Else {
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

                    $sSlug = $oFile.Name -replace $Process
                    $sPapa = ( ( ( $oFile | Split-Path -Parent) | Split-Path -Leaf ) -replace $Process )
                    $sPapaSlug = "${sPapa} ${sSlug}" 
                    $Title = ( $Pattern -f ( $sSlug, $sPapaSlug ) )
                }

            }
        }
    }
    
    If ( $Title ) {
        $Title | Write-Output
    }
}

}

Function Get-ADPNetAUUrlFromObject {
Param ( [Parameter(ValueFromPipeline=$true)] $Packet, $Property="au_start_url", $Parameters=@{}, $Context="object" )

    Begin { $cmdContext = $MyInvocation.MyCommand }

    Process {
        ( "[${cmdContext}] URL parsed from {0}, key='{1}'" -f $Context, $Property ) | Write-Debug
        
        $uri = [uri] ( $Packet.$Property )
        $uri | Add-Member -MemberType NoteProperty -Name "PacketSource" -Value $Property
        $uri | Add-Member -MemberType NoteProperty -Name "PluginSource" -Value $Parameters[$Property]

        $uri | Write-Output
    }

    End {
    }

}


Function Get-ADPNetAUUrl {
Param ( [Parameter(ValueFromPipeline=$true)] $Block, $Key="au_start_url" )

    Begin { $cmdContext = $MyInvocation.MyCommand }

    Process {

        $Out = @()
        $Packet = $null
        $PacketContext = $null

        If ( $Block -is [uri] ) {
            $Out += @( $Block )
        }
        ElseIf ( $Block -is [string] ) {
            $Packet = $null
            Try {
                $Packet = ( $Block | ConvertFrom-ADPNetJsonPacket )
                $PacketContext = "JSON"
            }
            Catch {
                Write-Debug ( "[${cmdContext}] JSON parsing failed; fallback to simple [uri] cast on '{0}'" -f $Block )
                $Out += ( [uri] $Block )
            }
        }
        ElseIf ( $Block -is [Hashtable] ) {
            $Packet = [PSCustomObject] $Block
            $PacketContext = "hashtable"
        }
        Else {
            Write-Warning ( "[${cmdContext}] Could not determine URI from {0} input." -f $Block.GetType().Name )
        }

        If ( $Packet ) {
            $sPluginJar = $Packet."Plugin JAR"
            If ( $sPluginJar ) {
                $pluginParams = ( $sPluginJar | Get-ADPNetPlugins | Get-ADPNetPluginDetails )
            }

            $Packet | Get-Member -MemberType NoteProperty |% { If ( $_.Name -like $Key ) { $_.Name } } |% {
                $Out += @( $Packet | Get-ADPNetAUUrlFromObject -Property:$_ -Parameters:$pluginParams -Context:$PacketContext )
            }
        }


        $Out | Write-Output

    }

    End { }

}

Function Get-ADPNetAUTable {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $ForService=$false )

    Begin { }

    Process {
        If ( $File -is [Hashtable] ) {
            $File
        }
        Else {
            $auParams = @{}

            $sAUTitle = ( $File | Get-ADPNetAUTitle )
            $sInstitution = ( Get-ColdStorageSettings -Name "Institution" )

            $sPluginJar = ( Get-ColdStorageSettings -Name "ADPNet-Plugin-Jar" )
            $oPackage = ( $File | Get-ItemPackage -Recurse -ShowWarnings:$ShowWarnings )

            $nBytes = $oPackage.CSPackageFileSize
            $nFiles = $oPackage.CSPackageContents
            $sFileSizeReadable = ( "{0}" -f ( $nBytes | Format-BytesHumanReadable ) )

            $sFileSizeBytes = ( "{0:N0} byte{1}" -f $nBytes,$( If ( $nBytes -ne 1 ) { "s" } Else { "" } ) )
            $sFileSizeFiles = ( "{0:N0} file{1}" -f $nFiles,$( If ( $nFiles -ne 1 ) { "s" } Else { "" } ) )
            $sFileSize = ( "{0} ({1}, {2})" -f $sFileSizeReadable,$sFileSizeBytes,$sFileSizeFiles )

            $Book = ( $File | Get-ADPNetStartUrl -Parameterize )
            $pluginParams = ( $sPluginJar | Get-ADPNetPlugins | Get-ADPNetPluginDetails -Interpolate:$Book )

            $auParams['Start URL'] = ( $pluginParams["au_start_url"] |% { $_ } )
            $auParams['Manifest URL'] = ( $pluginParams['au_manifest'] |% { $_ } )

            $auParams['Ingest Step'] = 'staged' # FIXME: stub this for now, maybe make configurable later
            $auParams['Ingest Report'] = ( $File | Get-ADPNetReportURL )

            $auParams['From Peer'] = ( Get-ColdStorageSettings -Name "ADPNet-Node" )
            $auParams['To Peer'] = $null # FIXME: stub this for the moment, maybe make configurable later

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

            If ( $ForService ) {
                $hashAU['Institution Code'] = ( Get-DropServerUser )
                $hashAU['Institution Name'] = ( "{0} ({1})" -f $sInstitution,( $auParams['From Peer'] ) )
                $hashAU['AU Title'] = $sAUTitle
                $hashAU['AU Directory'] = $Book["directory"]
                $hashAU['Drop Server'] = $Book["base_url"]
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

            $auParams.Keys |% {
                If ( $auParams[$_] ) {
                    $hashAU[$_] = $auParams[$_]
                }
            }

            $hashAU
        }
    }

    End { }

}

Function Write-ADPNetAUReportKeyValuePair {
Param ( [Parameter(ValueFromPipeline=$true)] $Key, $Table=$null, $Value=$null )

    Begin { }
    
    Process {
        $Value = $( If ( $Table -eq $null ) { $Value } ElseIf ( $Table.ContainsKey($Key) ) { $Table[$Key] } )
        If ( ( -Not ( $Key -match "(.*)_(.*)" ) ) -And ( $Value -is [String] ) ) {
            ("{0,-15} `t{1}" -f ( $Key.ToUpper() + ':' ), $Value)
        }
    }

    End { }

}

Function Write-ADPNetAUReport {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [string] $Output="Text" )

    Begin { }

    Process {
        $hashAU = ( $File | Get-ADPNetAUTable )
        $jsonPacket = ($hashAU | ConvertTo-Json -Compress)

        If ( $Output -eq "JSON" ) {
            ( "{0}" -f $jsonPacket )
        }
        Else {
            $group0 = @( 'Ingest Title', 'File Size', 'From Peer', 'To Peer' )
            $group1 = @( 'Plugin JAR', 'Plugin ID', 'Plugin Name', 'Plugin Version' )
            $group2 = @( 'Start URL', 'Manifest URL', 'Ingest Step', 'Ingest Report' )
            $group3 = $( $hashAU.Keys |% { If ( -Not ( ($group0+$group1+$group2+$group3) -ieq $_ ) ) { $_ } } )
            $group4 = @( 'JSON Packet' )
            "INGEST INFORMATION AND PARAMETERS:"
            "----------------------------------"
            $group0 | Write-ADPNetAUReportKeyValuePair -Table:$hashAU
            $group1 | Write-ADPNetAUReportKeyValuePair -Table:$hashAU
            $group2 | Write-ADPNetAUReportKeyValuePair -Table:$hashAU
            $group3 | Write-ADPNetAUReportKeyValuePair -Table:$hashAU
            ""
            $group4 | Write-ADPNetAUReportKeyValuePair -Value:$jsonPacket
            ""
        }
    }

    End { }

}

Function Add-ADPNetAUReport {
Param ( [Parameter(ValueFromPipeline=$true)] $AU, $LocalFolder, $WhatIf )

    Begin { }

    Process {
        $TempFile = New-TemporaryFile

        $AU | Write-ADPNetAUReport | Out-File -LiteralPath $TempFile.FullName -Encoding utf8
        #$AU | Write-ADPNetAUUrlRetrievalTest | Out-File -LiteralPath $TempFile.FullName -Append -Encoding utf8

        # Upload output to SFTP repository with an appropriate file name, to be pulled down on the preservation node.
        $TempFile | Set-DropServerAUReport -LocalFolder:$LocalFolder -WhatIf:$WhatIf

        # Tee output also to standard output for user reference, possible redirection
        Get-Content -LiteralPath $TempFile.FullName | Write-Output

        Remove-Item $TempFile
    }

    End { }

}

Function ConvertFrom-ADPNetJsonPacket {
Param ( [Parameter(ValueFromPipeline=$true)] $Block )

    Begin { $cmdContext = $MyInvocation.MyCommand }

    Process {
        $JSON = ( $Block -replace '^JSON\s*PACKET:\s*(\{)','$1' )
        
        ( $JSON | ConvertFrom-Json )
    }

    End { }
}

Function Get-SSHCredentials {
Param ( [Parameter(ValueFromPipeline=$true)] $Identity )

    Begin { }

    Process {
        $sUser = ( $Identity | Get-DropServerHostElements ).User
        $aKeys = @()
        $oKeyFiles = ( Get-ColdStorageSettings -Name "SSH-ID" )

        If ( $oKeyFiles ) {
            $oKeyFiles | Get-Member -MemberType NoteProperty -Name $Identity |% {
                $PropName = $_.Name
                $aKeys += @( $oKeyFiles.$PropName | ConvertTo-ColdStorageSettingsFilePath )
            }
            $aUserHost = ( $Identity -split "[@]",2 )
            $sUser = $aUserHost[0]
        }
        
        $oCredentials = [PSCustomObject] @{}
        $sUser |% { $oCredentials | Add-Member -MemberType NoteProperty -Name "User" -Value $_ }
        $aKeys |% { $oCredentials | Add-Member -MemberType NoteProperty -Name "Key" -Value $_ }
        
        $oCredentials
    }

    End { }

}

Function Get-ArrayReversed {
Param ( $List )

    $Copy = $List
    [Array]::Reverse( $Copy )
    $Copy

}

Function Get-DropServerHostElements {
Param ( [Parameter(ValueFromPipeline=$true)] $Authority )

    Begin { }

    Process {
        $sHost, $sUser = Get-ArrayReversed( $Authority -split "[@]", 2 )
        $sHost, $sPort = ( $sHost -split "[:]",2 )
        $sUser, $sPass = ( $sUser -split "[:]",2 )

        $Elements = New-Object -TypeName PSCustomObject
        $sHost |% { If ( $_ ) { $Elements | Add-Member -MemberType NoteProperty -Name "Host" -Value $_ } }
        $sPort |% { If ( $_ ) { $Elements | Add-Member -MemberType NoteProperty -Name "Port" -Value $_ } }
        $sUser |% { If ( $_ ) { $Elements | Add-Member -MemberType NoteProperty -Name "User" -Value $_ } }
        $sPass |% { If ( $_ ) { $Elements | Add-Member -MemberType NoteProperty -Name "Password" -Value $_ } }

        $Elements
    }

    End { }
}

Function Get-DropServerHostString {
Param ( [Parameter(ValueFromPipeline=$true)] $Elements )

    Begin { }

    Process {
        $sTemplate = ( "{0}" -f $Elements.Host )
        If ( $Elements.Port ) {
            $sTemplate = ( "{0}:{1}" -f $sTemplate,$Elements.Port )
        }
        If ( $Elements.User ) {
            $sTemplate = ( "{0}@{1}" -f $Elements.User,$sTemplate )
        }
        $sTemplate
    }

    End { }
}

Function Get-DropServerTunnel {
Param ( [Parameter(ValueFromPipeline=$true)] $URI )

    Begin { }

    Process {
        Get-ColdStorageSettings -Name "Drop-Server-Tunnel" |% {
            If ( $_ ) {
                $LocalPoint, $RemotePoint = ( $_ -split "[|]",2 )
                $MediumPoint, $RemotePoint = ( $RemotePoint -split "[,]",2 )
            
                If ( $LocalPoint ) { $LocalPoint = $LocalPoint.Trim() }
                If ( $MediumPoint ) { $MediumPoint = $MediumPoint.Trim() }
                If ( $RemotePoint ) { $RemotePoint = $RemotePoint.Trim() }

                $aHosts = @{
                    "Local"=( $LocalPoint | Get-DropServerHostElements );
                    "Medium"=( $MediumPoint | Get-DropServerHostElements );
                    "Remote"=( $RemotePoint | Get-DropServerHostElements )
                }

                $Triad = New-Object -TypeName PSCustomObject
                $aHosts.Keys |% { If ( $aHosts[$_] ) { $Triad | Add-Member -MemberType NoteProperty -Name $_ -Value $aHosts[$_] } }

                $Triad
            }
        }
    }

    End { }
}

Function New-DropServerTunnel {
Param ( [Parameter(ValueFromPipeline=$true)] $Tunnel )

    Begin { }

    Process {
        $oTunnel = $null
        If ( ( $Tunnel -is [string] ) -or ( $Tunnel -is [uri] ) ) {
            $oTunnel = ( $Tunnel | Get-DropServerTunnel )
        }
        ElseIf ( $Tunnel | Get-Member -MemberType NoteProperty -Name "Medium" ) {
            $oTunnel = $Tunnel
        }
        Else {
            Write-Error "[${context}] Could not determine tunnel definition from parameter:"
            Write-Error $Tunnel
        }

        If ( $oTunnel ) {
            
            $sId = ( $oTunnel.Medium | Get-DropServerHostString )
            $sRemote = ( $oTunnel.Remote | Get-DropServerHostString )
            $oCreds = ( $oTunnel.Medium | Get-DropServerHostString | Get-SSHCredentials )

            $sCredentialPrompt = ( "Open tunnel to {0} via {1}. SSH credentials for {2}:" -f $sRemote,$sId,$( If ( $oCreds.Key ) { $oCreds.Key } Else { $sID } ) )
            $sshCredential = ( Get-Credential -UserName:($oCreds.User) -Message $sCredentialPrompt )

            If ( $sshCredential ) {
                Write-Debug "Establishing SSH connection to ${sId}"
                If ( $oTunnel.Medium.Port ) {

                    If ( $oCreds.Key ) {
                        $tunnelSession = ( New-SSHSession -ComputerName:$oTunnel.Medium.Host -Port:($oTunnel.Medium.Port) -Credential:$sshCredential -KeyFile:($oCreds.Key) )
                    }
                    Else {
                        $tunnelSession = ( New-SSHSession -ComputerName:$oTunnel.Medium.Host -Port:($oTunnel.Medium.Port) -Credential:$sshCredential )
                    }

                }
                Else {

                    If ( $oCreds.Key ) {
                        $tunnelSession = ( New-SSHSession -ComputerName:$oTunnel.Medium.Host -Credential:$sshCredential -KeyFile:($oCreds.Key) )
                    }
                    Else {
                        $tunnelSession = ( New-SSHSession -ComputerName:$oTunnel.Medium.Host -Credential:$sshCredential )
                    }

                }


                If ( $tunnelSession.Connected ) {
                    Write-Debug "Opening SSH tunnel to ${sRemote}"
                    $aKeyFiles = ( Get-ColdStorageSettings -Name "SSH-ID" )
                    New-SSHLocalPortForward -SessionId:( $tunnelSession.SessionId ) -BoundHost:$oTunnel.Local.Host -BoundPort:$oTunnel.Local.Port -RemoteAddress:$oTunnel.Remote.Host -RemotePort:$oTunnel.Remote.Port
                }

                $tunnelSession
            }
        }
    }

    End { }
}


Function Get-DropServerHTTPProxy {
Param ( [Parameter(ValueFromPipeline=$true)] $URI )

    Begin { }

    Process {
        $Proxy = ( Get-ColdStorageSettings -Name "Drop-Server-Proxy" )
        If ( -Not $Proxy ) {
            # Try to get an implicit proxy address from the Drop-Server-Tunnel setting
            $dropTunnel = ( $URI | Get-DropServerTunnel )
            If ( $dropTunnel ) {
                $asURLParts = @( "http:", "", ( $dropTunnel.Local | Get-DropServerHostString ), "" )
                $Proxy = ( $asURLParts -join "/" )
            }
        }
        $Proxy
    }

    End { }

}

Function Invoke-ADPNetAUUrlRetrievalTest {
Param ( [Parameter(ValueFromPipeline=$true)] $URI )

    Begin {
        $cmdContext = $MyInvocation.MyCommand

        $dropTunnel = ( $URI | Get-DropServerTunnel )
        $tunnelSession = $null

        If ( $dropTunnel ) {
            $tunnelSession = ( $dropTunnel | New-DropServerTunnel )
        }

    }

    Process {
        Write-Debug ( "[$cmdContext] Retrieve URI: {0}" -f $URI )

        $Proxy = ( Get-DropServerHTTPProxy )
        Try {
            $HttpResponse = ( Invoke-WebRequest -UseBasicParsing -Uri:$URI -Proxy:$Proxy ) # N.B.: $Proxy may be $null
        }
        Catch {
            $HttpErrorMessage = [PSCustomObject] @{ "StatusDescription"=( $_.Exception.Message ); "StatusCode"=( 0 ) }
            If ($_.FullyQualifiedErrorId -like "WebCmdletWebResponseException*") {
                $HttpResponse = ( $_.Exception.Response )

                # HTTP Response will be $null if the connection was not made or failed in some way;
                # filled if it returned an HTTP error response
            }
        }

        $HttpRequest = (@{} | Select-Object @{ n="URI"; e={ $URI }}, @{ n="Proxy"; e={ $Proxy }})
        If ( $HttpResponse ) {
            $HttpResponse | Add-Member -MemberType NoteProperty -Name Request -Value $HttpRequest    
            $HttpResponse
        }
        Else {
            $HttpErrorMessage | Add-Member -MemberType NoteProperty -Name Request -Value $HttpRequest    
            $HttpErrorMessage
        }

    }

    End {

        If ( $tunnelSession ) {
            If ( $tunnelSession.Connected ) {
                Write-Debug ( "Closing ssh session # {0}" -f $tunnelSession.sessionId )
                $tunnelSession.Disconnect()
                Remove-SSHSession $tunnelSession
            }
        }

    }

}

Function Write-ADPNetAUUrlRetrievalTest {
Param ( [Parameter(ValueFromPipeline=$true)] $Block, $Key="*_url", [switch] $ShowWarnings=$false, [switch] $ShowErrors=$false, [switch] $ReturnObject=$false, [switch] $NoHeader=$false )

    Begin {
        $context = $MyInvocation.MyCommand

        If ( ( -Not $ReturnObject ) -And ( -Not $NoHeader ) ) {
            "URL RETRIEVAL TESTS:"
            "--------------------"
        }
    }

    Process {

        $Response = ( $Block | Get-ADPNetAUUrl -Key:$Key | Invoke-ADPNetAUUrlRetrievalTest )

        $Code = $Response.StatusCode.ToInt32([CultureInfo]::InvariantCulture)

        $UrlKey = $Response.Request.URI.PacketSource
        $FullUrl = $Response.Request.URI.ToString()
        $UrlTemplate = $Response.Request.URI.PluginSource

        $SideMessage = $null
        $SideStream = $null
        If ( $Code -ge 200 -and $Code -lt 300 ) {
            $OK = $true
        }
        ElseIf ( $Code -ge 300 -and $Code -lt 400 ) {
            $OK = $true
            $SideMessage = ( "[{0}] HTTP redirection response {1} from {2} <{3}>: '{4}'" -f $context, $Code, $UrlKey, $FullUrl, $Response.StatusDescription )
            $SideStream = $( If ( $ShowWarnings ) { "Write-Warning" } )
        }
        ElseIf ( $Code -ge 400 ) {
            $OK = $false
            $SideMessage = ( "[{0}] HTTP failure response {1} from {2} <{3}>: '{4}'" -f $context, $Code, $UrlKey, $FullUrl, $Response.StatusDescription )
            $SideStream = $( If ( $ShowErrors ) { "Write-Error" } ElseIf ( $ShowWarnings ) { "Write-Warning" } )
        }
        ElseIf ( $Code -eq 0 ) {
            $OK = $false
            $SideMessage = ( "[{0}] HTTP request failure from {1} <{2}>: '{3}'" -f $context, $UrlKey, $FullUrl, $Response.StatusDescription )
            $SideStream = $( If ( $ShowErrors ) { "Write-Error" } ElseIf ( $ShowWarnings ) { "Write-Warning" } )
        }
        
        If ( $SideMessage -and $SideStream ) {
            $SideMessage | & $SideStream
        }

        $Obj = ( [PSCustomObject] @{ "Code"=$Code; "Description"=$Response.StatusDescription; "Parameter"=$UrlKey; "Url"=$FullUrl; "UrlTemplate"=$UrlTemplate } )

        If ( $ReturnObject ) {
            $Obj
        }
        Else {
            ( $Obj | Get-Member -MemberType NoteProperty |% { $Prop = $_.Name ; $Obj.$Prop } ) -join " `t"
        }

    }

    End { }
}

#############################################################################################################
## PUBLIC FUNCTIONS: TRANSFER LOCKSS ARCHIVAL UNTIS (AUs) TO DROP SERVER VIA SFTP ###########################
#############################################################################################################

Function Add-ADPNetAUToDropServerStagingDirectory {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $WhatIf=$false )

    Begin { }

    Process {

        $Location = ( Get-Item -LiteralPath $File )
            
        $sLocation = $Location.FullName

        If ( -Not ( $Location | Get-LOCKSSManifest ) ) {

            $sTitle = ( $Location | Get-ADPNetAUTitle )
            If ( -Not $sTitle ) {
                $sTitle = ( Read-Host -Prompt "AU Title [${Location}]" )
            }

            Add-LOCKSSManifestHTML -Directory $File -Title $sTitle -Force:$Force -WhatIf:$WhatIf

        }

        ( $Location | Set-DropServerFolder -WhatIf:$WhatIf )

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
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $WhatIf=$false )

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
                    $oFile | Sync-DropServerAU -SFTPSession:$session -RemoteRepository:$RemoteRoot -WhatIf:$WhatIf
                }
                Else {
                    Write-Verbose "[drop:$sFile] not yet staged; add local copy"
                    $oFile | Add-DropServerAU -SFTPSession:$session -RemoteRepository:$RemoteRoot -WhatIf:$WhatIf
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

Function Set-DropServerAUReport {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $LocalFolder, [switch] $WhatIf=$false )

    Begin { $session = ( New-DropServerSession ) }

    Process {

        $oFile = ( Get-FileObject -File $File )
        $sFile = $oFile.FullName

        $oFolder = ( Get-FileObject -File $LocalFolder )
        $sFolder = $oFolder.FullName

        If ( $session ) {

            $RemoteRoot = "/drop_au_content_in_here"
            Set-SFTPLocation -SessionId $session.SessionId -Path "${RemoteRoot}"

            $RemoteDestination = ( $oFolder | Get-ADPNetReportFileName )
            If ( $Force -Or ( -Not ( Test-SFTPPath -SFTPSession:$session -Path:$RemoteDestination ) ) ) {
                Write-Verbose "[adpnet:$RemoteDestination] not yet staged; add local copy"
                $oFile | Add-DropServerAUReport -LocalFolder:$LocalFolder -SFTPSession:$session -WhatIf:$WhatIf
            }
            Else {
                # Already uploaded; throw a warning
                Write-Warning "[adpnet:$RemoteDestination] already exists; use -Force to overwrite"
            }
        }
        Else {

            Write-Warning "[adpnet:$sFolder]: SFTP connection failed -- could not upload AU report."
            Write-Error $session

        }

            
    }

    End {
        If ( $session ) {
            $removed = ( Remove-SFTPSession -SessionId $session.SessionId )
        }
    }

}

Function Add-DropServerAUReport {
    Param ( [Parameter(ValueFromPipeline=$true)] $ReportFile, $LocalFolder, $SFTPSession, $RemoteRepository=$null, [switch] $WhatIf=$false )

    Begin {
    
        If ( $RemoteRepository -eq $null ) {
            $RemoteRepository = Get-SFTPLocation -SFTPSession:$SFTPSession
        }

    }

    Process {
        $oLocalFolder = Get-FileObject($LocalFolder)
        $sLocalFullName = $oLocalFolder.FullName
        $sRemotePath = ("{0}/{1}" -f $RemoteRepository,( $oLocalFolder | Get-ADPNetReportFileName ))

        $oReportFile = Get-FileObject($ReportFile)
        $sReportFile = $oReportFile.FullName

        If ( -Not $WhatIf ) {
            $Item = ( New-SFTPItem -SFTPSession:$SFTPSession -Path:$sRemotePath -ItemType:File )
            $Content = ( Set-SFTPContent -SFTPSession:$SFTPSession -Path:($Item.FullName) -Value:( Get-Content -Raw -LiteralPath $sReportFile ) )
        }
        Else {
            ( "WhatIf: {0} -SFTPSession:{1} -Path:{2} -Destination:{3}" -f "Set-SFTPItem",$SFTPSession,$sLocalFullName,$sRemotePath )
        }
    }

    End { }

}

Function Add-DropServerAU {
    Param ( [Parameter(ValueFromPipeline=$true)] $LocalFolder, $SFTPSession, $RemoteRepository, [switch] $WhatIf=$false )

    Begin { }

    Process {
        $sLocalFullName = $LocalFolder.FullName
        $sRemotePath = ( $LocalFolder | Get-ADPNetStartDir )
        If ( -Not $WhatIf ) {
            Set-SFTPFolder -SessionId:($SFTPSession.SessionId) -LocalFolder:$sLocalFullName -RemotePath:$sRemotePath
        }
        Else {
            ( "WhatIf: {0} -SessionId:{1} -LocalFolder:{2} -RemotePath:{3}" -f "Set-SFTPFolder",$SFTPSession.SessionId,$sLocalFullName,$sRemotePath )
        }
    }

    End { }

}

Function Sync-DropServerAU {
Param ( [Parameter(ValueFromPipeline=$true)] $LocalFolder, $SFTPSession, $RemoteRepository, [switch] $WhatIf )

Begin { }

Process {
    $RemoteDestination = ( $LocalFolder | Get-ADPNetStartDir )
    Get-SFTPChildItem -SessionId:($SFTPSession.SessionId) -Path:$RemoteRepository |% {

        If ( $_.Name -ieq "${RemoteDestination}" ) {
            $RemoteBase = $_
        }

    }

    $aChecklist = @{}
    Get-ChildItem -Recurse -LiteralPath $LocalFolder.FullName |% {
        $RemoteFile = ( $_ | Get-ADPNetFileRemotePath -Session:$session -LocalBase:$LocalFolder -RemoteBase:$RemoteBase )
        $aChecklist[$_.FullName] = $RemoteFile
    }

    Get-SFTPChildItem -SessionId $session.SessionId -Recursive -Path $RemoteDestination |% {
        $RemoteFile = $_
        $LocalFile = ( $_ | Get-ADPNetFileLocalPath -Session:$session -LocalBase:$LocalFolder -RemoteBase:$RemoteBase )
        $aChecklist[$LocalFile] = $RemoteFile
    }

    $aChecklist.Keys |% {
        $LocalFile = Get-FileObject($_)
        $RemoteFile = $aChecklist[$_]
        If ( $RemoteFile -is [string] ) {
            $RemoteFileName = $RemoteFile
        }
        Else {
            $RemoteFileName = $RemoteFile.FullName
        }
        
        $RemoteAttr = Get-SFTPPathAttribute -SessionId $session.SessionId -Path $RemoteFileName -ErrorAction SilentlyContinue
        Write-Debug ( "COMPARE: {0} <-> `t{1}" -f $LocalFile, $RemoteFileName )
            
        $LocalLength = $( If ( $LocalFile ) { $LocalFile.Length } Else { $null } )
        $LocalLastWrite = $( If ( $LocalFile ) { $LocalFile.LastWriteTime } Else { $null } )
        $LocalIsRegular = $( If ( $LocalFile ) { Test-Path -LiteralPath $LocalFile.FullName -PathType Leaf } Else { $null } )

        $RemoteLength = $( If ( $RemoteAttr ) { $RemoteAttr.Size } Else { 0 } )
        $RemoteLastWrite = $( If ( $RemoteAttr ) { $RemoteAttr.LastWriteTime } Else { $null } )
        $RemoteIsRegular = $( If ( $RemoteAttr ) { $RemoteAttr.IsRegularFile } Else { $null } )

        $WrittenLater = ( $LocalLastWrite -gt $RemoteLastWrite )
        $SizesDiffer = ( $LocalLength -ne $RemoteLength )

        If ( $LocalIsRegular -or $RemoteIsRegular ) {
            If ( $WrittenLater -or $SizesDiffer ) {
                $RemotePath = ( $RemoteFileName -split "/" )
                $RemoteParent = ( $RemotePath[0..($RemotePath.Count-2)] ) -join "/"

                $FileName = $( If ($LocalFile) { $LocalFile.Name } Else { $RemotePath[-1] } )
                
                ( "${FileName} differs. Local copy: {0:N0} B ({1}); Remote: {2:N0} B ({3})" -f ($LocalLength, $LocalLastWrite, $RemoteLength, $RemoteLastWrite)) | Write-Warning

                If ( $LocalIsRegular ) {
                    If ( -Not $WhatIf ) {
                        Set-SFTPItem -SFTPSession:$session -Path:($LocalFile.FullName) -Destination:($RemoteParent) -Force -Verbose
                    }
                    Else {
                        ( 'WhatIf: {0} -SFTPSession:$session -Path:{1} -Destination:{2} -Force -Verbose' -f "Set-SFTPItem",($LocalFile.FullName),($RemoteParent) )
                    }
                }
                ElseIf ( $RemoteIsRegular ) {
                    If ( -Not $WhatIf ) {
                        Remove-SFTPItem -SFTPSession:$session -Path:$RemoteFileName -Force -Verbose
                    }
                    Else {
                        ( 'WhatIf: {0} -SFTPSession:$session -Path:{1} -Force -Verbose' -f "Remove-SFTPItem",$RemoteFileName )
                    }
                }
            }
        }
    }

}

End { }
}

Function Get-ADPNetFileRemotePath {
Param ( [Parameter(ValueFromPipeline=$true)] $LocalFile, $Session, $LocalBase, $RemoteBase )

    Begin { }

    Process {
        $reLocalBase = [Regex]::Escape($LocalBase.FullName + '\')
        $localRelative = ( $LocalFile.FullName -replace "^${reLocalBase}","" ) -replace '[\\]','/'
        $RemotizedFileName = ( $RemoteBase.FullName + "/${localRelative}" )

        $RemotizedFileName
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
        ( Get-Item -Force -LiteralPath $LocalizedFileName ).FullName | Write-Output
    }
    Else {
        $LocalizedFileName | Write-Output
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
        $OutputName = ( "{0}.zip" -f ( $oJAR.Name -replace "[^A-Za-z0-9]+","-" ) )
        $sZip = ( $Destination.FullName | Join-Path -ChildPath $OutputName )

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

Export-ModuleMember -Function Get-SSHCredentials

Export-ModuleMember -Function Add-ADPNetAUToDropServerStagingDirectory
Export-ModuleMember -Function New-DropServerSession
Export-ModuleMember -Function Set-DropServerFolder
Export-ModuleMember -Function Add-DropServerAU
Export-ModuleMember -Function Sync-DropServerAU
Export-ModuleMember -Function Get-ADPNetFileRemotePath
Export-ModuleMember -Function Get-ADPNetFileLocalPath

Export-ModuleMember -Function Get-ADPNetAUTitle
Export-ModuleMember -Function Get-ADPNetAUTable
Export-ModuleMember -Function Write-ADPNetAUReport
Export-ModuleMember -Function Get-ADPNetAUUrl
Export-ModuleMember -Function Invoke-ADPNetAUUrlRetrievalTest 
Export-ModuleMember -Function Write-ADPNetAUUrlRetrievalTest

Export-ModuleMember -Function Get-DropServerHostElements
Export-ModuleMember -Function Get-DropServerHostString
Export-ModuleMember -Function Get-DropServerTunnel
Export-ModuleMember -Function Get-DropServerHTTPProxy

Export-ModuleMember -Function Get-ADPNetADPNet
Export-ModuleMember -Function Get-ADPNetStartDir
Export-ModuleMember -Function Get-ADPNetStartURL
Export-ModuleMember -Function Get-LOCKSSManifestPath
Export-ModuleMember -Function Get-LOCKSSManifest
Export-ModuleMember -Function Get-LOCKSSManifestHTML
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

Export-ModuleMember -Function Add-ADPNetAUReport
Export-ModuleMember -Function Get-ADPNetReportFileName
Export-ModuleMember -Function Get-ADPNetReportURL
Export-ModuleMember -Function Set-DropServerAUReport
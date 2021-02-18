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

#############################################################################################################
## DATA #####################################################################################################
#############################################################################################################

$ColdStorageData = "\\ADAHColdStorage\ADAHDATA"
$ColdStorageDataER = "${ColdStorageData}\ElectronicRecords"
$ColdStorageDataDA = "${ColdStorageData}\Digitization"
$ColdStorageER = "\\ADAHColdStorage\ElectronicRecords"
$ColdStorageDA = "\\ADAHColdStorage\Digitization"
$ColdStorageBackup = "\\ADAHColdStorage\Share\ColdStorageMirroredBackup"

$mirrors = @{
    Processed=( "ER", "\\ADAHFS3\Data\Permanent", "${ColdStorageDataER}\Processed" )
    Unprocessed=( "ER", "\\ADAHFS1\PermanentBackup\Unprocessed", "${ColdStorageDataER}\Unprocessed" )
    Working_ER=( "ER", "${ColdStorageDataER}\Working-Mirror", "\\ADAHFS3\Data\ArchivesDiv\PermanentWorking" )
    Masters=( "DA", "${ColdStorageDataDA}\Masters", "\\ADAHFS3\Data\DigitalMasters" )
    Access=( "DA", "${ColdStorageDataDA}\Access", "\\ADAHFS3\Data\DigitalAccess" )
    Working_DA=( "DA", "${ColdStorageDataDA}\Working-Mirror", "\\ADAHFS3\Data\DigitalWorking" )
}
$RepositoryAliases = @{
    Processed=( "${ColdStorageER}\Processed", "${ColdStorageDataER}\Processed" )
    Working_ER=( "${ColdStorageER}\Working-Mirror", "${ColdStorageDataER}\Working-Mirror" )
    Unprocessed=( "${ColdStorageER}\Unprocessed", "${ColdStorageDataER}\Unprocessed" )
    Masters=( "${ColdStorageDA}\Masters", "${ColdStorageDataDA}\Masters" )
    Access=( "${ColdStorageDA}\Access", "${ColdStorageDataDA}\Access" )
    Working_DA=( "${ColdStorageDA}\Working-Mirror", "${ColdStorageDataDA}\Working-Mirror" )
    
}

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Get-ColdStorageRepositories () {
    $mirrors
}

Function Get-ColdStorageLocation {
Param ( $Repository )

    $aRepo = $mirrors[$Repository]

    If ( ( $aRepo[1] -Like "${ColdStorageER}\*" ) -Or ( $aRepo[1] -Like "${ColdStorageDA}\*" ) -Or ( $aRepo[1] -Like "${ColdStorageData}\*" ) ) {
        $aRepo[1]
    }
    Else {
        $aRepo[2]
    }
}

Function Get-ColdStorageZipLocation {
Param ( $Repository )

    $BaseDir = Get-ColdStorageLocation -Repository $Repository

    If ( Test-Path -LiteralPath "${BaseDir}\ZIP" ) {
        Get-Item -Force -LiteralPath "${BaseDir}\ZIP"
    }
}

Function Get-ColdStorageTrashLocation {
Param ( [Parameter(ValueFromPipeline=$true)] $Repository )

    Begin {
        $mirrors = ( Get-ColdStorageRepositories )
        
    }

    Process {
        If ( $Repository -ne $null ) {
            If ( $mirrors.ContainsKey($Repository) ) {
                $location = $mirrors[$Repository]
                $slug = $location[0]
            }
            Else {
                Write-Warning "Get-ColdStorageTrashLocation: Requested repository [{0}] does not exist." -f $Repository
            }
        }
        Else {
            Write-Warning "Get-ColdStorageTrashLocation: no valid repository found (null Repository parameter)"
        }

        "${ColdStorageBackup}\${slug}_${Repository}"
    }

    End { }
}

Function Get-FileRepositoryCandidates {
Param ( $Key, [switch] $UNC=$false )

    $mirrors = ( Get-ColdStorageRepositories )

    $repo = $mirrors[$Key][1..2]
    $aliases = $RepositoryAliases[$Key]

    ( $repo + $aliases) |% {
        $sTestRepo = ( $_ ).ToString()
        If ( $oTestRepo = Get-FileObject -File $sTestRepo ) {

            $sTestRepo # > stdout

            If ( -Not ( $UNC ) ) {
                $sLocalTestRepo = ( $oTestRepo | Get-LocalPathFromUNC ).FullName
                If ( $sTestRepo.ToUpper() -ne $sLocalTestRepo.ToUpper() ) {
                    $sLocalTestRepo # > stdout
                }
            }

        }
    }

}

Function Get-FileRepository {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $Slug=$false )

Begin { $mirrors = ( Get-ColdStorageRepositories ) }

Process {
    
    # get self if $File is a directory, parent if it is a leaf node
    $oDir = ( Get-ItemFileSystemLocation $File | Get-UNCPathResolved -ReturnObject )

    $oRepos = ( $mirrors.Keys |% {
        $sKey = $_;
        $oCands = ( Get-FileRepositoryCandidates -Key $_ );

        If ($oCands -ieq $oDir.FullName) {

            If ($Slug) { $sKey }
            Else { $oDir.FullName }
    } } )

    $oRepos
    If ( ( $oRepos.Count -lt 1 ) -and ( $oDir.Parent ) ) {
        $oDir.Parent | Get-FileRepository -Slug:$Slug
    }

}

End { }

}

Function Get-ColdStorageRepositoryDirectoryProps {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $oFile = Get-FileObject($File)
        $sContainer = $oFile.FullName
        If ( Test-Path -LiteralPath "${sContainer}\.coldstorage" -PathType Container ) {
            Get-ChildItem -LiteralPath "${sContainer}\.coldstorage" |% {
                If ( $_.Name -like "*.json" ) {
                    $Source = $_
                    $Source | Get-Content | ConvertFrom-Json |
                        Add-Member -PassThru -MemberType NoteProperty -Name Location -Value $oFile |
                        Add-Member -PassThru -MemberType NoteProperty -Name SourceLocation -Value ( $Source.Directory ) |
                        Add-Member -PassThru -MemberType NoteProperty -Name Source -Value ( $Source )
                }
            }
        }
    }

    End { }
}

Function Get-FileRepositoryProps {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $oFile = Get-FileObject($File)
        
        $Parent = $( If ( $oFile.Directory ) { $oFile.Directory } ElseIf ( $oFile.Parent ) { $oFile.Parent } )
        
        $Props = ( $Parent | Get-FileRepositoryProps )
        If ( $Props ) {
            $Props
        }
        Else {
            ( $oFile | Get-ColdStorageRepositoryDirectoryProps )
        }

    }

    End { }

}

Function Get-FileRepositoryLocation {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $Props = ( $File | Get-FileRepositoryProps )
        If ( $Props ) {
            $Props.Location
        }
    }

    End { }
}

Function Get-FileRepositoryName {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $Props = ( $File | Get-FileRepositoryProps )
        If ( $Props ) {
            $Props.Repository
        }
    }

    End { }
}

Function Get-FileRepositoryPrefix {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $Props = ( $File | Get-FileRepositoryProps )
        If ( $Props ) {
            $Props.Prefix
        }
    }

    End { }
}

Function New-ColdStorageRepositoryDirectoryProps {
Param ( [Parameter(ValueFromPipeline=$true)] $Table, $File, [switch] $Force = $false )

    $Props = ( $File | Get-ColdStorageRepositoryDirectoryProps )
    If ( $Props -and -Not ( $Force ) ) {
        Write-Warning "[coldstorage settle] This is already settled as a repository directory."
        $Props | Write-Warning
    }
    Else {
        $oFile = Get-FileObject($File)

        $Parent = $oFile.FullName
        $csName = ".coldstorage"
        $csDir = "${Parent}\${csName}"
        If ( Test-Path -LiteralPath "${csDir}" -PathType Container ) {
            $PropsDir = ( Get-Item -Force -LiteralPath "${csDir}" )
        }
        Else {
            $PropsDir = ( New-Item -ItemType Directory -Path "${Parent}" -Name "${csName}" -Verbose )
        }

        If ( $PropsDir ) {
            $sPropsDir = $PropsDir.FullName
            $Table | ConvertTo-Json > "${sPropsDir}\props.json"
            Get-Content "${sPropsDir}\props.json"
        }
        Else {
            "[coldstorage settle] Could not locate or create a props directory" | Write-Warning
        }
    }
}

Function Test-ColdStorageRepositoryPropsDirectory {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $oFile = Get-FileObject($File)

        $result = $false
        If ( $oFile.Name -eq ".coldstorage" ) {
            $Props = ( $oFile | Get-FileRepositoryProps )
            If ( $Props ) {

                If ( $oFile.FullName -eq $Props.SourceLocation.FullName ) {
                    $result = $true
                }

            }
        }

        $result | Write-Output
    }

    End { }
}

Function Test-ColdStorageRepositoryPropsFile {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $oFile = Get-FileObject($File)
        
        $result = $false

        If ( $oFile.Directory ) {
            If ( $oFile.Directory.Name -eq ".coldstorage" ) {
                $Props = ( $oFile | Get-FileRepositoryProps )
                If ( $Props ) {

                    If ( $oFile.FullName -eq $Props.Source.FullName ) {
                        $result = $true
                    }
                }
            }
        }

        $result

    }

    End { }
}

Export-ModuleMember -Function Get-ColdStorageRepositories
Export-ModuleMember -Function Get-ColdStorageLocation
Export-ModuleMember -Function Get-ColdStorageZipLocation
Export-ModuleMember -Function Get-ColdStorageTrashLocation
Export-ModuleMember -Function Get-FileRepository
Export-ModuleMember -Function Get-FileRepositoryName
Export-ModuleMember -Function Get-FileRepositoryPrefix
Export-ModuleMember -Function Get-FileRepositoryLocation
Export-ModuleMember -Function Get-FileRepositoryProps
Export-ModuleMember -Function Get-ColdStorageRepositoryDirectoryProps
Export-ModuleMember -Function New-ColdStorageRepositoryDirectoryProps
Export-ModuleMember -Function Test-ColdStorageRepositoryPropsDirectory
Export-ModuleMember -Function Test-ColdStorageRepositoryPropsFile

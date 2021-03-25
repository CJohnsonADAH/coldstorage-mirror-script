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

$global:gRepoLocsModuleCmd = $MyInvocation.MyCommand

Import-Module -Verbose:$false  $( My-Script-Directory -Command $global:gRepoLocsModuleCmd -File "ColdStorageSettings.psm1" )
Import-Module -Verbose:$false  $( My-Script-Directory -Command $global:gRepoLocsModuleCmd -File "ColdStorageFiles.psm1" )

#############################################################################################################
## DATA #####################################################################################################
#############################################################################################################

$ColdStorageData = "\\ADAHColdStorage\ADAHDATA"
$ColdStorageDataER = "${ColdStorageData}\ElectronicRecords"
$ColdStorageDataDA = "${ColdStorageData}\Digitization"
$ColdStorageER = "\\ADAHColdStorage\ElectronicRecords"
$ColdStorageDA = "\\ADAHColdStorage\Digitization"
$ColdStorageBackup = "\\ADAHColdStorage\Share\ColdStorageMirroredBackup"

$global:gColdStorageMirrors = @{
    Processed=( "ER", "\\ADAHFS3\Data\Permanent", "${ColdStorageDataER}\Processed", "${ColdStorageDataER}\Processed" )
    Unprocessed=( "ER", "\\ADAHFS1\PermanentBackup\Unprocessed", "${ColdStorageDataER}\Unprocessed", "${ColdStorageDataER}\Unprocessed" )
    Working_ER=( "ER", "${ColdStorageDataER}\Working-Mirror", "\\ADAHFS3\Data\ArchivesDiv\PermanentWorking", "${ColdStorageDataER}\Working-Mirror" )
    Masters=( "DA", "${ColdStorageDataDA}\Masters", "\\ADAHFS3\Data\DigitalMasters", "${ColdStorageDataDA}\Masters" )
    Access=( "DA", "${ColdStorageDataDA}\Access", "\\ADAHFS3\Data\DigitalAccess", "${ColdStorageDataDA}\Access" )
    Working_DA=( "DA", "${ColdStorageDataDA}\Working-Mirror", "\\ADAHFS3\Data\DigitalWorking", "${ColdStorageDataDA}\Working-Mirror" )
}
$mirrors = $global:gColdStorageMirrors
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

Function Get-ColdStorageRepositories {
Param ( $Groups=@(), $Repository=$null, [switch] $Tag=$false )

    Begin { }

    Process {
        $out = $global:gColdStorageMirrors

        If ( $Groups.Count -ge 1 ) {
        # Filter according to groups
            $filteredOut = @{}
            $out.Keys |% { $Key = $_; $row = $out[$Key]; If ( $Groups -ieq $row[0] ) { Write-Debug ( "FILTERED IN: {0}" -f $Key ); $filteredOut[$Key] = $row } Else { Write-Debug ( "FILTERED OUT: {0}" -f $Key ) } }
            $out = $filteredOut
        }

        If ( $Tag ) {
            $filteredOut = @{}
            $out.Keys |% {
                $Key = $_;
                $row = $out[$Key];
                $filteredOut[$Key] = (
                    @{} | Select-Object @{ n='Collection'; e={ $row[0] }},
                    @{ n='Locations'; e={
                        @{} | Select-Object @{ n='Reflection'; e={ $row[1] }},
                        @{ n='Original'; e={ $row[2] }},
                        @{ n='ColdStorage'; e={ $row[3] }}
                    }}
                )
            }
            $out = $filteredOut
        }

        If ( $Repository ) {
            $out = ( $out[$Repository] )
        }

        ( $out ) | Write-Output
    }

    End { }
}

Function Get-ColdStorageLocation {
Param ( [Parameter(ValueFromPipeline=$true)] $Repository, [switch] $ShowWarnings=$false )

    Process {
        If ( $Repository ) {
            If ( $mirrors.ContainsKey($Repository) ) {
                $aRepo = $mirrors[$Repository]

                If ( ( $aRepo[1] -Like "${ColdStorageER}\*" ) -Or ( $aRepo[1] -Like "${ColdStorageDA}\*" ) -Or ( $aRepo[1] -Like "${ColdStorageData}\*" ) ) {
                    $aRepo[1]
                }
                Else {
                    $aRepo[2]
                }
            }
            Else {
                $Mesg = ( "No such Repository: {0}" -f $Repository )
                If ( Test-Path -LiteralPath $Repository ) {
                    $FileType = $( If ( Test-Path -LiteralPath $Repository -PathType Container ) { "FOLDER" } Else { "FILE" } ) 
                    $Mesg = ( "{0} <-- THIS IS A {1} NAME, did you mean to use: -Items {2}` ?" -f $Mesg, $FileType, $Repository)
                }

                ( $Mesg ) | Write-Warning
            }
        }
        Else {
            ( "Repository name is empty." ) | Write-Warning
        }
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

Function Test-ColdStoragePropsDirectory {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $NoPackageTest=$false, [switch] $ShowWarnings=$false )

    Begin { }

    Process {
        $oFile = Get-FileObject($File)

        $result = $false
        If ( $oFile.Name -eq ".coldstorage" ) {
            $Packed = $( If ( $NoPackageTest ) { $null } Else { $oFile | Get-ItemPackage -Ascend -ShowWarnings:$ShowWarnings } )
            $result = ( -Not $Packed )
        }

        $result | Write-Output
    }

    End { }
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

#############################################################################################################
## PUBLIC FUNCTIONS: MIRRORED LOCATIONS #####################################################################
#############################################################################################################

Function Get-MirrorMatchedItem {
Param( [Parameter(ValueFromPipeline=$true)] $File, $Pair, [switch] $Original=$false, [switch] $Reflection=$false, [switch] $ColdStorage=$false, [switch] $Self=$false, [switch] $All=$false, $Repositories=$null )

Begin { $mirrors = ( Get-ColdStorageRepositories -Tag ) }

Process {
    
    If ( $Original ) { $Range = "Original" }
    ElseIf ( $Reflection ) { $Range = "Reflection" }
    ElseIf ( $ColdStorage ) { $Range = "ColdStorage" }
    Else { $Range = ( "Original", "Reflection" ) }

    If ( $Pair -eq $null ) {
        $Pair = ( Get-FileRepositoryName -File:$File )
        If ( $Pair.Length -gt 0 ) {
            Write-Debug ( "Adopted implicit Repository from item: {0}" -f ${Pair} )
        }
        Else  {
            Write-Warning ( "Cannot determine a Repository from item: {0}" -f $File.FullName )
        }
    }

    # get self if $File is a directory, parent if it is a leaf node
    $oDir = ( Get-ItemFileSystemLocation $File | Get-UNCPathResolved -ReturnObject | Get-LocalPathFromUNC )

    If ( $Repositories.Count -eq 0 -and ( $Pair -ne $null ) ) {

        If ( $mirrors.ContainsKey($Pair) ) {
            $Locations = $mirrors[$Pair].Locations
            
            Write-Debug ( "LOCATIONS:" )
            Write-Debug ( $Locations )

            $Matchable = @{}
            
            $Locations | Get-Member -MemberType NoteProperty |% {
                $PropName = $_.Name
                Write-Debug $PropName
                $Locations.${PropName} = ( $Locations.${PropName} | Get-UNCPathResolved -ReturnObject | Get-LocalPathFromUNC |% { $_.FullName } )
            }

            # Convert this into a list.
            $Matchable = ( $Locations | Get-Member -MemberType NoteProperty |% { $PropName=$_.Name; $Locations.$PropName } )
            
            "MATCHABLE:" | Write-Debug
            $Matchable |% { Write-Debug $_ }

        }
        Else {
            Write-Warning ( "[Get-MirrorMatchedItem] Requested repository pair ({0}) does not exist." -f $Pair )
        }
    }
    ElseIf ( $Pair -eq $null ) {
        Write-Warning ( "[Get-MirrorMatchedItem] No valid Repository found for item ({0})." -f $File )
    }

    # Do any of the path locations in $Matchable match $oDir.FullName ?
    $Matched = ( $Matchable -ieq $oDir.FullName )
    
    Write-Debug ( "oDir.FullName = '{0}'" -f $oDir.FullName )
    
    If ( $Matched ) {
        Write-Debug ( "MATCHED:" )
        $Matched |% { Write-Debug $_ }
        Write-Debug ( "RANGE:" )
        $Range |% { Write-Debug $_ }

        $Range |% {
            $Key = $_
            
            $MatchedUp = ( $Locations.$Key -ieq $oDir.FullName )
            If ( $All -or ( $MatchedUp -eq $Self ) ) {
                $Locations.$Key
            }
        }
        #($Repositories -ine $oDir.FullName)
    }
    ElseIf ( $oDir ) {
        
        $Child = ( $oDir.RelativePath -join "\" )
        $Parent = $oDir.Parent
        $sParent = $Parent.FullName

        If ( $Parent ) {
            $Parents = ( $sParent | Get-MirrorMatchedItem -Pair $Pair -Repositories $Repositories -Original:$Original -Reflection:$Reflection -ColdStorage:$ColdStorage -Self:$Self -All:$All )
            If ( $Parents.Count -gt 0 ) {
                $Parents |% {
                    If ( $_.Length -gt 0 ) {
                        $oParent = ( Get-Item -Force -LiteralPath $_ )
                        $sParent = $oParent.FullName

                        $PossiblePath = (( ( @($sParent) + $oDir.RelativePath ) -ne $null ) -ne "" )
                        $sPossiblePath = ( $PossiblePath -join "\" )

                        # Attempt to adjust around BagIt formatting:
                        # if known file is IN a bag, test for an alter OUTSIDE the bag
                        # if known file is OUTSIDE a bag, test for an alter IN a bag
                        # only use this to change the return value IF the alternative path exists
                        If ( -Not ( Test-Path -LiteralPath "${sPossiblePath}" ) ) {
                            $Leaf = ( $PossiblePath | Select-Object -Last 1 )
                            $Branch = ( $PossiblePath | Select-Object -SkipLast 1 )

                            $AlternativePath = ( @($Branch) + @("data") + @($Leaf) )
                            $sAlternativePath = ( $AlternativePath -join "\" )
                            If ( Test-Path -LiteralPath "${sAlternativePath}" ) {
                                $sPossiblePath = $sAlternativePath
                            }
                            ElseIf ( ( $Branch[-1] -eq "data" ) -Or ( $Leaf -eq "data" ) ) {
                                If ( Test-BagItFormattedDirectory -File $oDir.Parent ) {
                                    $LeafFileName = ( $oDir.RelativePath | Select-Object -Skip 1 )
                                    $AlternativePath = ( @($sParent) + @($LeafFileName) )
                                    $sAlternativePath = ( $AlternativePath -join "\" )
                                    If ( Test-Path -LiteralPath "${sAlternativePath}" ) {
                                        $sPossiblePath = $sAlternativePath
                                    }
                                }
                            }
                        }
                        $sPossiblePath
                    }
                }
            }
        }
        Else {

            $oDir.FullName

        }
        
    }

}

End { }

}

Function Test-MirrorMatchedItem {
Param( [Parameter(ValueFromPipeline=$true)] $File, $Pair, [switch] $Original=$false, [switch] $Reflection=$false, [switch] $ColdStorage=$false )

    Begin { }

    Process {
        # Is it mirrored at all?
        $images = ( $File | Get-MirrorMatchedItem -Pair:$Pair -All )

        If ( $images.Count -gt 1 ) {

            # If it is mirrored, then is it (a) the Original? (b) the Reflection? (c) the ColdStorage copy?
            $self = ( $File | Get-MirrorMatchedItem -Pair:$Pair -Self:$true )
            $alter = ( $File | Get-MirrorMatchedItem -Original:$Original -Reflection:$Reflection -ColdStorage:$ColdStorage -Pair:$Pair -All )

            # If $self is in the $alter set at least once, then we have a match.
            ( ( @($alter) -ieq $self ).Count -gt 0 )

        }
        Else {
            $false
        }
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
Export-ModuleMember -Function Test-ColdStoragePropsDirectory
Export-ModuleMember -Function Test-ColdStorageRepositoryPropsDirectory
Export-ModuleMember -Function Test-ColdStorageRepositoryPropsFile
Export-ModuleMember -Function Get-MirrorMatchedItem
Export-ModuleMember -Function Test-MirrorMatchedItem

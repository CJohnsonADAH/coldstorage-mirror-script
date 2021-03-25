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
$global:gColdStorageSettingsModuleCmd = $MyInvocation.MyCommand

Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gColdStorageSettingsModuleCmd -File "ColdStorageFiles.psm1" )

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Get-ColdStorageSettings {
Param([String] $Name="")

Begin { }

Process {
    Get-ColdStorageSettingsJson | Get-JsonSettings -Name $Name
}

End { }
}


Function Get-TablesMerged {
Param ( [switch] $NoClobber=$false, [switch] $ReturnObject=$false )

    $Output = @{ }
    ForEach ( $Table in ( $Input + $Args ) ) {
        
        If ( $Table -is [Hashtable] ) {
            ForEach ( $Key in $Table.Keys ) {
                If ( -Not ( $NoClobber -and $Output.ContainsKey($Key) ) ) {
                    $Output[$Key] = $Table.$Key
                }
            }
        }
        ElseIf ( $Table -is [Object] ) {
            $Table.PSObject.Properties | ForEach {
                If ( -Not ( $NoClobber -and $Output.ContainsKey($_.Name) ) ) {
                    $Output[$_.Name] = $( $_.Value )
                }
            }
        }


    }


    If ( $ReturnObject ) { [PSCustomObject] $Output } Else { $Output }

}

Function Get-ColdStorageSettingsFiles () {
    $JsonDir = ( My-Script-Directory -Command $global:gColdStorageCommand ).FullName

    $paths = "${JsonDir}\settings.json", "${JsonDir}\settings-${env:COMPUTERNAME}.json"
    
    $File = $null
    $paths | % {
        If ( Test-Path -LiteralPath $_ ) {
            (Get-Item -Force -LiteralPath $_) | Write-Output
        }
    }
}

Function Get-ColdStorageSettingsDefaults {
    $Out=@{
        BagIt="${HOME}\bin\bagit"
        ClamAV="${HOME}\bin\clamav"
    }
    $Out
}

Function Get-ColdStorageSettingsJson {
    Get-ColdStorageSettingsFiles | % {
        If ( $_ -eq $null ) {
            Get-ColdStorageSettingsDefaults | ConvertTo-Json
        } Else {
            Get-Content -Raw $_
        }
    } | Get-JsonSettings | Get-TablesMerged | ConvertTo-Json
}

Function ConvertTo-ColdStorageSettingsFilePath {
Param ( [Parameter(ValueFromPipeline=$true)] $Path )

Begin { }

Process {
    ( ( $Path -replace "[/]",'\' ) -replace '^~[\\]',"${HOME}\" )
}

End { }
}

Function Get-JsonSettings {
Param([String] $Name="", [Parameter(ValueFromPipeline=$true)] $Json)

Begin { }

Process {
    $Hashtable = ( $Json | ConvertFrom-Json )
    If ( $Name.Length -gt 0 ) {
        ( $Hashtable )."${Name}"
    }
    Else {
        $Hashtable
    }
}

End { }

}

#############################################################################################################
## Props Directories and JSON Files #########################################################################
#############################################################################################################

Function Get-ItemColdStoragePropsCascade {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [ValidateSet('Highest', 'Nearest', '')] [string] $Order=$null )

    Begin { }

    Process {
        $File | Get-ItemPropertiesDirectoryLocation -Name ".coldstorage" -Order:$Order -All |% {
            Get-ChildItem "*.json" -LiteralPath $_.FullName |% {
                $Source = $_
                $Source | Get-Content | ConvertFrom-Json |
                    Add-Member -PassThru -MemberType NoteProperty -Name Location -Value $oFile |
                    Add-Member -PassThru -MemberType NoteProperty -Name SourceLocation -Value ( $Source.Directory ) |
                    Add-Member -PassThru -MemberType NoteProperty -Name Source -Value ( $Source )
            }
        }
    }

    End { }

}

Function Get-ItemColdStorageProps {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [ValidateSet('Highest', 'Nearest', '')] [string] $Order=$null, [switch] $Cascade=$false )

    Begin { }

    Process {

        $aCascade = ( $File | Get-ItemColdStoragePropsCascade -Order:$Order )

        If ( $Cascade ) {
            $aCascade | Get-TablesMerged -NoClobber
        }
        Else {
            $aCascade | Select-Object -First 1
        }

    }

    End { }
}

#############################################################################################################
## External Dependency Locations ############################################################################
#############################################################################################################

Function Get-PathToDependency {
Param ( [String] $Package, $Exe=$null )

    $ExePath = ( Get-ColdStorageSettings($Package) | ConvertTo-ColdStorageSettingsFilePath )
    If ( $Exe ) {
        $ExePath = "${ExePath}\${Exe}"
    }

    ( $ExePath )

}

Function Get-PathToClamAV ( $Exe=$null ) { Get-PathToDependency -Package:ClamAV -Exe:$Exe }
Function Get-PathToBagIt ( $Exe=$null ) { Get-PathToDependency -Package:BagIt -Exe:$Exe }
Function Get-PathTo7z ( $Exe=$null ) { Get-PathToDependency -Package:7za -Exe:$Exe }
Function Get-PathToPython ( $Exe=$null ) { Get-PathToDependency -Package:Python -Exe:$Exe }
Function Get-PathToAWSCLI ( $Exe=$null ) { Get-PathToDependency -Package:AWS -Exe:$Exe }

Function Get-ExeFor7z { Get-PathTo7z -Exe:"7za.exe" }
Function Get-ExeForClamAV { Get-PathToClamAV -Exe:"clamscan.exe" }
Function Get-ExeForPython { Get-PathToPython -Exe:"python.exe" }
Function Get-ExeForAWSCLI { Get-PathToAWSCLI -Exe:"aws.exe" }


Function Get-AWSCLIExe {
    $Exe = "aws.exe"
    $awsPath = Get-AWSCLIPath
    If ( $awsPath ) {
        $Exe = ( "{0}\{1}" -f $awsPath,$exe )
    }
    ( $Exe )
}

Function Ping-Dependency {
Param ( [Parameter(ValueFromPipeline=$true)] $Path, $Name=$null, [string] $Test="--version", [switch] $Bork=$false, [ScriptBlock] $Process={ Param($Line); ( $Line ) } )
    
    $ExePath = $Path
    If ( $Bork ) { $ExePath = ( $Path + "-BORKED" ) }

    $DepName = $Name
    If ( $DepName -eq $null ) {
        $DepName = ( ( $Path -split '\\' ) | Select-Object -Last 1 )
    }

    $Status = "-"
    Try { $Output = ( & ${ExePath} ${Test} 2>&1 ); If ( $LastExitCode -gt 0 ) { $Status="CMD-ERR" } Else { $Status = "ok" } }
    Catch [System.Management.Automation.CommandNotFoundException] { $Status="ERR"; $Output = ( $_.ToString() ) }
    Catch [System.Management.Automation.RemoteException] { $Status="CMD-EXCEPT"; $Output = ( $_.ToString() ) }

    @{} | Select-Object @{ n='Name'; e={ $DepName } },
        @{ n='OK'; e={ $Status } },
        @{ n='Result'; e={ $( Invoke-Command -ScriptBlock:$Process -ArgumentList @( $Output, $null ) ) } },
        @{ n='Path'; e={ $Path } }

}

Function Ping-DependencyModule {
Param( [Parameter(ValueFromPipeline=$true)] $Module, [switch] $Bork=$false )

    Begin { }

    Process {
        $moduleName = $Module
        If ( $Bork ) {
            $moduleName = "${moduleName}-BORK"
        }

        $oModule = ( Get-Module -ListAvailable -Name:$moduleName | Add-Member -PassThru -NotePropertyName "OK" -NotePropertyValue "ok" )
        $oModule = ( $oModule |% { $_ | Add-Member -PassThru -NotePropertyName "Result" -NotePropertyValue ( "{0} ver. {1}" -f $_.Name,$_.Version ) } )

        If ( $oModule ) {
            $oModule
        }
        Else {
            @{} | Select-Object @{ n='Name'; e={ $moduleName } }, @{ n='OK'; e={ 'ERR' } },
                @{ n='Result'; e={ "Module not detected; use `Install-Module ${moduleName}` to install ?" } },
                @{ n='Path'; e={ '-N/A-' } }
        }
    }

    End { }

}

Export-ModuleMember -Function Get-ColdStorageSettings
Export-ModuleMember -Function Get-TablesMerged
Export-ModuleMember -Function Get-ColdStorageSettingsFiles
Export-ModuleMember -Function Get-ColdStorageSettingsDefaults
Export-ModuleMEmber -Function Get-ColdStorageSettingsJson 
Export-ModuleMember -Function ConvertTo-ColdStorageSettingsFilePath
Export-ModuleMember -Function Get-JsonSettings
Export-ModuleMember -Function Get-ItemColdStorageProps

Export-ModuleMember -Function Ping-Dependency
Export-ModuleMember -Function Ping-DependencyModule

Export-ModuleMember -Function Get-PathToClamAV
Export-ModuleMember -Function Get-PathToBagIt
Export-ModuleMember -Function Get-PathTo7z
Export-ModuleMember -Function Get-PathToPython
Export-ModuleMember -Function Get-PathToAWSCLI

Export-ModuleMember -Function Get-ExeFor7z
Export-ModuleMember -Function Get-ExeForClamAV
Export-ModuleMember -Function Get-ExeForPython
Export-ModuleMember -Function Get-ExeForAWSCLI

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
$gColdStorageCommand = $MyInvocation.MyCommand

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

    $Output = @{ }
    ForEach ( $Table in ( $Input + $Args ) ) {
        
        If ( $Table -is [Hashtable] ) {
            ForEach ( $Key in $Table.Keys ) {
                $Output.$Key = $Table.$Key
            }
        }
        ElseIf ( $Table -is [Object] ) {
            $Table.PSObject.Properties | ForEach {
                $Output."$($_.Name)" = $( $_.Value )
            }
        }


    }
    $Output

}

Function Get-ColdStorageSettingsFiles () {
    $JsonDir = ( My-Script-Directory -Command $gColdStorageCommand ).FullName

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

Export-ModuleMember -Function Get-ColdStorageSettings
Export-ModuleMember -Function Get-TablesMerged
Export-ModuleMember -Function Get-ColdStorageSettingsFiles
Export-ModuleMember -Function Get-ColdStorageSettingsDefaults
Export-ModuleMEmber -Function Get-ColdStorageSettingsJson 
Export-ModuleMember -Function ConvertTo-ColdStorageSettingsFilePath
Export-ModuleMember -Function Get-JsonSettings

Export-ModuleMember -Function Get-PathToClamAV
Export-ModuleMember -Function Get-PathToBagIt
Export-ModuleMember -Function Get-PathTo7z
Export-ModuleMember -Function Get-PathToPython
Export-ModuleMember -Function Get-PathToAWSCLI

Export-ModuleMember -Function Get-ExeFor7z
Export-ModuleMember -Function Get-ExeForClamAV
Export-ModuleMember -Function Get-ExeForPython
Export-ModuleMember -Function Get-ExeForAWSCLI

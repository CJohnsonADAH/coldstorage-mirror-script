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

Function Get-AWSCLIPath {
    return ( Get-ColdStorageSettings("AWS") | ConvertTo-ColdStorageSettingsFilePath )
}
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

Export-ModuleMember -Function Get-AWSCLIPath
Export-ModuleMember -Function Get-AWSCLIExe

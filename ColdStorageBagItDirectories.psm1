#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################

Function My-Script-Directory {
Param ( $Command, $File=$null )

    $Source = ( $Command.Source | Get-Item -Force )
    $Path = ( $Source.Directory | Get-Item -Force )

    If ( $File -ne $null ) {
        $Path = ( Join-Path $Path.FullName -ChildPath $File )
    }

    $Path
}

Import-Module $( My-Script-Directory -Command $MyInvocation.MyCommand -File "ColdStorageFiles.psm1" )

$global:CSBIDScriptDirectory = ( My-Script-Directory -Command $MyInvocation.MyCommand )

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Test-BagItFormattedDirectory {
Param ( $File )

    $result = $false # innocent until proven guilty

    $oFile = Get-FileObject -File $File
    If ( ( $oFile -ne $null ) -and ( $oFile | Get-Member -Name FullName ) ) {
        $BagDir = $oFile.FullName
        If ( Test-Path -LiteralPath $BagDir -PathType Container ) {
            $PayloadDir = ( "${BagDir}" | Join-Path -ChildPath "data" )
            if ( Test-Path -LiteralPath $PayloadDir -PathType Container ) {
                $BagItTxt = ( "${BagDir}" | Join-Path -ChildPath "bagit.txt" )
                if ( Test-Path -LiteralPath $BagItTxt -PathType Leaf ) {
                    $result = $true
                }
            }
        }
        ( "[Test-BagItFormattedDirectory] Result={0} -- File: '{1}'" -f $result,$File ) | Write-Debug
    }
    Else {
        ( "[Test-BagItFormattedDirectory] Result={0} -- File Not Found: '{1}'" -f $result,$File ) | Write-Debug
    }

    $result | Write-Output
}

Function Get-CSBaggedPackageLogDirectory {
Param ( $LiteralPath, [switch] $NoLog = $false )

    $LogDirItem = $null

    If ( -Not $NoLog ) {
        $LogDir = ( Join-Path -Path "${LiteralPath}" -ChildPath "logs" )
        If ( Test-Path -LiteralPath $LogDir ) {
            $LogDirItem = ( Get-Item -LiteralPath $LogDir -Force )
        }
        Else {
            $LogDirItem = ( New-Item -ItemType Directory -Path $LogDir )
        }
    }

    If ( $LogDirItem -ne $null ) {
        $LogDirItem
    }
}

Function Add-CSBaggedPackageValidationLog {
Param ( $LiteralPath, [switch] $NoLog = $false, [switch] $Fast = $false )

    $LogFile = $null

    If ( -Not $NoLog ) {
        $LogDirItem = ( Get-CSBaggedPackageLogDirectory -LiteralPath $DIRNAME -NoLog:$NoLog )
        If ( $LogDirItem ) {
            $Timestamp = @( ( Get-Date -Format 'yyyyMMdd' ), ( Get-Date -Format 'HHmmss' ) )
            $Method = $( If ( $Fast ) { "-FAST" } Else { "" } )
            $LogFile = ( Join-Path -Path $LogDirItem.FullName -ChildPath ( "validation-{0}-{1}-{2}-{3}{4}.txt" -f "bagit",$Timestamp[0], $Timestamp[1], $env:COMPUTERNAME, $Method ) )
        }
    }

    If ( $LogFile -ne $null ) {
        $LogFile
    }

}

Function Write-CSBagItValidationMessage {
Param ( [Parameter(ValueFromPipeline=$true)] $Line, $Log, [switch] $NoLog = $false, [switch] $ForLogOnly = $false )

    Begin { }

    Process {
        If ( $Verbose -and ( -Not $ForLogOnly ) ) {
            ( "${Line}" -split "[`r`n]+" ) | Write-Verbose
        }

        If ( -Not $NoLog ) {
            "${Line}" | Out-File -LiteralPath "${Log}" -Append -Encoding UTF8
        }
    }

    End { }

}

Function Test-CSBaggedPackageValidates ($DIRNAME, [String[]] $Skip=@( ), [switch] $Verbose = $false, [switch] $NoLog = $false, [switch] $Fast=$false ) {

    $CSBagIt= ( Join-Path $global:CSBIDScriptDirectory -ChildPath "coldstorage-bagit.ps1" )

    Push-Location $DIRNAME

    $LogFile = ( Add-CSBaggedPackageValidationLog -LiteralPath:$DIRNAME -NoLog:$NoLog -Fast:$Fast )
    
    If ( -Not ( -Not ( ( $Skip |% { $_.ToLower().Trim() } ) | Select-String -Pattern "^bagit$" ) ) ) {
        "BagIt Validation SKIPPED for path ${DIRNAME}" | Write-Verbose -InformationAction Continue
        "OK-BagIt: ${DIRNAME} (skipped)" # > stdout
    }
    Else {
        If ( $Verbose ) {
            "${CSBagIt} --validate ${DIRNAME}" | Write-Verbose
        }
        [PSCustomObject] @{ "Location"=( ( Get-Location ).Path ) } | ConvertTo-Json -Compress |% { "! JSON[Start]:`t $_" | Write-CSBagItValidationMessage -Log:$LogFile -NoLog:$NoLog -ForLogOnly }

        $Output = @( )
        $ValidationFlags = @( "--validate", '--dangerously' )
        If ( $Fast ) {
            $ValidationFlags += @( "--fast" )
        }
        & "${CSBagIt}" @ValidationFlags . -Progress -Stdout -DisplayResult |% {
            $Output = @( $Output ) + @( "$_" -split "[`r`n]+" )
            "$_" | Write-CSBagItValidationMessage -Log:$LogFile -NoLog:$NoLog -Verbose:$Verbose
        }
        $NotOK = $LastExitCode

        [PSCustomObject] @{ "Exit"=$NotOK } | ConvertTo-Json -Compress |% { "! JSON[Exit]:`t $_" | Write-CSBagItValidationMessage -Log:$LogFile -NoLog:$NoLog -ForLogOnly }

        If ( $NotOK -gt 0 ) {
            $OldErrorView = $ErrorView; $ErrorView = "CategoryView"
            
            "ERR-BagIt: ${DIRNAME}" | Write-Warning
            If ( -Not $Verbose ) {
                $Output | Write-Warning
            }

            $ErrorView = $OldErrorView
        }
        Else {
            "OK-BagIt: ${DIRNAME}" # > stdout
        }

    }

    Pop-Location

}


Function Select-BagItFormattedDirectories {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process { If ( Test-BagItFormattedDirectory($File) ) { $File } }

End { }
}

Function Select-BagItPayloadDirectory {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    If ( $File -ne $null ) {
        $sPath = ( ( Get-FileObject($File).FullName ) | Join-Path -ChildPath "data" )
        If ( Test-Path -LiteralPath "${sPath}" -PathType Container ) {
            Get-Item -Force -LiteralPath "${sPath}"
        }
    }
}

End { }

}

Function Select-BagItPayload {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    $File | Select-BagItPayloadDirectory |% {
        $sPath = $_.FullName
        Get-ChildItem -Force -Recurse -LiteralPath "${sPath}"
    }
}

End { }

}

Export-ModuleMember -Function Test-BagItFormattedDirectory
Export-ModuleMember -Function Test-CSBaggedPackageValidates
Export-ModuleMember -Function Select-BagItFormattedDirectories
Export-ModuleMember -Function Select-BagItPayloadDirectory
Export-ModuleMember -Function Select-BagItPayload

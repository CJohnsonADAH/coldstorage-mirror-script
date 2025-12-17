#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################

$global:gColdStorageDataModuleCmd = $MyInvocation.MyCommand
    
    $modSource = ( $global:gColdStorageDataModuleCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

#Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Get-StringMD5 {
Param ( [Parameter(ValueFromPipeline=$true)] $Line, $Text=$null )
<#
.SYNOPSIS
Return the MD5 checksum or checksums for a given string or set of strings.

.DESCRIPTION
Accepts input from the pipeline or from a command-line switch.
Outputs the computed MD5 hash for the input string, or hashes for each of several strings.
#>

    Begin { }

    Process {
        If ( $Line -ne $null ) {
            $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
            $utf8 = New-Object -TypeName System.Text.UTF8Encoding
            ( [System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($Line))) -replace '[^0-9A-F]+','' )
        }
    }

    End {
        If ( $Text -ne $null ) {
            $Text | Get-StringMD5
        }
    }
}

Function Get-StringChecksum {
Param ( [Parameter(ValueFromPipeline=$true)] $Line, $Text=$null, $Algorithm="MD5" )
    Begin { }

    Process {

        If ( $Line -ne $null ) {

            $stream = [System.IO.MemoryStream]::new()
            $writer = [System.IO.StreamWriter]::new( $stream )
            $writer.write( $Line )
            $writer.Flush()
            $stream.Position = 0

            $oHash = ( Get-FileHash -InputStream:$stream -Algorithm:$Algorithm )
            If ( $oHash ) {
                $oHash.Hash
            }

        }

    }

    End { 
        If ( $Text -ne $null ) {
            $Text | Get-StringChecksum -Algorithm:$Algorithm
        }
    }

}

Function Get-CurrentLine {
    $MyInvocation.ScriptLineNumber
}

Function Get-CSDebugContext {
Param ( $Function, $Format="{0}:{1}" )

    If ( $Function -is [String] ) {
        $sName = $Function
    }
    ElseIf ( $Function | Get-Member -Name MyCommand ) {
        $sName = ( $Function.MyCommand.Name )
    }
    Else {
        $sName = "${Function}"
    }
    $nLine = $MyInvocation.ScriptLineNumber

    $Format -f $sName, $nLine | Write-Output
}

Export-ModuleMember -Function Get-StringMD5
Export-ModuleMember -Function Get-StringChecksum
Export-ModuleMember -Function Get-CurrentLine
Export-ModuleMember -Function Get-CSDebugContext

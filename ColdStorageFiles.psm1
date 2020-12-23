Function Get-FileObject ( $File ) {
    
    $oFile = $null
    If ( $File -is [String] ) {
        If ( Test-Path -LiteralPath "${File}" ) {
            $oFile = ( Get-Item -Force -LiteralPath "${File}" )
        }
    }
    Else {
        $oFile = $File
    }

    $oFile
}

Function Get-FileLiteralPath {
Param($File)

	$sFile = $null

	If ( $File -eq $null ) {
		$oFile = $null
	}
	ElseIf ( -Not ( Get-Member -InputObject $File -name "FullName" -MemberType Properties ) ) {
		$oFile = Get-FileObject($File)
	}
	Else {
		$oFile = $File
	}

	If ( Get-Member -InputObject $oFile -name "FullName" -MemberType Properties ) {
		$sFile = $oFile.FullName
	}
	
	$sFile
}

Function Test-HiddenOrSystemFile ( $File ) {
    $oFile = Get-FileObject $File
    $screen = ( [IO.FileAttributes]::System + [IO.FileAttributes]::Hidden )

    ( ( $oFile.Attributes -band $screen ) -ne 0 )
}

Function Test-DifferentFileContent {
Param ( $From, $To, [Int] $DiffLevel=2, [switch] $Verbose=$false )

    # We go through some rigamarole here because each side of the comparison MAY be
    # a valid file path whose content we can hash, OR it MAY be a string of a path
    # to a file that does not (yet) exist.

	$oFrom = Get-FileObject($From)
	$oTo = Get-FileObject($To)
	
	If ( $oFrom -ne $null ) {
		$Differentiated = ($oTo -eq $null)
	
		If ( ( -Not $Differentiated ) -and ( $DiffLevel -gt 0 ) ) {
			$LeftLength = $null
			$RightLength = $null
			If ( $oFrom -ne $null ) {
				$LeftLength = $oFrom.Length
			}
			If ( $oTo -ne $null ) {
				$RightLength = $oTo.Length
			}
			If ($Verbose) { Write-Output "Length comparison: ${LeftLength} vs. ${RightLength}" }
			$Differentiated=($Differentiated -or ( $LeftLength -ne $RightLength ))
		}

		If ( ( -Not $Differentiated ) -and ( $DiffLevel -gt 1 ) ) {
			$sFrom = Get-FileLiteralPath($oFrom)
			$sTo = Get-FileLiteralPath($oTo)
			
			$LeftHash = $null
			$RightHash = $null

			If ( $sFrom -ne $null ) {
				$LeftHash = (Get-FileHash -LiteralPath $sFrom).hash
			}
			If ( $sTo -ne $null ) {
				$RightHash = (Get-FileHash -LiteralPath $sTo).hash
			}
			If ($Verbose) { Write-Output "Hash comparison: ${LeftHash} vs. ${RightHash}" }
			$Differentiated=($Differentiated -or ( $LeftHash -ne $RightHash))
        }
    }
	Else {
		$Differentiated = ($oTo -ne $null)
	}

    $Differentiated
}

Export-ModuleMember -Function Get-FileObject
Export-ModuleMember -Function Get-FileLiteralPath
Export-ModuleMember -Function Test-HiddenOrSystemFile
Export-ModuleMember -Function Test-DifferentFileContent

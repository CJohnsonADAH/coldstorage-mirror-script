Param(
	[Parameter(ValueFromPipeline=$true)] $Item,
	[switch] $Force=$false,
	[switch] $IfExists=$false,
	[switch] $ReturnObject=$false,
	[switch] $Quiet=$false,
	$Event="log",
	$EventType=$null,
	$Timestamp=$null,
	$Context=$null
)

Begin {
	If ( $Context ) {
		$sCmdName = $Context
	}
	Else {
		$sCmdName = $MyInvocation.MyCommand.Name
	}
}

Process {

	If ( $Item ) {

		$Package = ( $Item | & get-itempackage-cs.ps1 -At -Bagged -Force )

		If ( $Package | & test-cs-package-is.ps1 -Bagged ) {

			$Bag = ( $Package.CSPackageBagLocation | Sort-Object -Descending -Property LastWriteTime | Select-Object -First 1 )
			$LogContainer = ( $Bag | & get-bagitbagcomponent-cs.ps1 -Subdirectory:"logs" -Force:$Force )
			If ( $LogContainer ) {
				$Mesg = ( '[{0}] log file container: "{1}"' -f $sCmdName,$LogContainer.FullName )
				$Mesg | Write-Debug

				$TS = $Timestamp
				If ( $TS -eq $null ) {
					$TS = ( Get-Date )
				}
				ElseIf ( $TS -is [string] ) {
					$TS = [DateTime]::Parse( $TS )
				}
				
				$sDate = $TS.ToString('yyyyMMdd')
				$sTime = $TS.ToString('HHmmss')
				$sMachine = $env:COMPUTERNAME

				$sSuffix = $sMachine
				If ( $EventType -ne $null ) {
					$sSuffix = ( "{0}-{1}" -f $sSuffix, $EventType )
				}
				
				$LogFileName = ( "{0}-{1}-{2}-{3}.txt" -f $Event, $sDate, $sTime, $sSuffix )
				$LogFile = ( Join-Path $LogContainer.FullName -ChildPath $LogFileName )
				
				If ( ( -Not $IfExists ) -Or ( Test-Path -LiteralPath $LogFile -PathType Leaf ) ) {
					If ( -Not $ReturnObject ) {
						$LogFile
					}
					Else {
						Get-Item -LiteralPath $LogFile -Force
					}
				}

			}
			Else {
				$Mesg = ( '[{0}] logs subdirectory not found.' -f $sCmdName )
				If ( $Quiet ) {
					$Mesg | Write-Debug
				}
				Else {
					$Mesg | Write-Warning
				}
			}
			#$LogContainer = ( $Bag | 
			#$LogContainerPath = 
			
			
		}
		
	}
	
}

End {
}

Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    [switch] $At=$false,
    [switch] $NoValidate=$false
)

# Initialize variables
$global:gTMMCSScriptName = $MyInvocation.MyCommand
$global:gTMMCSScriptPath = $MyInvocation.MyCommand.Definition

$Cmd = $global:gTMMCSScriptName
$Package = $null
$Counterpart = $null

$Package = ( $Item | & coldstorage-get-packages.ps1 for -Items -At:$At )
If ( $Package -ne $null ) {
    $Mirrors = ( $Package | & get-mirrormatcheditem-cs.ps1 -Object -Original -Reflection )
    $Original, $Reflection = $Mirrors
}
Else {
    '[{0}] ITEM: "{1}" - PRESERVATION PACKAGE could not be found.' -f $Cmd,$Item | Write-Warning
}

$manifestDiffs = -1
If ( ( $Original -ne $null ) -and ( $Reflection -ne $null ) ) {
    "[{0}] OK: {1} =? {2}" -f $Cmd,$Original.FullName,$Reflection.FullName | Write-Debug
    If ( $Original | test-cs-package-is.ps1 -Bagged ) {

        If ( $Reflection | test-cs-package-is.ps1 -Bagged ) {

            $manifests = ( Get-ChildItem -LiteralPath $Original.FullName -File |? { $_.Name -like '*manifest-*.txt' } )
            $countermanifests = ( Get-ChildItem -LiteralPath $Reflection.FullName -File |? { $_.Name -like '*manifest-*.txt' } )
            $manpairs = @{ } 
            
            $manifests |% { $Name = $_.Name ; $manpairs[ $Name ] = @( $_ ) }
            $countermanifests |% { $Name = $_.Name ; $Orig = @( ) ; If ( $manpairs.ContainsKey( $Name ) ) { $Orig += @( $manpairs[ $Name ] ) } ; $manpairs[ $Name ] = @( $Orig ) + @( $_ ) }
            
            $manifestDiffs = 0
            $manpairs.Keys |% {
                $pair = $manpairs[ $_ ]
                If ( $pair.Count -ne 2 ) {
                    "NOOOO {0}" -f $pair | Write-Error
                    $manifestDiffs = 1
                }
                ElseIf ( $manifestDiffs -ne -1 ) {
                    "& fc.exe '{0}' '{1}'" -f $pair[0].FullName, $pair[1].FullName | Write-Debug
                    $fcOutput = ( & fc.exe $pair[0].FullName $pair[1].FullName ) ; $diff = $LASTEXITCODE
                    $manifestDiffs = ( $manifestDiffs + $diff )

                    If ( $diff -ne 0 ) {
                        $fcOutput | Write-Host -ForegroundColor Yellow
                        "fc.exe Exit Code: {0:N0}" -f $diff | Write-Error
                    }
                }
            }

            If ( $manifestDiffs -eq 0 ) {

                If ( -Not $NoValidate ) {
                    Push-Location $Original.FullName
                    & coldstorage-bagit.ps1 --validate . -Progress
                    Pop-Location

                    Push-Location $Reflection.FullName
                    & coldstorage-bagit.ps1 --validate . -Progress
                    Pop-Location
                }

                "GOOD"
            }
            Else {
                "BAD" | Write-Error
            }

        }
        Else {

            "OH NO" | Write-Error

        }
    }
    Else {

        "OH MY" | Write-Error

    }
}
ELse {
    '[{0}] PACKAGE: "{1}" - MIRRORED PACKAGE could not be found.' -f $Cmd,$Package.FullName | Write-Warning
}

Exit 255
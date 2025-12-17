Param(
    $Repositories=@( 'Access', 'Masters' ),
    $Window=60,
    $IPG=75,
    $Schedule='6:00 PM'
)

If ( $Schedule -ne $null ) {
    $Timeout = ( [DateTime]::Parse( $Schedule ) - ( Get-Date ) ).TotalSeconds
    $sSchedule = ( " (schedule: {0})" -f $Schedule )
}
Else {
    $Timeout = $null
    $sSchedule = ""
}

If ( & read-yesfromhost-cs.ps1 -Prompt:( "Initiate mirror{0}:" -f $sSchedule ) -Timeout:$Timeout -DefaultInput:"Y" ) {

    $Repositories |% {
        $repo = ( & coldstorage repository $_ -Location:Original )

        If ( Test-Path -LiteralPath $repo.File -PathType Container ) {
            $Local = ( $repo.File | & get-mirrormatcheditem-cs.ps1 -Original | Convert-Path )
            $o = ( Get-Item -LiteralPath $Local -Force )

            Push-Location -LiteralPath $o.FullName

            Get-ChildItem -Directory |? { $_.Name -notlike '.*' } |? { $_.Name -notin @( 'ZIP' ) } |% {
                Push-Location -LiteralPath $_.FullName
                Write-Progress -Id 001 $_.FullName

                $mirror = ( Get-Item . | get-mirrormatcheditem-cs.ps1 -ColdStorage )
                If ( Test-Path $mirror ) {
                    $mirror = ( $mirror | Convert-Path )
                }
                Else {
                    $oMirror = ( New-Item -ItemType Directory $mirror )
                    $mirror = ( $oMirror.FullName | Convert-Path )
                }

                If ( $mirror ) {
                    & Robocopy.exe /copy:DAT /dcopy:DAT /maxage:${Window} /ipg:${IPG} /z /r:1 /w:1 /e $_.FullName $mirror /XD .coldstorage ZIP
                }

                Pop-Location

            }

            Pop-Location
        }
        Else {
            "COULD NOT CHANGE LOCATION TO {0}" -f $_ | Write-Error
        }
    }
}

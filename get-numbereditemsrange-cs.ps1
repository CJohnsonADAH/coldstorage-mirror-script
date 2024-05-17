Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    [switch] $Prefix=$false,
    [switch] $Suffix=$false
)

Begin {
}

Process {
    $Item | get-file-cs.ps1 -Object |% {

        $Name = $_.Name
        If ( $Name -match '^([A-Za-z]+)([0-9]+)_(\1)([0-9]+)([^0-9].*)?$' ) {

            $sPrefix = ''
            If ( $Prefix ) {
                $sPrefix = $Matches[1]
            }
            
            $sSuffix = ''
            If ( $Suffix ) {
                $sSuffix = $Matches[5]
            }
            
            $DigitCount = $Matches[2].Length
            $From = [int64] $Matches[2]
            $To = [int64] $Matches[4]
            
            If ( $To -ge $From ) {
                $N = $From
                While ( $N -le $To ) {
                    $Template = ( "{1:D${DigitCount}}" )
                    $Next = ( "{0}${Template}{2}" -f $sPrefix,$N,$sSuffix )
                    $Next
                    $N = $N + 1
                }
            }
        }
    }
}

End {
}
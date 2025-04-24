Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    [switch] $SystemFiles=$false,
    [switch] $Not=$false
)

Begin {

    $aCrud = @(
    '^Thumbs[.]db$'
    )
    $aAttribs = @(
    [IO.FileAttributes]::System
    )
}

Process {
    "[{0}] testing {1}" -f $MyInvocation.MyCommand.Name,$Item.Name | Write-Debug
    
    $MatchingCriteria = @{ }
    $MatchingCriteria['filename pattern'] = ( $aCrud |? { $Item.Name -match $_ } )
    If ( $SystemFiles ) {
        $MatchingCriteria['file attribute'] = @( $aAttribs |? { [bool] ( $Item.Attributes -band $_ ) } )
    }

    $Matching = @( )
    $MatchingCriteria.Keys |% {
        $test = $_
        $aCriteria = $MatchingCriteria[ $_ ]
        $aCriteria |% { "[{0}] {1} matches {2}: {3}" -f $MyInvocation.MyCommand.Name,$Item.Name,$test,$_ } | Write-Debug
        $Matching += @( $aCriteria )
    }

    $Matched = ( $Matching.Count -gt 0 )
    ( $Matched -xor $Not )

}

End {
}

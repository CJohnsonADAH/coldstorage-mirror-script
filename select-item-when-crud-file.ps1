Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    [switch] $SystemFiles=$false,
    [switch] $Not=$false
)

Begin {
}

Process {
    $Item |? { $_ | & test-item-is-crud-file.ps1 -SystemFiles:$SystemFiles -Not:$Not }
}

End {
}

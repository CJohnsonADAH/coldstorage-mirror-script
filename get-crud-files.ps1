Param(
    [Parameter(ValueFromPipeline=$true)] $Container,
    [switch] $SystemFiles=$false
)

Begin {
}

Process {
    Get-ChildItem $Container | & select-item-when-crud-file.ps1 -SystemFiles:$SystemFiles
}

End {
}

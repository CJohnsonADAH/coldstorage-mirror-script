Param(
    [Parameter(ValueFromPipeline=$true)] $Container,
    [switch] $SystemFiles=$false,
    [switch] $Recurse=$false,
    [switch] $IncludeDirectories=$false
)

Begin {
}

Process {
    If ( $Container ) {
        $oContainer = ( $Container | & get-file-cs.ps1 -Object )
        If ( $oContainer ) {
            Get-ChildItem $Container -Recurse:$Recurse -File:( -Not $IncludeDirectories ) -Force | & select-item-when-crud-file.ps1 -SystemFiles:$SystemFiles
        }
        Else {
            '[{0}] no such file: "{1}"' -f $MyInvocation.MyCommand.Name,$Container | Write-Error
        }
    }
}

End {
}

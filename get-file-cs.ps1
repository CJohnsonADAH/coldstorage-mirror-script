Param(
    [Parameter(ValueFromPipeline=$true)] $File,
    [switch] $Object=$false,
    [switch] $LiteralPath=$false
)

Begin {
    $global:gColdStorageGetFileCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gColdStorageGetFileCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )

    $gfExitCode = 0
}

Process {
    If ( $Object ) {
        $File | Get-FileObject
    }

    If ( $LiteralPath ) {
        $File | Get-FileLiteralPath
    }
    ElseIf ( -Not $Object ) {
        $File | Get-FileObject
    }
}

End {
    Exit $gfExitCode
}

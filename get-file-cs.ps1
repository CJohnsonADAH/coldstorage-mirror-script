Param(
    [Parameter(ValueFromPipeline=$true)] $File,
    [switch] $Object=$false,
    [switch] $LiteralPath=$false,
    [switch] $Localize=$false
)

Begin {
    $global:gColdStorageGetFileCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gColdStorageGetFileCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )

    $gfExitCode = 0
}

Process {
    $o = $File
    If ( $Localize ) { 
        $o = ( $o | Get-LocalPathFromUNC )
    }

    If ( $Object ) {
        $o | Get-FileObject
    }

    If ( $LiteralPath ) {
        $o | Get-FileLiteralPath
    }
    ElseIf ( -Not $Object ) {
        $o | Get-FileObject
    }
}

End {
    Exit $gfExitCode
}

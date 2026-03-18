Param(
    [Parameter(ValueFromPipeline=$true)] $Item
)

Begin {
    $ExitCode = 0
}

Process {

    If ( $Item -ne $null ) {

        If ( $Item | test-cs-package-is.ps1 -Unbagged ) {
            
            If ( $Item | test-readytobundle-cs.ps1 ) {
            
                $Item

            }

        }

    }

}

End {
    Exit $ExitCode
}

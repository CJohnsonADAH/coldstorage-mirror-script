<#
Out-BagItFormattedDirectory-CS.ps1 
@version 2026.0326

.SYNOPSIS
Invoke the BagIt.py external script to bag a preservation package

.DESCRIPTION
Given a directory of digital content, enclose it within a BagIt-formatted package.
Formerly known as: Do-Bag-Directory

.PARAMETER Container
Specifies the directory to enclose in a BagIt-formatted package.

.PARAMETER PassThru
If present, output the location of the BagIt-formatted package into the pipeline after completing the bagging.

.PARAMETER Progress
If provided, provides a [CSProgressMessenger] object to manage progress and logging output from the process.
#>


Param(
    [Parameter(ValueFromPipeline=$true)] $Container,
    [switch] $PassThru=$false,
    $Log=$null,
    $LogPackage=$null,
    $Context=$null,
    $Progress=$null
)

Begin {

    $global:gOutBagItFormattedDirectoryCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gOutBagItFormattedDirectoryCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageInteraction.psm1" )

    $ExitCode = 0

}

Process {
    
    $BagDir = ( $Container | Get-FileLiteralPath )

    Push-Location -LiteralPath:$BagDir

    Get-SystemArtifactItems -LiteralPath "." | Remove-Item -Force -Verbose:$Verbose

    "PS ${PWD}> bagit.py ." | Write-Verbose
    
    If ( $Progress ) {
        $Progress.Update( ( "Bagging {0}" -f $BagDir ), 0, ( "OK-BagIt: {0}" -f $BagDir ) )
    }

    $BagItPy = ( Get-PathToBagIt | Join-Path -ChildPath "bagit.py" )
	$Python = ( Get-ExeForPython )

    # Execute bagit.py under python interpreter; capture stderr output and send it to $Progress if we have that
    $Output = ( & "${Python}" "${BagItPy}" . 2>&1 |% { "$_" -replace "[`r`n]","" } |% { If ( $Progress ) { $Progress.Update( ( "Bagging {0}: {1}" -f $BagDir,"$_" ), 0, $null ) } ; "$_" } )
    $NotOK = $LASTEXITCODE
        
    If ( $Log -ne $null ) {
        # Send the bagit.py console output to the log file, if provided
        $Output | Write-CSOutputWithLogMaybe -Package:$LogPackage -Command:$Context -Log:$Log >$null
    }

    $ExitCode = $NotOK
    If ( $NotOK -gt 0 ) {
        "ERR-BagIt: returned ${NotOK}" | Write-Verbose
        $Output | Write-Error
    }
    Else {
            
        # Send the bagit.py console output to Verbose stream
        $Output 2>&1 |% { "$_" -replace "[`r`n]","" } |% { If ( $Progress ) { $Progress.Update( ( "Bagging {0}: {1}" -f $BagDir,"$_" ), 0, $null ) } ; $_ | Write-Verbose }
            
        # If requested, pass thru the successfully bagged directory to Output stream
        If ( $PassThru ) {
            $BagDir | Get-FileObject | Write-Output
        }
        ElseIf ( $Progress ) {
            $Progress.Update( ( "Bagged {0}" -f $BagDir ), ( "OK-BagIt: {0}" -f $BagDir ) )
        }


    }

    Pop-Location
}

End {
    Exit $ExitCode
}


Param(
    $Repository,
    [switch] $Interactive=$false,
    [switch] $Progress=$false,
    [switch] $PassThru=$false,
    [switch] $Verbose=$false,
    [switch] $Quiet=$false,
    [switch] $Debug=$false,
    [switch] $RandomOrder=$false,
    [switch] $Version=$false,
    $LogFile=$null,
    [int] $Directories=-1,
    $Timeout=$null,
    [string] $Path="*",
    [switch] $SU
)

# $MyInvocation.BoundParameters.Keys|Write-Warning
# $Verbose = ( $MyInvocation.BoundParameters["Verbose"].IsPresent )
# $Verbose = $( If ( $Verbose -eq $null ) { $false } Else { $Verbose } )
# $Debug = ( $MyInvocation.BoundParameters["Debug"].IsPresent )
# $Debug = $( If ( $Debug -eq $null ) { $false } Else { $Debug } )

$global:gColdStorageReportStatusCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gColdStorageReportStatusCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" ) -Force
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageUserPrivileges.psm1" ) -Force

Function Get-CSRepositoryProperties {
Param ( $Repository )

    $aRepo = $null
    If ( $Repository ) {
        $aRepos = ( & coldstorage repository )
        $aRepo = ( $Repository | & coldstorage repository -Location:Original ) 
    }

    If ( $aRepo -ne $null ) {

        $Repo = $Repository

        $RepoGroup = ( $aRepos.Keys |? { $_ -eq $Repo } |% { $aRepos[ $_ ][0] } )

        $RepoRoot = ( $aRepo.FILE | Get-LocalPathFromUNC )
        "REPOSITORY: {0} / {1}" -f $Repo, $RepoRoot | Write-Host -ForegroundColor Yellow

    }
    Else {
    
        $RepoGroup = 'ER'
        $Repo = 'Processed'
        $RepoRoot = ( Join-Path 'H:\ElectronicRecords' -ChildPath $Repo )

    }

    $Out = [PSCustomObject] @{
        "Name"=$Repo
        "Group"=$RepoGroup
        "Root"=$RepoRoot
    }

    $Out | Write-Output
}
Function Write-CSRepositoryProgress {
Param ( [Parameter(ValueFromPipeline=$true)] $Message, $Id=42, $Repository, $PercentComplete=0, [switch] $Completed )

    Begin { }

    Process {
        Write-Progress -Id:$Id -Activity:( 'Scanning {0}-{1}' -f $Repository.Group, $Repository.Name ) -Status:$Message -PercentComplete:$PercentComplete -Completed:$Completed
    }

    End { }

}

If ( $Version ) {
    "{0} 2025.0618" -f $modSource.Name | Write-Output
    Exit 0
}

$Invoc = $MyInvocation
$cmd = $Invoc.MyCommand

Start-ProcessWithNetworkAccess -SU:$SU -Invocation:$Invoc -Command:$cmd

$Repo = ( Get-CSRepositoryProperties -Repository:$Repository )

Push-Location $Repo.Root

$t0 = ( Get-Date )
$t0 | Write-CSRepositoryProgress -Repository:$Repo

$aDirectories = ( Get-ChildItem -Directory -Path:$Path )
If ( $RandomOrder ) {
    $aDirectories = ( $aDirectories | Sort-Object { Get-Random } )
}

If ( $Directories -gt 0 ) {
    $aDirectories = ( $aDirectories | Select-Object -First:$Directories )
}

$cmd = $MyInvocation.MyCommand.Name

$nDirectories = ( $aDirectories | Measure-Object ).Count
$I = 0

$TO = $Timeout
If ( ( ( $Timeout -is [Int] ) -or ( $Timeout -is [Int64] ) ) -or ( $Timeout -is [double] ) ) {
    $TO = ( New-TimeSpan -Seconds $Timeout )
}

$aDirectories |? { -Not ( $_.Name -like ".*" ) } |? { -Not ( $_.Name -eq "ZIP" ) } |? {
    If ( $Interactive ) {
        read-yesfromhost-cs.ps1 -Prompt ( "Report {0}" -f $_.Name ) -Timeout 10 -DefaultTimeout 5
    }
    Else {
        $true
    }
} |% {
    Push-Location $_.FullName
    "REPORT-SCAN [{1}]: {0}" -f $_.FullName,( Get-Date ) | Write-Host -BackgroundColor Black -ForegroundColor DarkYellow

    If ( $LogFile ) {
        ( "[{0}] {1}" -f ( Get-Date ),$_.FullName ) >> $LogFile
    }

    $tN = ( Get-Date )
    $Proceed = $true
    If ( $TO -ne $null ) {
        $Proceed = ( ( $tN - $t0 ) -le $TO )
        "TIMESPAN [ {0} <= {1} ] PROCEED: {2}" -f ( $tN - $t0 ), ( $TO ), $Proceed | Write-Verbose
    }

    If ( $Proceed ) {
        ( "[{0}] Processing {1}" -f $cmd, $_.Name ) | Write-Verbose -Verbose:$Verbose

        $caption =  ( "[{0}] {1}" -f $tN,$_.Name )
        $pct =  ( @( 100.0, ( $I / $nDirectories ) ) | Measure-Object -Minimum ).Minimum

        $caption | Write-CSRepositoryProgress -Repository:$Repo -PercentComplete:$pct

        & coldstorage.ps1 packages -Items . -Recurse -Zipped -Mirrored -NotInCloud -Context:$Repo.Root -Verbose:$Verbose -Debug:$Debug -Progress:$Progress |% {
            If ( $PassThru ) {
                $_ | write-packages-report-cs.ps1 -Context:$Repo.Root | Write-Host -BackgroundColor Black -ForegroundColor Green
                $_
            }
            Else {
                $_ | write-packages-report-cs.ps1 -Context:$Repo.Root
            }
        }
    }
    Else {
        ( "[{0}] {1} skipped - timed out" -f $cmd, $_.Name ) | Write-Warning
    }
    Pop-Location

    $I = ( $I + 1 )
}

$tN = ( Get-Date )

$t0 | Write-CSRepositoryProgress -Repository:$Repo -PercentComplete:100.0 -Completed

If ( -Not $Quiet ) {
    "[{0}] {1}" -f ( $MyInvocation.MyCommand.Name, ( $tN - $t0 ) ) | Write-Host -ForegroundColor Green
}

Pop-Location

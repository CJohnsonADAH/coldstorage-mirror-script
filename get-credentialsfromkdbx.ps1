Import-Module PoShKeePass

$KDBX = "D:\AdminDiv\InformationTechnology\Database.kdbx"
$TempLocation = "C:\Database.kdbx"
$DB = "ITDB"
$Root = "Database"
$GroupName = "ADAH-Servers"
$Title = "Test-KDBX"

Copy-Item -LiteralPath $KDBX -Destination $TempLocation

New-KeePassDatabaseConfiguration -DatabaseProfileName:$DB -DatabasePath:$TempLocation -UseMasterKey
Get-KeePassEntry -DatabaseProfileName:$DB -KeePassEntryGroupPath:"${Root}\${GroupName}" -Title:"${Title}"

Remove-Item $TempLocation
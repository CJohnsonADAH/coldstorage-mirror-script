#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################

Function My-Script-Directory {
Param ( $Command, $File=$null )

    $Source = ( $Command.Source | Get-Item -Force )
    $Path = ( $Source.Directory | Get-Item -Force )

    If ( $File -ne $null ) {
        $Path = ($Path.FullName + "\" + $File)
    }

    $Path
}

$global:gLockssPluginPropertiesModuleCmd = $MyInvocation.MyCommand

If ( $global:gScriptContextName -eq $null ) {
    $global:gScriptContextName = $global:gLockssPluginPropertiesModuleCmd 
    $global:gModuleContextName = $global:gLockssPluginPropertiesModuleCmd 
}
Else {
    $global:gModuleContextName = "${global:gScriptContextName}:${global:gLockssPluginPropertiesModuleCmd}"
}

Import-Module -Verbose:$false  $( My-Script-Directory -Command $global:gLockssPluginPropertiesModuleCmd -File "ColdStorageSettings.psm1" )

#############################################################################################################
## PUBLIC FUNCTIONS: CREDENTIALS TO CONNECT TO DROP SERVER ##################################################
#############################################################################################################

Function Get-LockssPluginXML {
Param( [Parameter(ValueFromPipeline=$true)] $Item, [switch] $ReturnObject=$false )

    Begin { }

    Process {
        If ( $Item.Name -like "*.xml" ) {
            $sXML = ( Get-Content -LiteralPath $Item.FullName -Raw )
            If ( $ReturnObject ) {
                [xml] $sXML
            }
            Else {
                $sXML
            }
        }
    }

    End { }

}

Function Get-LockssPluginPropertyTypeCodesDictionary {
    @{
        "boolean"=@(5, [Bool]); "int"=@(2, [Long]); "long"=@(11, [Long]);
        "num_range"=@(8, [String]); "pos_int"=@(6, [Long]); "range"=@(7, [String]);
        "set"=@(9, [String]); "string"=@(1, [String]); "time_interval"=@(12, [String]); "url"=@(3, [uri]);
        "user_passwd"=@(10, [String]); "year"=@(4, [Int])
    }
}

Function Get-LockssPluginPropertyDataType {
Param ( [Parameter(ValueFromPipeline=$true)] $Line=$null, [String] $Name="", [Int] $Code=-1, [switch] $ReturnObject, [switch] $ReturnCode, [switch] $ReturnName, [switch] $ReturnType )

    Begin { $Dict = ( Get-LockssPluginPropertyTypeCodesDictionary ) }

    Process {
        If ( $Line -ne $null ) {

            $Pair = @()
            If ( $Line -is [String] ) {
                $Key = $Line.ToLower()
                If ( $Dict.ContainsKey($Line) ) {
                    $Pair = $Dict[$Line]
                }
            }
            ElseIf ( $Line -is [Int] ) {
                $Dict.Keys |% { $Row = $Dict[$_]; If ( $Row[0] -eq $Line ) { $Key = $_; $Pair = $Row } }
            }

            If ( $ReturnObject ) {
                [PSCustomObject] @{ "Name"=$Key; "Code"=$Pair[0]; "Type"=$Pair[1] }
            }
            ElseIf ( $ReturnType ) {
                $Pair[1]
            }
            ElseIf ( $ReturnCode ) {
                $Pair[0]
            }
            Else {
                $Key
            }

        }
    }

    End {
        If ( $Name.Length -gt 0 ) {
            $Name | Get-LockssPluginPropertyDataType -ReturnObject:$ReturnObject -ReturnType:$ReturnType -ReturnCode
        }
        If ( $Code -gt -1 ) {
            $Code | Get-LockssPluginPropertyDataType -ReturnObject:$ReturnObject -ReturnType:$ReturnType -ReturnName
        }
    }

}

Function Get-LockssPluginInterpolatedValue {
Param ( [Parameter(ValueFromPipeline=$true)] $Text, $Interpolate=$null )

    Begin { }

    Process {
        If ( $Text -is [String] ) {
            If ( $Text.Substring(0, 1) -eq '"' ) {
                $TextRemainder = $Text.Substring(1)
                $CloseQuotes = ( $TextRemainder.IndexOf('"') )
                If ( $CloseQuotes -ge 0 ) {
                    $TextTemplate = $TextRemainder.Substring(0, $CloseQuotes)
                    If ( ( $Interpolate -ne $null ) -and ( $TextTemplate.IndexOf('%') -ge 0 ) ) {
                        $Separator = $TextRemainder.Substring($CloseQuotes, 2)
                        $Parameters = ( ( $TextRemainder.Substring($CloseQuotes + 2).Trim() -split "," ) |% { $_.Trim() } )

                        $Parameters |% {

                            $sKey = $_
                            $sPlaceholder = "%s"
                            $InsertHere = $TextTemplate.IndexOf($sPlaceholder)
                            If ( $InsertHere -ge 0 ) {
                                $ParameterIsSet = ( $Interpolate -ne $null )
                                If ( $ParameterIsSet ) {
                                    $ParameterIsSet = $Interpolate.ContainsKey($sKey)
                                }

                                If ( $ParameterIsSet ) {
                                    $TextTemplate = ( $TextTemplate.Substring(0, $InsertHere) + ( "{0}" -f $Interpolate[$sKey] ) + $TextTemplate.Substring($InsertHere + $sPlaceholder.Length) )
                                }
                                Else {                                    
                                    $TextTemplate = ( $TextTemplate.Substring(0, $InsertHere) + ( '${' + "${sKey}" + '}' ) + $TextTemplate.Substring($InsertHere + $sPlaceholder.Length) )
                                }
                            }

                        }

                        $Text = $TextTemplate
                    }
                }
            }
        }
        $Text
    }

    End { }
}

Function ConvertTo-LockssPluginPropertyValue {
Param ( [Parameter(ValueFromPipeline=$true)] $Element, [System.Type] $DataType, [switch] $Value=$true, $Interpolate=$null )

    Begin { }

    Process {
        If ( $Value ) {
            If ( $DataType -eq $null ) {
                $Text = ( $Element.InnerText )
            }
            Else {
                $Text = ( $Element.InnerText -as $DataType )
            }
            
            $Text | Get-LockssPluginInterpolatedValue -Interpolate:$Interpolate
        }
        Else {
            $Element
        }
    }

    End { }
}

Function ConvertTo-LockssPluginProperties {
Param ( [Parameter(ValueFromPipeline=$true)] $Element, [switch] $Value, [switch] $KeyValue, $Interpolate=$null )

    Begin { }

    Process {
        If ( $KeyValue ) {

            $Key = $Element.Name
            $DataValue = $( Switch ( $Key.ToLower() ) {
                "type" { Get-LockssPluginPropertyDataType -Code $Element.InnerText -ReturnType }
                default { $Element | ConvertTo-LockssPluginPropertyValue -Value:$true -Interpolate:$Interpolate }
            } )

            @{ "${Key}"=@( $DataValue ) }
        }
        Else {
            $sElement = $Element.Name.ToLower()
            $tDataType = Get-LockssPluginPropertyDataType -Name $sElement -ReturnType

            Switch ( $sElement ) {
                "#document" { $Element.DocumentElement | ConvertTo-LockssPluginProperties -Value:$Value -Interpolate:$Interpolate }
                "map" {
                    $Hash = @{}

                    $Element.ChildNodes | ConvertTo-LockssPluginProperties -Value:$Value -Interpolate:$Interpolate |% {
                        $Hash = $Hash + $_
                    }
                    $Hash
                }

                "int" { $Element | ConvertTo-LockssPluginPropertyValue -DataType $tDataType -Value:$Value -Interpolate:$Interpolate }
                "long" { $Element | ConvertTo-LockssPluginPropertyValue -DataType $tDataType -Value:$Value -Interpolate:$Interpolate }
                "num_range" { $Element | ConvertTo-LockssPluginPropertyValue -DataType $tDataType -Value:$Value -Interpolate:$Interpolate }
                "pos_int" { $Element | ConvertTo-LockssPluginPropertyValue -DataType $tDataType -Value:$Value -Interpolate:$Interpolate }
                "range" { $Element | ConvertTo-LockssPluginPropertyValue -DataType $tDataType -Value:$Value -Interpolate:$Interpolate }
                "set" { $Element | ConvertTo-LockssPluginPropertyValue -DataType $tDataType -Value:$Value -Interpolate:$Interpolate }
                "string" { $Element | ConvertTo-LockssPluginPropertyValue -DataType $tDataType -Value:$Value -Interpolate:$Interpolate }
                "url" { $Element | ConvertTo-LockssPluginPropertyValue -DataType $tDataType -Value:$Value -Interpolate:$Interpolate }
                "user_passwd" { $Element | ConvertTo-LockssPluginPropertyValue -DataType $tDataType -Value:$Value -Interpolate:$Interpolate }
                "year" { $Element | ConvertTo-LockssPluginPropertyValue -DataType $tDataType -Value:$Value -Interpolate:$Interpolate }

                "list" { @( $Element.ChildNodes | ConvertTo-LockssPluginProperties -Value:$Value -Interpolate:$Interpolate ) }

                "org.lockss.daemon.ConfigParamDescr" {
                    $Props = @{}
                    @( $Element.ChildNodes | ConvertTo-LockssPluginProperties -KeyValue -Interpolate:$Interpolate ) |% {
                        $Props = $Props + $_
                    }
                    [PSCustomObject] $Props
                }

                "entry" {
                    $key = ( $Element.ChildNodes[0] | ConvertTo-LockssPluginProperties -Value -Interpolate:$Interpolate )
                    $DataValue = ( $Element.ChildNodes[1] | ConvertTo-LockssPluginProperties -Value -Interpolate:$Interpolate )

                    @{ "${key}"=@( $DataValue ) }
                }

                default { Write-Warning ( "[${global:gScriptContextName}:ConvertTo-LockssPluginProperties] XML element not understood: {0}" -f $Element.Name ) }
            }
        }
    }

    End { }

}

Export-ModuleMember -Function Get-LockssPluginXML
Export-ModuleMember -Function ConvertTo-LockssPluginProperties
Export-ModuleMember -Function Get-LockssPluginPropertyDataType
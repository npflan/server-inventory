#Install-Module -Name Posh-SSH
cls

[bool]$UseCache = $false
[String]$NetBoxApiBaseURL = 'https://netbox.minserver.dk/api/'

if(!$UseCache)
{
    Get-Item -Path "Inventory\*" | Remove-Item -Force
}

Get-Item -Path "Error\*" | Remove-Item -Force

if($credsNetbox -eq $null)
{
    $credsNetbox = Get-Credential -Message "Type login information to Netbox"
}

$OverviewList = @()
"Getting C7000 Enclosures from NetBox..."
[string]$BladeCenterDeviceTypeId = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/device-types" -Credential $credsNetbox).results | ? {$_.model -eq "C7000 Bladecenter"} | Select -ExpandProperty Id
$AllDevices = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/devices?limit=9999" -Credential $credsNetbox).results
$Enclosures = $AllDevices | ? {$_.device_type.id -eq $BladeCenterDeviceTypeId} | Select id, name, platform, serial, @{n='primary_ipv4_address';e={$_.primary_ip4.address.replace('/24','')}}, comment | sort primary_ipv4_address
$AllEnclosureBays = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/device-bays?limit=9999" -Credential $credsNetbox).results | ? {$_.device.id -in $Enclosures.Id} | Select id, device, name, description, installed_device

"Running loop over enclosures..."
if($credsBladeEnclosure -eq $null)
{
    $credsBladeEnclosure = Get-Credential -Message "Type login information to HP System Administrator"
}

foreach($Enclosure in ($Enclosures | ? {$_.primary_ipv4_address -ne $null}))
{
    " - Enclosure $($Enclosure.primary_ipv4_address)"
    $EnclosureInfo = $null
    if(!$UseCache)
    {
        $ses = New-SSHSession -ComputerName $Enclosure.primary_ipv4_address -Credential $credsBladeEnclosure -AcceptKey
        $EnclosureInfo = (Invoke-SSHCommand -SSHSession $ses -Command "show enclosure info").Output
        $EnclosureInfo | Set-Content -Path "Inventory\$($Enclosure.primary_ipv4_address)_EnclosureInfo.txt"
    }
    else
    {
        $EnclosureInfo = Get-Content -Path "Inventory\$($Enclosure.primary_ipv4_address)_EnclosureInfo.txt"
    }

    $EnclosureData = [Regex]::Matches($EnclosureInfo, "Enclosure Name: (?<EnclosureName>[\w ]+)([\S\s]+?)Enclosure Type: (?<EnclosureType>[\w ]+)([\S\s]+?)Serial Number: (?<SerialNumber>[\w ]+)").Groups | Select Name, Value
    $EnclosureData_EnclosureName = ($EnclosureData | ? {$_.Name -eq 'EnclosureName'}).Value.Trim()
    $EnclosureData_EnclosureType = ($EnclosureData | ? {$_.Name -eq 'EnclosureType'}).Value.Trim()
    $EnclosureData_SerialNumber = ($EnclosureData | ? {$_.Name -eq 'SerialNumber'}).Value.Trim()

    if($EnclosureData_EnclosureName -ne $Enclosure.name)
    {
        " - - Patching enclosure name from: $($Enclosure.name) to: $($EnclosureData_EnclosureName)"
    }

    if($EnclosureData_EnclosureType -ne $Enclosure.platform)
    {
        " - - Patching enclosure name platform: $($Enclosure.platform) to: $($EnclosureData_EnclosureType)"
    }

    if($EnclosureData_SerialNumber -ne $Enclosure.serial)
    {
        " - - Patching enclosure serial from: $($Enclosure.serial) to: $($EnclosureData_SerialNumber)"
    }

    " - - Fetching bays..."
    $EnclosureBays = $AllEnclosureBays | ? {$_.device.id -eq $Enclosure.Id}

    foreach($EnclosureBay in $EnclosureBays)
    {
        " - - - Bay: $($EnclosureBay.name)"
        if(!$UseCache)
        {
            $EnclosureBayInfo = (Invoke-SSHCommand -SSHSession $ses -Command "show server info $($EnclosureBay.name)").Output
            $EnclosureBayInfo | Set-Content -Path "Inventory\$($Enclosure.primary_ipv4_address)_Bay_$($EnclosureBay.name).txt"
        }
        else
        {
            $EnclosureBayInfo = Get-Content -Path "Inventory\$($Enclosure.primary_ipv4_address)_Bay_$($EnclosureBay.name).txt"
        }
        
        if([Regex]::IsMatch($EnclosureBayInfo, "Server Blade Type: No Server Blade Installed"))
        {
            " - - - - Bay is empty..."

            if($EnclosureBay.installed_device.id -ne $null)
            {
                Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Remove device from bay"
            }
            continue
        }

        if([Regex]::IsMatch($EnclosureBayInfo, "Type: Storage Blade"))
        {
            " - - - - Storage Blade"

            $EnclosureBayData = [Regex]::Matches($EnclosureBayInfo, "Product Name: (?<ProductName>[\w \.@()]+)[\S\s]+?Serial Number: (?<SerialNumber>[\w \.@()?]+)[\S\s]+?").Groups
            $EnclosureBayData_ProductName = ($EnclosureBayData | ? {$_.Name -eq 'ProductName'}).Value.Trim()
            $EnclosureBayData_SerialNumber = ($EnclosureBayData | ? {$_.Name -eq 'SerialNumber'}).Value.Trim()

            if([string]::IsNullOrWhiteSpace($EnclosureBayData_SerialNumber))
            {
                Write-Host " - - - - Device has no serial number!, can't sync device!" -ForegroundColor Red
                continue
            }
            $PutDeviceInBay = $false

            if($EnclosureBay.installed_device.id -ne $null)
            {
                $DeviceInBay = $AllDevices | ? {$_.Id -eq $EnclosureBay.installed_device.id}
                if($DeviceInBay.serial -ne $EnclosureBayData_SerialNumber)
                {
                    Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Remove device from bay"
                    $PutDeviceInBay = $true
                }
            }
            else
            {
                $PutDeviceInBay = $true
            }

            $FoundDevice = $AllDevices | ? {$_.serial -eq $EnclosureBayData_SerialNumber}
            if($FoundDevice -eq $null)
            {
                Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Create device"
                #set FoundDevice for put and update command
            }

            if($PutDeviceInBay)
            {
                Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Put device in bay"
            }

            Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Update device"
            continue
        }

        $EnclosureBayData = [Regex]::Matches($EnclosureBayInfo, "Product Name: (?<ProductName>[\w \.@()]+)[\S\s]+?Serial Number: (?<SerialNumber>[\w \.@()?]+)[\S\s]+?Server Name: (?<ServerName>[\w \.@()]+)[\S\s]+?Asset Tag: (?<AssetTag>[\w \.@()\[\]]+)[\S\s]+?CPU 1: (?<CPU1>[\w \.@()-]+)[\S\s]+?CPU 2: (?<CPU2>[\w \.@()-]+)[\S\s]+?Memory: (?<Memory>[\w \.@()]+)[\S\s]+?Flex[\S\s]+Ethernet[\S\s]+(LOM[1]{0,1}:1-a|NIC 1:|Port 1:)[\s]+(?<NIC1_MAC>([0-9A-F]{2}[:-]){5}[0-9A-F]{2})[\S\s]+?(LOM[1]{0,1}:2-a|NIC 2:|Port 2:)[\s]+(?<NIC2_MAC>([0-9A-F]{2}[:-]){5}[0-9A-F]{2})[\S\s]+?Management Processor[\S\s]+?Type: (?<ManagementType>[\w \.@()]+)[\S\s]+?IP Address: (?<ManagementIP>[\w \.@()]+)").Groups
        if($EnclosureBayData.Count -lt 8)
        {
            Write-Host  -ForegroundColor Red " - - - - Regex Error: Not enough groups found!"
            $EnclosureBayInfo | Set-Content -Path "Error\$($Enclosure.primary_ipv4_address)_Bay_$($EnclosureBay.name).txt"
            continue
        }

        $EnclosureBayData_ProductName = ($EnclosureBayData | ? {$_.Name -eq 'ProductName'}).Value.Trim()
        $EnclosureBayData_SerialNumber = ($EnclosureBayData | ? {$_.Name -eq 'SerialNumber'}).Value.Trim()
        $EnclosureBayData_ServerName = ($EnclosureBayData | ? {$_.Name -eq 'ServerName'}).Value.Trim()
        $EnclosureBayData_AssetTag = ($EnclosureBayData | ? {$_.Name -eq 'AssetTag'}).Value.Trim()
        $EnclosureBayData_CPU1 = ($EnclosureBayData | ? {$_.Name -eq 'CPU1'}).Value.Trim()
        $EnclosureBayData_CPU2 = ($EnclosureBayData | ? {$_.Name -eq 'CPU2'}).Value.Trim()
        $EnclosureBayData_Memory = ($EnclosureBayData | ? {$_.Name -eq 'Memory'}).Value.Trim()
        $EnclosureBayData_NIC1_MAC = ($EnclosureBayData | ? {$_.Name -eq 'NIC1_MAC'}).Value.Trim()
        $EnclosureBayData_NIC2_MAC = ($EnclosureBayData | ? {$_.Name -eq 'NIC2_MAC'}).Value.Trim()
        $EnclosureBayData_ManagementType = ($EnclosureBayData | ? {$_.Name -eq 'ManagementType'}).Value.Trim()
        $EnclosureBayData_ManagementIP = ($EnclosureBayData | ? {$_.Name -eq 'ManagementIP'}).Value.Trim()

            
        if([string]::IsNullOrWhiteSpace($EnclosureBayData_SerialNumber))
        {
            Write-Host " - - - - Device has no serial number!, can't sync device!" -ForegroundColor Red
            continue
        }

        $PutDeviceInBay = $false
        if($EnclosureBay.installed_device.id -ne $null)
        {
            $DeviceInBay = $AllDevices | ? {$_.Id -eq $EnclosureBay.installed_device.id}
            if($DeviceInBay.serial -ne $EnclosureBayData_SerialNumber)
            {
                Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Remove device from bay"
                $PutDeviceInBay = $true
            }
        }
        else
        {
            $PutDeviceInBay = $true
        }

        $FoundDevice = $AllDevices | ? {$_.serial -eq $EnclosureBayData_SerialNumber}
        if($FoundDevice -eq $null)
        {
            Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Create device"
            #set FoundDevice for put and update command
        }

        if($PutDeviceInBay)
        {
            Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Put device in bay"
        }

        Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Update device"

        #Debug stuff
        if([string]::IsNullOrWhiteSpace($EnclosureBayData_AssetTag) -or $EnclosureBayData_AssetTag -eq '[Unknown]')
        {
            Write-Host -ForegroundColor Red " - - - - Missing assettag"
        }

            #overview
            $OverviewList += [pscustomobject]@{
            Enclosure_Name = $EnclosureData_EnclosureName
            Enclosure_IP = $Enclosure.primary_ipv4_address
            Bay = $($EnclosureBay.name)
            ProductName = $EnclosureBayData_ProductName
            SerialNumber = $EnclosureBayData_SerialNumber
            ServerName = $EnclosureBayData_ServerName
            AssetTag = $EnclosureBayData_AssetTag
            CPU1 = $EnclosureBayData_CPU1
            CPU2 = $EnclosureBayData_CPU2
            Memory = $EnclosureBayData_Memory
            NIC1_MAC = $EnclosureBayData_NIC1_MAC
            NIC2_MAC = $EnclosureBayData_NIC2_MAC
            ManagementType = $EnclosureBayData_ManagementType
            ManagementIP = $EnclosureBayData_ManagementIP}
    }

    if(!$UseCache)
    {
        Remove-SSHSession -SSHSession $ses > $null
    }

    #break
}

Get-Item Overview.csv | Remove-Item -Force
$OverviewList | Export-Csv -Delimiter ';' -Path Overview.csv -NoClobber -NoTypeInformation

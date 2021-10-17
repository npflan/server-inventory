#Install-Module -Name Posh-SSH
Clear-Host
[int]$CurrentSite = 1
[bool]$UseCache = $false
[String]$NetBoxApiBaseURL = 'https://netbox.minserver.dk/api/'

if (!$UseCache) {
    Get-Item -Path "Inventory\*" | Remove-Item -Force
}

Get-Item -Path "Error\*" | Remove-Item -Force

if ($NetBoxToken -eq $null) {
    $NetBoxToken = Read-Host "Please type NetBox API Key"
}

$NetBoxTokenHeader = @{Authorization = "token $($NetBoxToken)"}

$CPUInfos = @(
    @{Name = 'AMD Opteron(tm) Processor 6134 (8 cores)'; Speed = 2.30; Cores = 8; HyperThreading = $false; }
    @{Name = 'AMD Opteron(tm) Processor 6172 (12 cores)'; Speed = 2.10; Cores = 12; HyperThreading = $false; }
    @{Name = 'AMD Opteron(tm) Processor 6174 (12 cores)'; Speed = 2.20; Cores = 12; HyperThreading = $false; }
    @{Name = 'AMD Opteron(tm) Processor 6308 (4 cores)'; Speed = 3.50; Cores = 4; HyperThreading = $false; }
    @{Name = 'Intel(R) Xeon(R) CPU E5-2650 0 @ 2.00GHz (8 cores)'; Speed = 2.00; Cores = 8; HyperThreading = $true; }
    @{Name = 'Intel(R) Xeon(R) CPU E5-2670 0 @ 2.60GHz (8 cores)'; Speed = 2.60; Cores = 8; HyperThreading = $true; }
    @{Name = 'Intel(R) Xeon(R) CPU E5520 @ 2.27GHz (4 cores)'; Speed = 2.27; Cores = 4; HyperThreading = $true; }
    @{Name = 'Intel(R) Xeon(R) CPU E5540 @ 2.53GHz (4 cores)'; Speed = 2.53; Cores = 4; HyperThreading = $true; }
    @{Name = 'Intel(R) Xeon(R) CPU E5620 @ 2.40GHz (4 cores)'; Speed = 2.40; Cores = 4; HyperThreading = $true; }
    @{Name = 'Intel(R) Xeon(R) CPU E5640 @ 2.67GHz (4 cores)'; Speed = 2.67; Cores = 4; HyperThreading = $true; }
    @{Name = 'Intel(R) Xeon(R) CPU L5520 @ 2.27GHz (4 cores)'; Speed = 2.27; Cores = 4; HyperThreading = $true; }
    @{Name = 'Intel(R) Xeon(R) CPU L5630 @ 2.13GHz (4 cores)'; Speed = 2.13; Cores = 4; HyperThreading = $true; }
    @{Name = 'Intel(R) Xeon(R) CPU X5550 @ 2.67GHz (4 cores)'; Speed = 2.67; Cores = 4; HyperThreading = $true; }
    @{Name = 'Intel(R) Xeon(R) CPU X5650 @ 2.67GHz (6 cores)'; Speed = 2.67; Cores = 6; HyperThreading = $true; }
    @{Name = 'Intel(R) Xeon(R) CPU X5670 @ 2.93GHz (6 cores)'; Speed = 2.93; Cores = 6; HyperThreading = $true; }
    @{Name = 'Intel(R) Xeon(R) CPU X5675 @ 3.07GHz (6 cores)'; Speed = 3.07; Cores = 6; HyperThreading = $true; }
)

#Get DHCP Reservations
$DHCPReservations = @()
$DHCPReservations += (Invoke-RestMethod -Method Get -Uri 'https://raw.githubusercontent.com/npflan/serverteam-dhcp/master/config/reservation.ip.10.100.101.0.json').reservations
$DHCPReservations += (Invoke-RestMethod -Method Get -Uri 'https://raw.githubusercontent.com/npflan/serverteam-dhcp/master/config/reservation.ip.10.100.102.0.json').reservations
$DHCPReservations += (Invoke-RestMethod -Method Get -Uri 'https://raw.githubusercontent.com/npflan/serverteam-dhcp/master/config/reservation.ip.10.100.103.0.json').reservations
$DHCPReservations += (Invoke-RestMethod -Method Get -Uri 'https://raw.githubusercontent.com/npflan/serverteam-dhcp/master/config/reservation.ip.10.100.201.0.json').reservations

$OverviewList = @()
"Getting C7000 Enclosures from NetBox..."
$DeviceTypes = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/device-types/?limit=9999" -Headers $NetBoxTokenHeader).results
[string]$BladeCenterDeviceTypeId = $DeviceTypes | Where-Object {$_.model -eq "C7000 Bladecenter"} | Select-Object -ExpandProperty Id
$AllDevices = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/devices/?limit=9999" -Headers $NetBoxTokenHeader).results
$Enclosures = $AllDevices | Where-Object {$_.device_type.id -eq $BladeCenterDeviceTypeId -and $_.site.id -eq $CurrentSite} | Select-Object id, name, platform, serial, @{n = 'primary_ipv4_address'; e = {$_.primary_ip4.address.replace('/24', '')}}, comment | sort primary_ipv4_address
$AllEnclosureBays = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/device-bays/?limit=9999" -Headers $NetBoxTokenHeader).results | Where-Object {$_.device.id -in $Enclosures.Id} | Select id, device, name, description, installed_device

"Running loop over enclosures..."
if ($credsBladeEnclosure -eq $null) {
    $credsBladeEnclosure = Get-Credential -Message "Type login information to HP System Administrator"
}

foreach ($Enclosure in ($Enclosures | Where-Object {$_.primary_ipv4_address -ne $null})) {
    # -and $_.primary_ipv4_address -eq "10.100.202.121"
    " - Enclosure $($Enclosure.primary_ipv4_address)"
    $EnclosureInfo = $null
    if (!$UseCache) {
        $ses = New-SSHSession -ComputerName $Enclosure.primary_ipv4_address -Credential $credsBladeEnclosure -AcceptKey
        $EnclosureInfo = (Invoke-SSHCommand -SSHSession $ses -Command "show enclosure info").Output
        $EnclosureInfo | Set-Content -Path "Inventory\$($Enclosure.primary_ipv4_address)_EnclosureInfo.txt"
    }
    else {
        $EnclosureInfo = Get-Content -Path "Inventory\$($Enclosure.primary_ipv4_address)_EnclosureInfo.txt"
    }

    $EnclosureData = [Regex]::Matches($EnclosureInfo, "Enclosure Name: (?<EnclosureName>[\w ]+)([\S\s]+?)Enclosure Type: (?<EnclosureType>[\w ]+)([\S\s]+?)Serial Number: (?<SerialNumber>[\w ]+)").Groups | Select Name, Value
    $EnclosureData_EnclosureName = ($EnclosureData | Where-Object {$_.Name -eq 'EnclosureName'}).Value.Trim()
    $EnclosureData_EnclosureType = ($EnclosureData | Where-Object {$_.Name -eq 'EnclosureType'}).Value.Trim()
    $EnclosureData_SerialNumber = ($EnclosureData | Where-Object {$_.Name -eq 'SerialNumber'}).Value.Trim()

    if ($EnclosureData_EnclosureName -ne $Enclosure.name) {
        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching enclosure name from: $($Enclosure.name) to: $($EnclosureData_EnclosureName)"
        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/devices/$($Enclosure.id)/" -ContentType "application/json" -Body (@{name = $EnclosureData_EnclosureName; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
    }

    if ($EnclosureData_SerialNumber -ne $Enclosure.serial) {
        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching enclosure serial from: $($Enclosure.serial) to: $($EnclosureData_SerialNumber)"
        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/devices/$($Enclosure.id)/" -ContentType "application/json" -Body (@{serial = $EnclosureData_SerialNumber; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
    }

    " - - Fetching bays..."
    $EnclosureBays = $AllEnclosureBays | Where-Object {$_.device.id -eq $Enclosure.Id}

    foreach ($EnclosureBay in $EnclosureBays) {
        " - - - Bay: $($EnclosureBay.name)"

        #region Cache Settings
        if (!$UseCache) {
            $EnclosureBayInfo = (Invoke-SSHCommand -SSHSession $ses -Command "show server info $($EnclosureBay.name)").Output
            $EnclosureBayInfo | Set-Content -Path "Inventory\$($Enclosure.primary_ipv4_address)_Bay_$($EnclosureBay.name).txt"
        }
        else {
            $EnclosureBayInfo = Get-Content -Path "Inventory\$($Enclosure.primary_ipv4_address)_Bay_$($EnclosureBay.name).txt"
        }
        #endregion
        
        #region Empty bay
        if ([Regex]::IsMatch($EnclosureBayInfo, "Server Blade Type: No Server Blade Installed")) {
            Write-Host " - - - - Bay is empty..."

            if ($EnclosureBay.installed_device.id -ne $null) {
                Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Remove device from bay"
                Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/device-bays/$($EnclosureBay.id)/" -ContentType "application/json" -Body (@{device = $Enclosure.id; name = $EnclosureBay.name; installed_device = $null} | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
            }
            continue
        }
        #endregion

        #region Storage Blade
        if ([Regex]::IsMatch($EnclosureBayInfo, "Type: Storage Blade")) {
            Write-Host " - - - - Storage Blade"

            $EnclosureBayData = [Regex]::Matches($EnclosureBayInfo, "Product Name: (?<ProductName>[\w \.@()]+)[\S\s]+?Serial Number: (?<SerialNumber>[\w \.@()?]+)[\S\s]+?").Groups
            $EnclosureBayData_ProductName = ($EnclosureBayData | Where-Object {$_.Name -eq 'ProductName'}).Value.Trim()
            $EnclosureBayData_SerialNumber = ($EnclosureBayData | Where-Object {$_.Name -eq 'SerialNumber'}).Value.Trim()

            if ([string]::IsNullOrWhiteSpace($EnclosureBayData_SerialNumber) -eq $false) {
                $FoundDevice = $AllDevices | Where-Object {$_.serial -eq $EnclosureBayData_SerialNumber}
                if ($FoundDevice -eq $null -and [string]::IsNullOrWhiteSpace($EnclosureBayData_SerialNumber) -eq $false) {
                    Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Create device"
                    $body = @{
                        name        = $EnclosureBayData_SerialNumber; 
                        serial      = $EnclosureBayData_SerialNumber; 
                        device_type = 34; 
                        device_role = 10; 
                        site        = $CurrentSite;
                    } | ConvertTo-Json -Compress
                    Invoke-RestMethod -Method Post -Uri "$($NetBoxApiBaseURL)dcim/devices/" -ContentType "application/json" -Body $body -Header $NetBoxTokenHeader | Out-Null

                    $AllDevices = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/devices/?limit=9999" -Header $NetBoxTokenHeader).results
                    #find using serial number
                    if ([string]::IsNullOrWhiteSpace($EnclosureBayData_SerialNumber) -eq $false) {
                        $FoundDevice = $AllDevices | Where-Object {$_.serial -eq $EnclosureBayData_SerialNumber}
                    }
                }
                if ($FoundDevice -eq $null -and $EnclosureBay.installed_device.id -ne $null) {
                    Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Remove device from bay"
                    Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/device-bays/$($EnclosureBay.id)/" -ContentType "application/json" -Body (@{device = $Enclosure.id; name = $EnclosureBay.name; installed_device = $null} | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                }
                elseif ($FoundDevice -ne $null -and $EnclosureBay.  installed_device.id -ne $FoundDevice.id) {
                    Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Insert device in bay"
                    Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/device-bays/$($EnclosureBay.id)/" -ContentType "application/json" -Body (@{device = $Enclosure.id; name = $EnclosureBay.name; installed_device = $FoundDevice.id} | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                }
                if ($FoundDevice -ne $null) {
                    if ([string]::IsNullOrWhiteSpace($EnclosureBayData_SerialNumber) -eq $false -and $EnclosureBayData_SerialNumber -ne $FoundDevice.name) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching name from: $($FoundDevice.name) to: $($EnclosureBayData_SerialNumber)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/devices/$($FoundDevice.id)/" -ContentType "application/json" -Body (@{name = $EnclosureBayData_SerialNumber; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                    if ([string]::IsNullOrWhiteSpace($EnclosureBayData_SerialNumber) -eq $false -and $EnclosureBayData_SerialNumber -ne $FoundDevice.serial) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching serial from: $($FoundDevice.serial) to: $($EnclosureBayData_SerialNumber)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/devices/$($FoundDevice.id)/" -ContentType "application/json" -Body (@{serial = $EnclosureBayData_SerialNumber; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                    #Update site
                    if ($FoundDevice.site.id -ne $CurrentSite) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching site from: $($FoundDevice.site.id) to: $($CurrentSite)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/devices/$($FoundDevice.id)/" -ContentType "application/json" -Body (@{site = $CurrentSite; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                }
            }
            else {
                Write-Host -ForegroundColor Red " - - - - Serial number is missing..."
                if ($EnclosureBay.installed_device.id -ne $null) {
                    Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Remove device from bay"
                    Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/device-bays/$($EnclosureBay.id)/" -ContentType "application/json" -Body (@{device = $Enclosure.id; name = $EnclosureBay.name; installed_device = $null} | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                }
            }
        }
        #endregion

        #region Server Blade
        if ([Regex]::IsMatch($EnclosureBayInfo, "Type: Server Blade")) {
            Write-Host " - - - - Server Blade"

            $EnclosureBayData = [Regex]::Matches($EnclosureBayInfo, "Product Name: (?<ProductName>[\w \.@()]+)[\S\s]+?Serial Number: (?<SerialNumber>[\w \.@()?]+)[\S\s]+?Server Name: (?<ServerName>[\w \.@()]+)[\S\s]+?Asset Tag: (?<AssetTag>[\w \.@()\[\]]+)[\S\s]+?CPU 1: (?<CPU1>[\w \.@()-]+)[\S\s]+?CPU 2: (?<CPU2>[\w \.@()-]+)[\S\s]+?Memory: (?<Memory>[\w \.@()]+)[\S\s]+?Flex[\S\s]+Ethernet[\S\s]+(LOM[1]{0,1}:1-a|NIC 1:|Port 1:)[\s]+(?<NIC1_MAC>([0-9A-F]{2}[:-]){5}[0-9A-F]{2})[\S\s]+?(LOM[1]{0,1}:2-a|NIC 2:|Port 2:)[\s]+(?<NIC2_MAC>([0-9A-F]{2}[:-]){5}[0-9A-F]{2})[\S\s]+?Management Processor[\S\s]+?Type: (?<ManagementType>[\w \.@()]+)[\S\s]+?IP Address: (?<ManagementIP>[\w \.@()]+)").Groups
            if ($EnclosureBayData.Count -lt 8) {
                Write-Host  -ForegroundColor Red " - - - - Regex Error: Not enough groups found!"
                $EnclosureBayInfo | Set-Content -Path "Error\$($Enclosure.primary_ipv4_address)_Bay_$($EnclosureBay.name).txt"
                continue
            }

            $EnclosureBayData_ProductName = ($EnclosureBayData | Where-Object {$_.Name -eq 'ProductName'}).Value.Trim()
            $EnclosureBayData_SerialNumber = ($EnclosureBayData | Where-Object {$_.Name -eq 'SerialNumber'}).Value.Trim()
            $EnclosureBayData_ServerName = ($EnclosureBayData | Where-Object {$_.Name -eq 'ServerName'}).Value.Trim()
            $EnclosureBayData_AssetTag = ($EnclosureBayData | Where-Object {$_.Name -eq 'AssetTag'}).Value.Trim()
            $EnclosureBayData_CPU1 = ($EnclosureBayData | Where-Object {$_.Name -eq 'CPU1'}).Value.Trim()
            $EnclosureBayData_CPU2 = ($EnclosureBayData | Where-Object {$_.Name -eq 'CPU2'}).Value.Trim()
            $EnclosureBayData_Memory = ($EnclosureBayData | Where-Object {$_.Name -eq 'Memory'}).Value.Trim()
            $EnclosureBayData_NIC1_MAC = ($EnclosureBayData | Where-Object {$_.Name -eq 'NIC1_MAC'}).Value.Trim()
            $EnclosureBayData_NIC2_MAC = ($EnclosureBayData | Where-Object {$_.Name -eq 'NIC2_MAC'}).Value.Trim()
            $EnclosureBayData_ManagementType = ($EnclosureBayData | Where-Object {$_.Name -eq 'ManagementType'}).Value.Trim()
            $EnclosureBayData_ManagementIP = ($EnclosureBayData | Where-Object {$_.Name -eq 'ManagementIP'}).Value.Trim()

            #cleanup
            if ($EnclosureBayData_AssetTag -eq '[Unknown]')
            { $EnclosureBayData_AssetTag = ""}
            if ($EnclosureBayData_ServerName -eq 'host is unnamed')
            { $EnclosureBayData_ServerName = ""}
            
            #region Find Device
            $FoundDevice = $null
            #find using serial number
            if ([string]::IsNullOrWhiteSpace($EnclosureBayData_SerialNumber) -eq $false) {
                $FoundDevice = $AllDevices | Where-Object {$_.serial -eq $EnclosureBayData_SerialNumber}
            }
            #find using asset tag
            if ($FoundDevice -eq $null -and [string]::IsNullOrWhiteSpace($EnclosureBayData_AssetTag) -eq $false) {
                $FoundDevice = $AllDevices | Where-Object {$_.asset_tag -eq $EnclosureBayData_AssetTag}
            }
            #find by mac address on nic1
            if ($FoundDevice -eq $null -and [string]::IsNullOrWhiteSpace($EnclosureBayData_NIC1_MAC) -eq $false) {
                $foundInterface = (Invoke-RestMethod -Method Get -Uri "https://netbox.minserver.dk/api/dcim/interfaces/?mac_address=$($EnclosureBayData_NIC1_MAC.Replace(':',''))" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                if ($foundInterface -ne $null) {
                    $FoundDevice = $AllDevices | Where-Object {$_.id -eq $foundInterface.device.Id}
                }
            }

            #endregion

            #region Create Device
            if ($FoundDevice -eq $null -and ([string]::IsNullOrWhiteSpace($EnclosureBayData_SerialNumber) -eq $false -or [string]::IsNullOrWhiteSpace($EnclosureBayData_AssetTag) -eq $false -or [string]::IsNullOrWhiteSpace($EnclosureBayData_NIC1_MAC) -eq $false)) {
                Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Create device"
                if ([string]::IsNullOrWhiteSpace($EnclosureBayData_SerialNumber)) {
                    if ([string]::IsNullOrWhiteSpace($EnclosureBayData_AssetTag) -eq $false) {
                        $EnclosureBayData_SerialNumber = $EnclosureBayData_AssetTag
                    }
                    else {
                        $EnclosureBayData_SerialNumber = $EnclosureBayData_NIC1_MAC.Replace(':', '');
                    }
                }
                if ([string]::IsNullOrWhiteSpace($EnclosureBayData_ServerName)) {
                    if ([string]::IsNullOrWhiteSpace($EnclosureBayData_AssetTag) -eq $false) {
                        $EnclosureBayData_ServerName = $EnclosureBayData_AssetTag
                    }
                    else {
                        $EnclosureBayData_ServerName = $EnclosureBayData_NIC1_MAC.Replace(':', '');
                    }
                }
                if ([string]::IsNullOrWhiteSpace($EnclosureBayData_AssetTag)) {
                    $EnclosureBayData_AssetTag = $null
                }

                $DeviceType = $DeviceTypes | Where-Object {$_.model -eq $EnclosureBayData_ProductName.Replace('ProLiant', '').Replace('Gen8', 'G8').Trim()}
                if ($DeviceType -ne $null) {
                    $body = @{
                        name        = $EnclosureBayData_ServerName; 
                        serial      = $EnclosureBayData_SerialNumber; 
                        asset_tag   = $EnclosureBayData_AssetTag;
                        device_type = $DeviceType.Id; 
                        device_role = 11; 
                        site        = $CurrentSite;
                    } | ConvertTo-Json -Compress
                    Invoke-RestMethod -Method Post -Uri "$($NetBoxApiBaseURL)dcim/devices/" -ContentType "application/json" -Body $body -Header $NetBoxTokenHeader | Out-Null

                    $AllDevices = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/devices/?limit=9999" -Header $NetBoxTokenHeader).results
                    #find using serial number
                    if ([string]::IsNullOrWhiteSpace($EnclosureBayData_SerialNumber) -eq $false) {
                        $FoundDevice = $AllDevices | Where-Object {$_.serial -eq $EnclosureBayData_SerialNumber}
                    }
                    #find using asset tag
                    if ($FoundDevice -eq $null -and [string]::IsNullOrWhiteSpace($EnclosureBayData_AssetTag) -eq $false) {
                        $FoundDevice = $AllDevices | Where-Object {$_.asset_tag -eq $EnclosureBayData_AssetTag}
                    }

                    if ($FoundDevice -ne $null) {
                        #UpdateMACAddress
                        $eth0 = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/interfaces/?name=eth0&device_id=$($FoundDevice.Id)" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/interfaces/$($Eth0.id)/" -ContentType "application/json" -Body (@{device = $FoundDevice.id; name = "Eth0"; mac_address = $EnclosureBayData_NIC1_MAC} | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                        $eth1 = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/interfaces/?name=eth1&device_id=$($FoundDevice.Id)" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/interfaces/$($Eth1.id)/" -ContentType "application/json" -Body (@{device = $FoundDevice.id; name = "Eth1"; mac_address = $EnclosureBayData_NIC2_MAC} | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                }
                else {
                    Write-host -ForegroundColor Red " - - - - Error: DeviceType not found in netbox $($EnclosureBayData_ProductName)"
                }
            }
            #endregion

            #region put in chassis
            if ($FoundDevice -eq $null -and $EnclosureBay.installed_device.id -ne $null) {
                Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Remove device from bay"
                Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/device-bays/$($EnclosureBay.id)/" -ContentType "application/json" -Body (@{device = $Enclosure.id; name = $EnclosureBay.name; installed_device = $null} | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
            }
            elseif ($FoundDevice -ne $null -and $EnclosureBay.installed_device.id -ne $FoundDevice.id) {
                Write-Host  -ForegroundColor Yellow " - - - - NETBOX: Insert device in bay"
                Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/device-bays/$($EnclosureBay.id)/" -ContentType "application/json" -Body (@{device = $Enclosure.id; name = $EnclosureBay.name; installed_device = $FoundDevice.id} | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
            }
            #endregion
            
            #region Update
            if ($FoundDevice -ne $null) {
                if ([string]::IsNullOrWhiteSpace($EnclosureBayData_ServerName) -eq $false -and $EnclosureBayData_ServerName -ne $FoundDevice.name) {
                    Write-Host -ForegroundColor Yellow " - - NETBOX: Patching name from: $($FoundDevice.name) to: $($EnclosureBayData_ServerName)"
                    Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/devices/$($FoundDevice.id)/" -ContentType "application/json" -Body (@{name = $EnclosureBayData_ServerName; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                }
                if ([string]::IsNullOrWhiteSpace($EnclosureBayData_AssetTag) -eq $false -and $EnclosureBayData_AssetTag -ne $FoundDevice.asset_tag) {
                    Write-Host -ForegroundColor Yellow " - - NETBOX: Patching asset_tag from: $($FoundDevice.asset_tag) to: $($EnclosureBayData_AssetTag)"
                    Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/devices/$($FoundDevice.id)/" -ContentType "application/json" -Body (@{asset_tag = $EnclosureBayData_AssetTag; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                }
                if ([string]::IsNullOrWhiteSpace($EnclosureBayData_SerialNumber) -eq $false -and $EnclosureBayData_SerialNumber -ne $FoundDevice.serial) {
                    Write-Host -ForegroundColor Yellow " - - NETBOX: Patching serial from: $($FoundDevice.serial) to: $($EnclosureBayData_SerialNumber)"
                    Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/devices/$($FoundDevice.id)/" -ContentType "application/json" -Body (@{serial = $EnclosureBayData_SerialNumber; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                }
                #Update site
                if ($FoundDevice.site.id -ne $CurrentSite) {
                    Write-Host -ForegroundColor Yellow " - - NETBOX: Patching site from: $($FoundDevice.site.id) to: $($CurrentSite)"
                    Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/devices/$($FoundDevice.id)/" -ContentType "application/json" -Body (@{site = $CurrentSite; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                }
                $eth0 = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/interfaces/?name=eth0&device_id=$($FoundDevice.Id)" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                if ($eth0.Id -eq $null) {
                    $eth0 = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/interfaces/?name=Eth0&device_id=$($FoundDevice.Id)" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                }
                if ([string]::IsNullOrWhiteSpace($EnclosureBayData_NIC1_MAC) -eq $false -and $EnclosureBayData_NIC1_MAC -ne $eth0.mac_address) {
                    Write-Host -ForegroundColor Yellow " - - NETBOX: Patching eth0 mac from: $($eth0.mac_address) to: $($EnclosureBayData_NIC1_MAC)"
                    Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/interfaces/$($eth0.id)/" -ContentType "application/json" -Body (@{device = $FoundDevice.id; name = "Eth0"; mac_address = $EnclosureBayData_NIC1_MAC} | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                }
                $eth1 = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/interfaces/?name=eth1&device_id=$($FoundDevice.Id)" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                if ($eth1.Id -eq $null) {
                    $eth1 = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/interfaces/?name=Eth1&device_id=$($FoundDevice.Id)" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                }
                if ([string]::IsNullOrWhiteSpace($EnclosureBayData_NIC2_MAC) -eq $false -and $EnclosureBayData_NIC2_MAC -ne $eth1.mac_address) {
                    Write-Host -ForegroundColor Yellow " - - NETBOX: Patching eth1 mac from: $($eth1.mac_address) to: $($EnclosureBayData_NIC2_MAC)"
                    Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/interfaces/$($eth1.id)/" -ContentType "application/json" -Body (@{device = $FoundDevice.id; name = "Eth1"; mac_address = $EnclosureBayData_NIC2_MAC} | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                }

                #writing IP's
                $eth0_ip = ($DHCPReservations | Where-Object {$_.'hw-address' -eq $EnclosureBayData_NIC1_MAC}).'ip-address'
                if ([string]::IsNullOrWhiteSpace($eth0_ip) -eq $false) {
                    $nb_eth0_ip = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)ipam/ip-addresses/?address=$($eth0_ip)" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                    if ($nb_eth0_ip.id -eq $null) {
                        Write-host -ForegroundColor Yellow " - - NETBOX: Create IP: $($eth0_ip)"
                        Invoke-RestMethod -Method Post -Uri "$($NetBoxApiBaseURL)ipam/ip-addresses/" -ContentType "application/json" -Body (@{
                                address   = "$($eth0_ip)/24";
                                interface = $eth0.id;
                            } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                    elseif($nb_eth0_ip.interface.id -ne $eth0.id){
                        Write-host -ForegroundColor Yellow " - - NETBOX: Patching IP to device : $($eth0_ip)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)ipam/ip-addresses/$($nb_eth0_ip.id)/" -ContentType "application/json" -Body (@{
                            interface = $eth0.id;
                        } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                }

                $eth1_ip = ($DHCPReservations | Where-Object {$_.'hw-address' -eq $EnclosureBayData_NIC2_MAC}).'ip-address'
                if ([string]::IsNullOrWhiteSpace($eth1_ip) -eq $false) {
                    $nb_eth1_ip = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)ipam/ip-addresses/?address=$($eth1_ip)" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                    if ($nb_eth1_ip.id -eq $null) {
                        Write-host -ForegroundColor Yellow " - - NETBOX: Create IP: $($eth1_ip)"
                        Invoke-RestMethod -Method Post -Uri "$($NetBoxApiBaseURL)ipam/ip-addresses/" -ContentType "application/json" -Body (@{
                                address   = "$($eth1_ip)/24";
                                interface = $eth1.id;
                            } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                    elseif($nb_eth1_ip.interface.id -ne $eth1.id){
                        Write-host -ForegroundColor Yellow " - - NETBOX: Patching IP to device : $($eth1_ip)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)ipam/ip-addresses/$($nb_eth1_ip.id)/" -ContentType "application/json" -Body (@{
                            interface = $eth1.id;
                        } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                }

                #region Inventory
                $Proc1 = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/?device_id=$($FoundDevice.Id)&tag=Proc1" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                $Proc1Description = "Processor 1"
                if ([string]::IsNullOrWhiteSpace($EnclosureBayData_CPU1) -eq $false -and $EnclosureBayData_CPU1 -notlike "*present*") {
                    $ManufactureId = 10 #Intel
                    if ($EnclosureBayData_CPU1 -like "*AMD*") {
                        $ManufactureId = 11 #AMD
                    }
                    if ($Proc1.id -eq $null) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Creating Inventory Proc1"
                        Invoke-RestMethod -Method Post -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/" -ContentType "application/json" -Body (@{
                                name         = $EnclosureBayData_CPU1;
                                manufacturer = $ManufactureId;
                                device       = $FoundDevice.Id;
                                description  = $Proc1Description;
                                tags         = @("Proc1");
                            } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                    else {
                        if ($EnclosureBayData_CPU1 -ne $Proc1.name) {
                            Write-Host -ForegroundColor Yellow " - - NETBOX: Patching Proc1 name from: $($Proc1.name) to: $($EnclosureBayData_CPU1)"
                            Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($Proc1.id)/" -ContentType "application/json" -Body (@{name = $EnclosureBayData_CPU1; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                        }
                        if ($ManufactureId -ne $Proc1.manufacturer.id) {
                            Write-Host -ForegroundColor Yellow " - - NETBOX: Patching Proc1 manufacturer from: $($Proc1.manufacturer.id) to: $($ManufactureId)"
                            Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($Proc1.id)/" -ContentType "application/json" -Body (@{manufacturer = $ManufactureId; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                        }
                        if ($Proc1Description -ne $Proc1.description) {
                            Write-Host -ForegroundColor Yellow " - - NETBOX: Patching Proc1 description from: $($Proc1.description) to: $($Proc1Description)"
                            Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($Proc1.id)/" -ContentType "application/json" -Body (@{description = $Proc1Description; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                        }
                    }
                }
                elseif ($Proc1.id -ne $null) {
                    Invoke-RestMethod -Method Delete -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($Proc1.id)/" -ContentType "application/json" -Header $NetBoxTokenHeader | Out-Null
                }

                $Proc2 = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/?device_id=$($FoundDevice.Id)&tag=Proc2" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                $Proc2Description = "Processor 2"
                if ([string]::IsNullOrWhiteSpace($EnclosureBayData_CPU2) -eq $false -and $EnclosureBayData_CPU2 -notlike "*present*") {
                    $ManufactureId = 10 #Intel
                    if ($EnclosureBayData_CPU2 -like "*AMD*") {
                        $ManufactureId = 11 #AMD
                    }
                    if ($Proc2.id -eq $null) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Creating Inventory Proc2"
                        Invoke-RestMethod -Method Post -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/" -ContentType "application/json" -Body (@{
                                name         = $EnclosureBayData_CPU2;
                                manufacturer = $ManufactureId;
                                device       = $FoundDevice.Id;
                                description  = $Proc2Description;
                                tags         = @("Proc2");
                            } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                    else {
                        if ($EnclosureBayData_CPU2 -ne $Proc2.name) {
                            Write-Host -ForegroundColor Yellow " - - NETBOX: Patching Proc2 name from: $($Proc2.name) to: $($EnclosureBayData_CPU2)"
                            Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($Proc2.id)/" -ContentType "application/json" -Body (@{name = $EnclosureBayData_CPU2; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                        }
                        if ($ManufactureId -ne $Proc2.manufacturer.id) {
                            Write-Host -ForegroundColor Yellow " - - NETBOX: Patching Proc2 manufacturer from: $($Proc2.manufacturer.id) to: $($ManufactureId)"
                            Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($Proc2.id)/" -ContentType "application/json" -Body (@{manufacturer = $ManufactureId; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                        }
                        if ($Proc2Description -ne $Proc2.description) {
                            Write-Host -ForegroundColor Yellow " - - NETBOX: Patching Proc2 description from: $($Proc2.description) to: $($Proc2Description)"
                            Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($Proc2.id)/" -ContentType "application/json" -Body (@{description = $Proc2Description; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                        }
                    }
                }
                elseif ($Proc2.id -ne $null) {
                    Invoke-RestMethod -Method Delete -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($Proc2.id)/" -ContentType "application/json" -Header $NetBoxTokenHeader | Out-Null
                }

                $Memory = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/?device_id=$($FoundDevice.Id)&tag=Memory" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                $MemoryDescription = "Memory (GB)"
                $EnclosureBayData_Memory = $EnclosureBayData_Memory.Replace(' MB', '')
                $EnclosureBayData_Memory = [System.Math]::Round($EnclosureBayData_Memory / 1024, 2);
                if ($Memory.id -eq $null) {
                    Write-Host -ForegroundColor Yellow " - - NETBOX: Creating Inventory Memory"
                    Invoke-RestMethod -Method Post -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/" -ContentType "application/json" -Body (@{
                            name        = $EnclosureBayData_Memory;
                            device      = $FoundDevice.Id;
                            description = $MemoryDescription;
                            tags        = @("Memory");
                        } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                }
                else {
                    if ($EnclosureBayData_Memory -ne $Memory.name) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching Memory name from: $($Memory.name) to: $($EnclosureBayData_Memory)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($Memory.id)/" -ContentType "application/json" -Body (@{name = $EnclosureBayData_Memory; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                    if ($MemoryDescription -ne $Memory.description) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching Memory description from: $($Memory.description) to: $($MemoryDescription)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($Memory.id)/" -ContentType "application/json" -Body (@{description = $MemoryDescription; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                }

                $CPU1Info = $CPUInfos | Where-Object {$_.Name -eq $EnclosureBayData_CPU1}
                $CPU2Info = $CPUInfos | Where-Object {$_.Name -eq $EnclosureBayData_CPU2}
                $ProcSingleCoreSpeed = $CPU1Info.Speed;
                $ProcCores = $CPU1Info.Cores + $CPU2Info.Cores;
                $ProcCoresLogical = $ProcCores;
                if ($CPU1Info.HyperThreading)
                {$ProcCoresLogical = $ProcCoresLogical * 2}                
                $ProcCombinedCoresSpeed = [System.Math]::Round($ProcCores * $ProcSingleCoreSpeed, 2);
                $ProcSingleCoreSpeedDescription = "Proccessor Single Core Speed"
                $NB_ProcSingleCoreSpeed = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/?device_id=$($FoundDevice.Id)&tag=ProcSingleCoreSpeed" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                if ($NB_ProcSingleCoreSpeed.id -eq $null) {
                    Write-Host -ForegroundColor Yellow " - - NETBOX: Creating Inventory ProcSingleCoreSpeed"
                    Invoke-RestMethod -Method Post -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/" -ContentType "application/json" -Body (@{
                            name        = $ProcSingleCoreSpeed;
                            device      = $FoundDevice.Id;
                            description = $ProcSingleCoreSpeedDescription;
                            tags        = @("ProcSingleCoreSpeed");
                        } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                }
                else {
                    if ($ProcSingleCoreSpeed -ne $NB_ProcSingleCoreSpeed.name) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching ProcSingleCoreSpeed name from: $($NB_ProcSingleCoreSpeed.name) to: $($ProcSingleCoreSpeed)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($NB_ProcSingleCoreSpeed.id)/" -ContentType "application/json" -Body (@{name = $ProcSingleCoreSpeed; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                    if ($ProcSingleCoreSpeedDescription -ne $NB_ProcSingleCoreSpeed.description) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching ProcSingleCoreSpeed description from: $($NB_ProcSingleCoreSpeed.description) to: $($ProcSingleCoreSpeedDescription)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($NB_ProcSingleCoreSpeed.id)/" -ContentType "application/json" -Body (@{description = $ProcSingleCoreSpeedDescription; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                }

                $NB_ProcCores = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/?device_id=$($FoundDevice.Id)&tag=ProcCores" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                $ProcCoresDescription = "Proccessor Physical Cores";
                if ($NB_ProcCores.id -eq $null) {
                    Write-Host -ForegroundColor Yellow " - - NETBOX: Creating Inventory ProcCores"
                    Invoke-RestMethod -Method Post -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/" -ContentType "application/json" -Body (@{
                            name        = $ProcCores;
                            device      = $FoundDevice.Id;
                            description = $ProcCoresDescription;
                            tags        = @("ProcCores");
                        } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                }
                else {
                    if ($ProcCores -ne $NB_ProcCores.name) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching ProcCores name from: $($NB_ProcCores.name) to: $($ProcCores)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($NB_ProcCores.id)/" -ContentType "application/json" -Body (@{name = $ProcCores; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                    if ($ProcCoresDescription -ne $NB_ProcCores.description) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching ProcCores description from: $($NB_ProcCores.description) to: $($ProcCoresDescription)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($NB_ProcCores.id)/" -ContentType "application/json" -Body (@{description = $ProcCoresDescription; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                }

                $NB_ProcCoresLogical = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/?device_id=$($FoundDevice.Id)&tag=ProcCoresLogical" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                $ProcCoresLogicalDescription = "Proccessor Logicals Cores";
                if ($NB_ProcCoresLogical.id -eq $null) {
                    Write-Host -ForegroundColor Yellow " - - NETBOX: Creating Inventory ProcCoresLogical"
                    Invoke-RestMethod -Method Post -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/" -ContentType "application/json" -Body (@{
                            name        = $ProcCoresLogical;
                            device      = $FoundDevice.Id;
                            description = $ProcCoresLogicalDescription;
                            tags        = @("ProcCoresLogical");
                        } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                }
                else {
                    if ($ProcCoresLogical -ne $NB_ProcCoresLogical.name) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching ProcCoresLogical name from: $($NB_ProcCoresLogical.name) to: $($ProcCoresLogical)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($NB_ProcCoresLogical.id)/" -ContentType "application/json" -Body (@{name = $ProcCoresLogical; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                    if ($ProcCoresLogicalDescription -ne $NB_ProcCoresLogical.description) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching ProcCoresLogical description from: $($NB_ProcCoresLogical.description) to: $($ProcCoresLogicalDescription)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($NB_ProcCoresLogical.id)/" -ContentType "application/json" -Body (@{description = $ProcCoresLogicalDescription; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                }

                $NB_ProcCombinedCoresSpeed = (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/?device_id=$($FoundDevice.Id)&tag=ProcCombinedCoresSpeed" -ContentType "application/json" -Header $NetBoxTokenHeader).results
                $ProcCombinedCoresSpeedDescription = "Proccessor Combined Cores Speed";
                if ($NB_ProcCombinedCoresSpeed.id -eq $null) {
                    Write-Host -ForegroundColor Yellow " - - NETBOX: Creating Inventory ProcCombinedCoresSpeed"
                    Invoke-RestMethod -Method Post -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/" -ContentType "application/json" -Body (@{
                            name        = $ProcCombinedCoresSpeed;
                            device      = $FoundDevice.Id;
                            description = $ProcCombinedCoresSpeedDescription;
                            tags        = @("ProcCombinedCoresSpeed");
                        } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                }
                else {
                    if ($ProcCombinedCoresSpeed -ne $NB_ProcCombinedCoresSpeed.name) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching ProcCombinedCoresSpeed name from: $($NB_ProcCombinedCoresSpeed.name) to: $($ProcCombinedCoresSpeed)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($NB_ProcCombinedCoresSpeed.id)/" -ContentType "application/json" -Body (@{name = $ProcCombinedCoresSpeed; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                    if ($ProcCombinedCoresSpeedDescription -ne $NB_ProcCombinedCoresSpeed.description) {
                        Write-Host -ForegroundColor Yellow " - - NETBOX: Patching ProcCombinedCoresSpeed description from: $($NB_ProcCombinedCoresSpeed.description) to: $($ProcCombinedCoresSpeedDescription)"
                        Invoke-RestMethod -Method Patch -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($NB_ProcCombinedCoresSpeed.id)/" -ContentType "application/json" -Body (@{description = $ProcCombinedCoresSpeedDescription; } | ConvertTo-Json -Compress) -Header $NetBoxTokenHeader | Out-Null
                    }
                }

                foreach ($delete in (Invoke-RestMethod -Method Get -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/?device_id=$($FoundDevice.Id)&tag=null" -ContentType "application/json" -Header $NetBoxTokenHeader).results) {
                    Write-Host -ForegroundColor Yellow " - - NETBOX: Removing inventory $($delete.id)"
                    Invoke-RestMethod -Method Delete -Uri "$($NetBoxApiBaseURL)dcim/inventory-items/$($delete.id)/" -ContentType "application/json" -Header $NetBoxTokenHeader | Out-Null
                }
                #endregion                        
            }
            #endregion

            #Debug stuff
            #if ([string]::IsNullOrWhiteSpace($EnclosureBayData_AssetTag) -or $EnclosureBayData_AssetTag -eq '[Unknown]') {
            #    Write-Host -ForegroundColor Red " - - - - Missing assettag"
            #}
        }
        #endregion

        #region Overview List
        $OverviewList += [pscustomobject]@{
            Enclosure_Name         = $EnclosureData_EnclosureName
            Enclosure_IP           = $Enclosure.primary_ipv4_address
            Bay                    = $($EnclosureBay.name)
            ProductName            = $EnclosureBayData_ProductName
            SerialNumber           = $EnclosureBayData_SerialNumber
            ServerName             = $EnclosureBayData_ServerName
            AssetTag               = $EnclosureBayData_AssetTag
            CPU1                   = $EnclosureBayData_CPU1
            CPU2                   = $EnclosureBayData_CPU2
            Memory                 = $EnclosureBayData_Memory
            NIC1_MAC               = $EnclosureBayData_NIC1_MAC
            NIC2_MAC               = $EnclosureBayData_NIC2_MAC
            ManagementType         = $EnclosureBayData_ManagementType
            ManagementIP           = $EnclosureBayData_ManagementIP
            ProcSingleCoreSpeed    = $ProcSingleCoreSpeed
            ProcCores              = $ProcCores
            ProcCoresLogical       = $ProcCoresLogical
            ProcCombinedCoresSpeed = $ProcCombinedCoresSpeed
            Eth0_IP                = $eth0_ip
            Eth1_IP                = $eth1_ip
        }
        #endregion
    }

    if (!$UseCache) {
        Remove-SSHSession -SSHSession $ses > $null
    }

    #break
}

Get-Item Overview.csv | Remove-Item -Force
$OverviewList | Export-Csv -Delimiter ';' -Path Overview.csv -NoClobber -NoTypeInformation

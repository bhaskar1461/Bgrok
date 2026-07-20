# bgrok - Wake-on-LAN Diagnostic Spike
# Run this script in an Administrator PowerShell console to query WoL capability.

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "         bgrok Wake-on-LAN Diagnostics" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Get Net Adapters
Write-Host "[1/3] Querying Windows Network Adapters..." -ForegroundColor Yellow
$Adapters = Get-NetAdapter -Physical | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress
$Adapters | Format-Table -AutoSize

# 2. Check WMI Wake Capabilities
Write-Host "[2/3] Querying WMI Power Management for Wake-on-LAN Settings..." -ForegroundColor Yellow
try {
    $WakeDevices = Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceWakeEnable
    $NetworkWakeDevices = $WakeDevices | Where-Object { $_.InstanceName -match "PCI" -or $_.InstanceName -match "NET" }
    
    if ($NetworkWakeDevices) {
        Write-Host "Found the following network adapters with wake-up capabilities enabled:" -ForegroundColor Green
        foreach ($dev in $NetworkWakeDevices) {
            Write-Host "  - Device Path: $($dev.InstanceName)" -ForegroundColor Gray
            Write-Host "    Wake Enabled: $($dev.Enable)" -ForegroundColor White
        }
    } else {
        Write-Host "No network adapters were found with MSPower_DeviceWakeEnable set to True." -ForegroundColor Yellow
        Write-Host "You may need to enable 'Allow this device to wake the computer' in Device Manager." -ForegroundColor Gray
    }
} catch {
    Write-Host "Could not query WMI MSPower_DeviceWakeEnable. Make sure you are running as Administrator." -ForegroundColor Red
    Write-Host "Error details: $_" -ForegroundColor DarkRed
}
Write-Host ""

# 3. Check advanced adapter registry keys for WoL settings
Write-Host "[3/3] Scanning Registry for adapter-specific WoL settings..." -ForegroundColor Yellow
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
if (Test-Path $registryPath) {
    $subkeys = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match "^\d{4}$" }
    $foundWoLKeys = $false

    foreach ($key in $subkeys) {
        $adapterDesc = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
        if ($adapterDesc -and $adapterDesc.DriverDesc) {
            $adapterName = $adapterDesc.DriverDesc
            # Check common WoL registry settings
            $wolKeys = @("PnPCapabilities", "*WakeOnMagicPacket", "*WakeOnPattern", "WakeOnMagicPacket", "WakeUpModeCap")
            $settings = @{}
            foreach ($k in $wolKeys) {
                if ($null -ne $adapterDesc.$k) {
                    $settings[$k] = $adapterDesc.$k
                }
            }
            if ($settings.Count -gt 0) {
                $foundWoLKeys = $true
                Write-Host "Adapter: $adapterName" -ForegroundColor White
                Write-Host "  Registry Path: SYSTEM\CurrentControlSet\Control\Class\...\\$($key.PSChildName)" -ForegroundColor Gray
                foreach ($pair in $settings.GetEnumerator()) {
                    # Decode PnPCapabilities if present
                    if ($pair.Key -eq "PnPCapabilities") {
                        # Bit 8 (value 0x100 = 256) usually means WoL / wake capabilities.
                        # If PnPCapabilities is 0, it means Wake-on-LAN is fully enabled (PnP allows power management).
                        # If bit 8 is set, wake from shutdown is enabled.
                        Write-Host "    $($pair.Key) : $($pair.Value) (Power Management flags)" -ForegroundColor Gray
                    } else {
                        Write-Host "    $($pair.Key) : $($pair.Value) (1 = Enabled, 0 = Disabled)" -ForegroundColor White
                    }
                }
            }
        }
    }
    if (-not $foundWoLKeys) {
        Write-Host "No explicit WoL registry settings found. They might be using default driver configurations." -ForegroundColor Gray
    }
} else {
    Write-Host "Adapter registry class path not found." -ForegroundColor Red
}

Write-Host ""
Write-Host "WoL Setup Checklist & Troubleshooting Guide:" -ForegroundColor Cyan
Write-Host "1. BIOS/UEFI: Ensure 'Wake-on-LAN', 'WOL', 'Power On by PCI-E', or 'Resume By PCI-E Device' is Enabled." -ForegroundColor Gray
Write-Host "2. Device Manager: Go to Network Adapters -> [Your Adapter] -> Properties." -ForegroundColor Gray
Write-Host "   - Under 'Power Management', check 'Allow this device to wake the computer' and 'Only allow a magic packet to wake the computer'." -ForegroundColor Gray
Write-Host "   - Under 'Advanced', ensure 'Wake on Magic Packet' is set to 'Enabled'." -ForegroundColor Gray
Write-Host "3. Windows Fast Startup: Fast Startup can sometimes interfere with WoL from a fully shut-down state." -ForegroundColor Gray
Write-Host "   If WoL fails from Shutdown (S5) but works from Sleep (S3), consider disabling Fast Startup in Control Panel -> Power Options." -ForegroundColor Gray
Write-Host "==================================================" -ForegroundColor Cyan

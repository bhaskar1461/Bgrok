# bgrok - Wake Beacon (Wake-on-LAN Daemon)

The **Wake Beacon** is a lightweight Python script that acts as an always-on bridge on your home Wi-Fi network (typically run on a Raspberry Pi, home router, or another PC). It connects to the `bgrok` signaling relay server, listens for wake commands, and broadcasts Wake-on-LAN magic packets locally to wake your target laptop.

---

## How to Set Up

### 1. Prerequisites
Ensure you have Python 3.7+ installed. Install the required `websockets` dependency:

```bash
pip install websockets
```

### 2. Find Your Target Laptop's MAC Address
On the target laptop (the one you want to wake up), run the diagnostic script in an Administrator console to get the correct physical MAC address:
```powershell
powershell -File .\spikes\spike_wol_check.ps1
```
Note the MAC address of your active network adapter (e.g. `00:11:22:33:44:55`).

### 3. Run the Beacon
Start the beacon script on your always-on home device, pointing it to your cloud relay server URL and target adapter MAC address:

```bash
python -m beacon.main --relay ws://<your-relay-ip>:8765 --agent-id bgrok-laptop-default --mac 00:11:22:33:44:55
```

The beacon will connect and register with the relay, then sit in a persistent loop.

---

## Troubleshooting Wake-on-LAN
If the beacon broadcasts the packet but the laptop does not wake up:
1. **BIOS**: Enter your laptop's BIOS/UEFI setup and ensure **Wake-on-LAN** or **Power On by PCI-E/Network** is enabled.
2. **Device Manager**: In Windows, open Device Manager -> Network Adapters -> [Your Adapter] -> Properties. Under the **Power Management** tab, make sure "Allow this device to wake the computer" and "Only allow a magic packet to wake the computer" are checked. Under **Advanced**, verify "Wake on Magic Packet" is set to "Enabled".
3. **Power State**: Ensure the target computer is plugged into AC power (some network cards disable WoL when running on battery to save power).

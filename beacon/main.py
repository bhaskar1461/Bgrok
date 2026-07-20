import asyncio
import json
import logging
import sys
import socket
import struct
import argparse

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] bgrok_beacon: %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("bgrok_beacon")

def send_wol(mac_address: str, broadcast_ip: str = "255.255.255.255", port: int = 9):
    """
    Sends a standard Wake-on-LAN (WoL) Magic Packet to the target MAC address.
    """
    clean_mac = mac_address.replace(":", "").replace("-", "")
    if len(clean_mac) != 12:
        raise ValueError(f"Invalid MAC address format: {mac_address}")

    # Magic packet is 6 bytes of 0xFF followed by target MAC address repeated 16 times
    hex_data = "FFFFFFFFFFFF" + clean_mac * 16
    packet = bytes.fromhex(hex_data)

    logger.info(f"Broadcasting Wake-on-LAN Magic Packet to MAC: {mac_address} via {broadcast_ip}:{port}...")
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            s.sendto(packet, (broadcast_ip, port))
        logger.info("Magic packet sent successfully.")
    except Exception as e:
        logger.error(f"Failed to send Magic Packet: {e}")

async def run_beacon(relay_url: str, agent_id: str, mac_address: str):
    """
    Starts the persistent Wake Beacon loop, auto-reconnecting to the Relay.
    """
    import websockets

    # Normalize url scheme if simple host:port was provided
    if not relay_url.startswith("ws://") and not relay_url.startswith("wss://"):
        relay_url = f"ws://{relay_url}"
    
    # Ensure URL ends with websocket route
    if not relay_url.endswith("/ws"):
        if relay_url.endswith("/"):
            relay_url += "ws"
        else:
            relay_url += "/ws"

    logger.info("==================================================")
    logger.info("         bgrok Wake-on-LAN Wake Beacon            ")
    logger.info("==================================================")
    logger.info(f"Target Agent ID : {agent_id}")
    logger.info(f"Target MAC      : {mac_address}")
    logger.info(f"Relay Server URL: {relay_url}")
    logger.info("==================================================")

    while True:
        try:
            logger.info("Connecting to Relay server...")
            async with websockets.connect(relay_url) as ws:
                # 1. Register as beacon
                reg_payload = {
                    "type": "register_beacon",
                    "agent_id": agent_id,
                    "mac_address": mac_address
                }
                await ws.send(json.dumps(reg_payload))
                
                # 2. Wait for registration verification
                resp = await ws.recv()
                data = json.loads(resp)
                if data.get("type") == "registered":
                    logger.info("Beacon registered successfully with Relay.")
                else:
                    logger.error(f"Unexpected response from Relay: {resp}")
                    await asyncio.sleep(5)
                    continue

                # 3. Message loop
                async for message in ws:
                    try:
                        payload = json.loads(message)
                    except json.JSONDecodeError:
                        logger.warning(f"Ignored invalid JSON message: {message}")
                        continue
                    
                    msg_type = payload.get("type")
                    if msg_type == "wake":
                        mac = payload.get("mac_address", mac_address)
                        send_wol(mac)
                    elif msg_type == "ping":
                        # Echo back ping to prevent connection idle timeout
                        await ws.send(json.dumps({"type": "pong"}))
                    else:
                        logger.info(f"Received unhandled message from relay: {message}")

        except websockets.exceptions.ConnectionClosed:
            logger.warning("Connection closed by Relay server. Retrying in 5 seconds...")
            await asyncio.sleep(5)
        except Exception as e:
            logger.error(f"Error in beacon connection loop: {e}. Retrying in 5 seconds...")
            await asyncio.sleep(5)

def main():
    parser = argparse.ArgumentParser(description="bgrok Wake-on-LAN Wake Beacon Daemon")
    parser.add_argument("--relay", type=str, default="ws://localhost:8765", help="Relay WS URL (e.g. ws://192.168.0.3:8765)")
    parser.add_argument("--agent-id", type=str, default="bgrok-laptop-default", help="ID of target agent laptop (default: bgrok-laptop-default)")
    parser.add_argument("--mac", type=str, required=True, help="Target computer's Ethernet/Wi-Fi physical MAC address (e.g. 00:11:22:33:44:55)")
    
    args = parser.parse_args()
    
    try:
        asyncio.run(run_beacon(args.relay, args.agent_id, args.mac))
    except KeyboardInterrupt:
        logger.info("Beacon stopped by user request.")
        sys.exit(0)

if __name__ == "__main__":
    main()

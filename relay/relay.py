import asyncio
import json
import logging
import sys
import os
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import uvicorn

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("bgrok_relay")

app = FastAPI(title="bgrok Signaling Relay")

# Connection pools
# Map agent_id -> WebSocket
agents = {}
# Map client_id -> WebSocket
clients = {}
# Track client_id -> agent_id mappings
client_to_agent = {}
# Map agent_id -> (WebSocket, mac_address)
beacons = {}

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    client_id = None
    agent_id = None
    role = None
    
    try:
        while True:
            # Receive text data
            message = await websocket.receive_text()
            try:
                data = json.loads(message)
            except json.JSONDecodeError:
                logger.warning("Received invalid non-JSON payload.")
                await websocket.send_json({"type": "error", "message": "Invalid JSON"})
                continue
                
            msg_type = data.get("type")
            if not msg_type:
                continue
                
            # --- Agent Registration ---
            if msg_type == "register_agent":
                agent_id = data.get("agent_id")
                if not agent_id:
                    await websocket.send_json({"type": "error", "message": "Missing agent_id"})
                    continue
                role = "agent"
                agents[agent_id] = websocket
                logger.info(f"Agent '{agent_id}' registered successfully.")
                await websocket.send_json({"type": "registered", "role": "agent"})
                
            # --- Beacon Registration ---
            elif msg_type == "register_beacon":
                agent_id = data.get("agent_id")
                mac_address = data.get("mac_address")
                if not agent_id or not mac_address:
                    await websocket.send_json({"type": "error", "message": "Missing agent_id or mac_address"})
                    continue
                role = "beacon"
                beacons[agent_id] = (websocket, mac_address)
                logger.info(f"Beacon for Agent '{agent_id}' (MAC: {mac_address}) registered successfully.")
                await websocket.send_json({"type": "registered", "role": "beacon"})

            # --- Client Registration ---
            elif msg_type == "register_client":
                client_id = data.get("client_id")
                target_agent_id = data.get("agent_id")
                if not client_id or not target_agent_id:
                    await websocket.send_json({"type": "error", "message": "Missing client_id or agent_id"})
                    continue
                role = "client"
                clients[client_id] = websocket
                client_to_agent[client_id] = target_agent_id
                logger.info(f"Client '{client_id}' registered to target Agent '{target_agent_id}'.")
                
                # Check if target agent is online
                if target_agent_id in agents:
                    await websocket.send_json({"type": "agent_status", "status": "online"})
                else:
                    await websocket.send_json({"type": "agent_status", "status": "offline"})
                    
            # --- Signaling Relay ---
            elif msg_type == "signal":
                dest = data.get("dest")
                payload = data.get("payload")
                
                if not dest or not payload:
                    continue
                
                if role == "client":
                    target_agent = client_to_agent.get(client_id)
                    if target_agent and target_agent in agents:
                        logger.info(f"Routing client '{client_id}' signal to agent '{target_agent}'")
                        await agents[target_agent].send_json({
                            "type": "signal",
                            "sender": client_id,
                            "payload": payload
                        })
                    else:
                        logger.warning(f"Client '{client_id}' tried to signal offline agent '{target_agent}'.")
                        await websocket.send_json({"type": "error", "message": "Agent is offline"})
                        
                elif role == "agent":
                    if dest in clients:
                        logger.info(f"Routing agent '{agent_id}' signal to client '{dest}'")
                        await clients[dest].send_json({
                            "type": "signal",
                            "sender": agent_id,
                            "payload": payload
                        })
                    else:
                        logger.warning(f"Agent '{agent_id}' tried to signal offline client '{dest}'.")
                        
            # --- Pairing Proxy ---
            elif msg_type == "pair_request":
                target_agent_id = data.get("agent_id")
                client_id = data.get("client_id")
                if target_agent_id in agents:
                    logger.info(f"Forwarding pairing request from Client '{client_id}' to Agent '{target_agent_id}'")
                    await agents[target_agent_id].send_json({
                        "type": "pair_request",
                        "client_id": client_id,
                        "pairing_code": data.get("pairing_code"),
                        "client_pubkey": data.get("client_pubkey")
                    })
                else:
                    await websocket.send_json({"type": "pair_response", "status": "failed", "reason": "Agent offline"})
                    
            elif msg_type == "pair_response":
                target_client_id = data.get("client_id")
                if target_client_id in clients:
                    logger.info(f"Forwarding pairing response from Agent '{agent_id}' to Client '{target_client_id}': status={data.get('status')}")
                    await clients[target_client_id].send_json({
                        "type": "pair_response",
                        "status": data.get("status"),
                        "reason": data.get("reason")
                    })
                    
    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected for active role: {role}")
    except Exception as e:
        logger.error(f"Error handling WebSocket endpoint: {e}")
    finally:
        # Cleanup connection pools
        if role == "agent" and agent_id in agents:
            del agents[agent_id]
            logger.info(f"Agent '{agent_id}' disconnected.")
            for cid, aid in list(client_to_agent.items()):
                if aid == agent_id and cid in clients:
                    try:
                        asyncio.create_task(clients[cid].send_json({"type": "agent_status", "status": "offline"}))
                    except Exception:
                        pass
        elif role == "client" and client_id in clients:
            del clients[client_id]
            if client_id in client_to_agent:
                del client_to_agent[client_id]
            logger.info(f"Client '{client_id}' disconnected.")
        elif role == "beacon":
            for aid, (ws, mac) in list(beacons.items()):
                if ws == websocket:
                    del beacons[aid]
                    logger.info(f"Beacon for Agent '{aid}' disconnected.")
                    break

@app.get("/")
def read_root():
    return {"status": "ok", "service": "bgrok Signaling Relay"}

@app.post("/wake/{agent_id}")
async def wake_agent(agent_id: str):
    if agent_id in beacons:
        ws, mac = beacons[agent_id]
        try:
            # Forward the wake request to the beacon
            await ws.send_json({"type": "wake", "mac_address": mac})
            logger.info(f"Forwarded HTTP wake request for Agent '{agent_id}' to active beacon.")
            return {"status": "ok", "message": "Wake command forwarded to beacon"}
        except Exception as e:
            logger.error(f"Failed to forward wake command to beacon for '{agent_id}': {e}")
            return {"status": "error", "message": f"Failed to reach beacon: {e}"}
    else:
        logger.warning(f"Wake requested for Agent '{agent_id}', but no beacon is registered.")
        return {"status": "error", "message": f"No Wake Beacon registered for agent ID '{agent_id}'"}

def main():
    import argparse
    parser = argparse.ArgumentParser(description="bgrok WebSockets Signaling Relay Server (FastAPI)")
    parser.add_argument("--port", type=int, default=8765, help="Port to host relay (default: 8765)")
    parser.add_argument("--host", type=str, default="0.0.0.0", help="Host binding (default: 0.0.0.0)")
    parser.add_argument("--ssl", action="store_true", help="Enable WSS mode using cert.pem and key.pem")
    args = parser.parse_args()
    
    cert_path = "cert.pem"
    key_path = "key.pem"
    ssl_keyfile = None
    ssl_certfile = None
    
    if args.ssl:
        if os.path.exists(cert_path) and os.path.exists(key_path):
            ssl_keyfile = key_path
            ssl_certfile = cert_path
            logger.info("SSL Certificate files found. Starting FastAPI via WSS.")
        else:
            logger.error(f"--ssl was requested but cert files not found at '{cert_path}' / '{key_path}'.")
            sys.exit(1)
    else:
        logger.info("Starting unsecure WS FastAPI Relay server.")
        
    logger.info("==================================================")
    logger.info("      bgrok FastAPI Signaling Relay Boot          ")
    logger.info("==================================================")
    
    uvicorn.run(
        "relay.relay:app",
        host=args.host,
        port=args.port,
        ssl_keyfile=ssl_keyfile,
        ssl_certfile=ssl_certfile,
        log_level="info"
    )

if __name__ == "__main__":
    main()

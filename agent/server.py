import asyncio
import json
import logging
import base64
import websockets
from aiortc import RTCPeerConnection, RTCSessionDescription

from agent.input_injector import InputInjector
from agent.screen_capture import ScreenCaptureTrack
from agent.crypto_helper import CryptoHelper

logger = logging.getLogger(__name__)

# Core components
injector = InputInjector()
crypto_helper = CryptoHelper()
active_pc = None

# Global loop control
websocket_client = None

async def close_active_pc():
    global active_pc
    if active_pc:
        logger.info("Closing active WebRTC peer connection...")
        try:
            await active_pc.close()
        except Exception as e:
            logger.error(f"Error closing peer connection: {e}")
        active_pc = None

async def handle_signaling_offer(client_id, payload, websocket):
    """
    Validates signature on the client SDP offer and establishes WebRTC peer connection.
    """
    global active_pc
    try:
        sdp = payload.get("sdp")
        sdp_type = payload.get("type")
        signature_base64 = payload.get("signature")
        
        if not sdp or not sdp_type or not signature_base64:
            logger.error("Incoming signaling offer is missing fields.")
            return

        # 1. Cryptographic Signature Verification
        # Client signs the raw SDP string
        message_bytes = sdp.encode('utf-8')
        try:
            signature_bytes = base64.b64decode(signature_base64)
        except Exception:
            logger.error("Failed to decode base64 signature.")
            return
            
        is_valid = crypto_helper.verify_signature(client_id, message_bytes, signature_bytes)
        if not is_valid:
            logger.warning(f"Connection attempt rejected: Invalid signature from client '{client_id}'.")
            return
            
        logger.info(f"Verified signature for client '{client_id}'. Preparing WebRTC connection...")

        # 2. Teardown existing session
        await close_active_pc()

        # 3. Configure Peer Connection
        # Use standard STUN for ICE candidates routing
        pc = RTCPeerConnection()
        active_pc = pc

        # 4. Attach Screen Stream Video Track
        fps = int(payload.get("fps", 30))
        width = int(payload.get("width", 1280))
        height = int(payload.get("height", 720))
        
        video_track = ScreenCaptureTrack(fps=fps, target_width=width, target_height=height)
        pc.addTrack(video_track)

        # 5. Attach Data Channel Input callbacks
        @pc.on("datachannel")
        def on_datachannel(channel):
            logger.info(f"Inputs Data Channel '{channel.label}' established.")
            @channel.on("message")
            def on_message(message):
                try:
                    event_data = json.loads(message)
                    injector.process_event(event_data)
                except Exception as ex:
                    logger.error(f"Error handling inputs message: {ex}")

        @pc.on("connectionstatechange")
        async def on_connectionstatechange():
            logger.info(f"WebRTC Connection State changed to: {pc.connectionState}")
            if pc.connectionState in ["failed", "closed"]:
                await close_active_pc()

        # 6. Negotiation
        offer_desc = RTCSessionDescription(sdp=sdp, type=sdp_type)
        await pc.setRemoteDescription(offer_desc)
        
        answer = await pc.createAnswer()
        await pc.setLocalDescription(answer)
        
        # 7. Send Answer back through WebSocket Relay
        logger.info(f"Sending SDP Answer to client '{client_id}' through relay...")
        await websocket.send(json.dumps({
            "type": "signal",
            "dest": client_id,
            "payload": {
                "sdp": pc.localDescription.sdp,
                "type": pc.localDescription.type
            }
        }))

    except Exception as e:
        logger.error(f"Error during WebRTC offer handling: {e}", exc_info=True)

async def handle_pairing_request(data, current_pairing_code, websocket):
    """
    Validates one-time pairing code and registers the client's public key.
    """
    client_id = data.get("client_id")
    client_pubkey = data.get("client_pubkey")
    pairing_code = data.get("pairing_code")
    
    if not client_id or not client_pubkey or not pairing_code:
        logger.warning("Pairing request missing essential fields.")
        return
        
    logger.info(f"Received pairing request from Client '{client_id}' with code '{pairing_code}'")
    
    if pairing_code != current_pairing_code:
        logger.warning(f"Pairing code mismatch! Expected '{current_pairing_code}', got '{pairing_code}'.")
        await websocket.send(json.dumps({
            "type": "pair_response",
            "client_id": client_id,
            "status": "rejected",
            "reason": "Invalid pairing code"
        }))
        return

    # Success: Save client's key in registry database
    crypto_helper.save_client_key(client_id, client_pubkey)
    
    # Send approved response
    logger.info(f"Approved pairing for client '{client_id}'. Public key registered.")
    await websocket.send(json.dumps({
        "type": "pair_response",
        "client_id": client_id,
        "status": "approved"
    }))

async def start_signaling_loop(relay_url, agent_id, pairing_code):
    """
    Outbound WebSocket connection to the Relay. Listens for signaling & pairing events.
    """
    global websocket_client
    import ssl
    
    logger.info(f"Connecting to Relay server at {relay_url}...")
    
    while True:
        try:
            ssl_context = None
            if relay_url.startswith("wss://"):
                ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
                ssl_context.check_hostname = False
                ssl_context.verify_mode = ssl.CERT_NONE
                
            async with websockets.connect(relay_url, ssl=ssl_context) as websocket:
                websocket_client = websocket
                
                # 1. Register as Agent
                await websocket.send(json.dumps({
                    "type": "register_agent",
                    "agent_id": agent_id
                }))
                
                # 2. Main message processing loop
                async for message in websocket:
                    try:
                        data = json.loads(message)
                    except ValueError:
                        continue
                    
                    msg_type = data.get("type")
                    if msg_type == "registered":
                        logger.info("Successfully registered on Relay server.")
                        
                    elif msg_type == "pair_request":
                        await handle_pairing_request(data, pairing_code, websocket)
                        
                    elif msg_type == "signal":
                        sender = data.get("sender")
                        payload = data.get("payload")
                        await handle_signaling_offer(sender, payload, websocket)
                        
                    elif msg_type == "agent_status":
                        # Status notices are for clients, agents can ignore
                        pass
                        
        except (websockets.exceptions.ConnectionClosed, ConnectionRefusedError) as e:
            logger.warning(f"Relay connection disconnected/refused: {e}. Retrying in 5 seconds...")
            await close_active_pc()
            await asyncio.sleep(5)
        except Exception as e:
            logger.error(f"Error in signaling loop: {e}", exc_info=True)
            await close_active_pc()
            await asyncio.sleep(5)

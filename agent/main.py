import argparse
import asyncio
import logging
import random
import string
import sys

from agent.server import start_signaling_loop

def generate_pairing_code() -> str:
    """Generates a secure 6-character alphanumeric pairing token."""
    # Exclude confusing characters (like 0, O, 1, I)
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "".join(random.choices(alphabet, k=6))

def main():
    parser = argparse.ArgumentParser(description="bgrok Windows Remote Desktop Agent (Phase 3)")
    parser.add_argument(
        "--relay-url", 
        type=str, 
        default="ws://localhost:8765", 
        help="WebSocket Relay Server URL (default: ws://localhost:8765)"
    )
    parser.add_argument(
        "--agent-id", 
        type=str, 
        default="bgrok-laptop-default", 
        help="Unique Agent identity string (default: bgrok-laptop-default)"
    )
    parser.add_argument(
        "--verbose", 
        action="store_true", 
        help="Enable detailed debug-level diagnostics logs"
    )
    
    args = parser.parse_args()
    
    # Configure logging output
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        handlers=[logging.StreamHandler(sys.stdout)]
    )
    
    logger = logging.getLogger("bgrok_agent")
    
    # Generate temporary session pairing code
    pairing_code = generate_pairing_code()
    
    logger.info("==================================================")
    logger.info("      bgrok Remote Desktop Agent (Phase 3)        ")
    logger.info("==================================================")
    logger.info(f"Identity Agent ID  : {args.agent_id}")
    logger.info(f"Relay Server URL   : {args.relay_url}")
    logger.info("")
    logger.info("   -------------------------------------------")
    logger.info(f"   >>> ACTIVE PAIRING CODE: {pairing_code} <<<")
    logger.info("   -------------------------------------------")
    logger.info("")
    logger.info("Keep this code open to pair your phone client.")
    logger.info("Outbound WebSockets signaling tunnel active.")
    logger.info("==================================================")
    
    try:
        asyncio.run(start_signaling_loop(args.relay_url, args.agent_id, pairing_code))
    except KeyboardInterrupt:
        logger.info("Shutdown requested. Stopping bgrok agent...")

if __name__ == "__main__":
    main()

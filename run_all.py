import subprocess
import sys
import time
import os

print("==================================================")
print("             bgrok Launcher (All-in-One)          ")
print("==================================================")

# Resolve project root so cert paths work regardless of CWD
project_root = os.path.dirname(os.path.abspath(__file__))

# 1. Start HTTPS Client Server (port 8000) — mobile browsers require
#    secure context for WebRTC APIs like getDisplayMedia and RTCPeerConnection
print("1. Starting HTTPS Client Server (port 8000)...")
ssl_server = subprocess.Popen(
    [sys.executable, "-u", "-m", "agent.ssl_server"],
    cwd=project_root
)

time.sleep(1)

# 2. Start WSS Relay — must match the protocol the client page is served over,
#    otherwise browsers block ws:// from an https:// page (mixed content)
print("2. Starting WSS Relay Server (port 8765)...")
relay = subprocess.Popen(
    [sys.executable, "-u", "-m", "relay.relay", "--port", "8765", "--ssl"],
    cwd=project_root
)

time.sleep(1)

# 3. Start Agent pointing to the WSS relay
rust_agent_path = os.path.join(project_root, "agent-rust", "target", "debug", "agent-rust.exe")
use_rust = "--rust" in sys.argv or os.path.exists(rust_agent_path)

if use_rust:
    print("3. Starting Native Rust Remote Desktop Agent...")
    if not os.path.exists(rust_agent_path):
        print("Compiling agent-rust...")
        subprocess.run(["cargo", "build", "--manifest-path", os.path.join(project_root, "agent-rust", "Cargo.toml")])
    agent = subprocess.Popen(
        [rust_agent_path],
        cwd=os.path.join(project_root, "agent-rust")
    )
else:
    print("3. Starting Python Remote Desktop Agent...")
    agent = subprocess.Popen(
        [sys.executable, "-u", "-m", "agent.main", "--relay-url", "wss://bgrok.cc.cd:8765"],
        cwd=project_root
    )

print("==================================================")
print("All bgrok processes running. Press Ctrl+C to terminate.")
print("==================================================")

try:
    while True:
        # Monitor processes. Exit if any process dies
        if ssl_server.poll() is not None:
            print("[System] HTTPS Client Server stopped.")
            break
        if relay.poll() is not None:
            print("[System] WSS Relay Server stopped.")
            break
        if agent.poll() is not None:
            print("[System] Agent stopped.")
            break
        time.sleep(1)
except KeyboardInterrupt:
    print("\n[System] Shutdown requested. Stopping all bgrok processes...")
finally:
    # Clean shutdown of all processes
    ssl_server.terminate()
    relay.terminate()
    agent.terminate()
    
    # Wait for completion
    ssl_server.wait()
    relay.wait()
    agent.wait()
    print("[System] All processes stopped. Goodbye!")

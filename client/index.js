// Logging utility
const terminal = document.getElementById("terminal");
function log(message, type = 'info') {
    const entry = document.createElement("div");
    entry.className = `log-entry log-${type}`;
    const time = new Date().toLocaleTimeString();
    entry.innerText = `[${time}] ${message}`;
    terminal.appendChild(entry);
    terminal.scrollTop = terminal.scrollHeight;
}

// UI Elements
const btnConnect = document.getElementById("btn-connect");
const btnDisconnect = document.getElementById("btn-disconnect");
const relayUrlInput = document.getElementById("relay-url");
const agentIdInput = document.getElementById("agent-id");
const streamRes = document.getElementById("stream-res");
const streamFps = document.getElementById("stream-fps");
const connBadge = document.getElementById("conn-state-badge");
const latencyIndicator = document.getElementById("latency-indicator");
const connectionOverlay = document.getElementById("connection-overlay");
const remoteVideo = document.getElementById("remote-video");
const viewportBox = document.getElementById("viewport-box");

// Pairing UI Elements
const pairCodeInput = document.getElementById("pair-code");
const btnPair = document.getElementById("btn-pair");

// Input Mode State
let activeInputMode = 'direct'; // 'direct' or 'trackpad'
const tabDirect = document.getElementById("tab-direct");
const tabTrackpad = document.getElementById("tab-trackpad");
const trackpadArea = document.getElementById("trackpad-area");

// WebRTC State
let pc = null;
let dataChannel = null;
let statsIntervalId = null;
let lastBytesReceived = 0;
let lastTimestamp = 0;

// WebSockets Signaling Relay State
let ws = null;
let clientId = null; // Stored unique client ID
let clientKeyPair = null; // Generated ECDSA keys

// Keyboard Grab State
let keyboardGrabActive = true;
const btnKeyboardGrab = document.getElementById("btn-keyboard-grab");

// --- Panel Toggle for Mobile ---
const btnTogglePanel = document.getElementById("btn-toggle-panel");
const sidePanel = document.querySelector(".panel");

if (btnTogglePanel && sidePanel) {
    // Start with panel collapsed on mobile
    const isMobile = window.matchMedia("(max-width: 768px)").matches;
    if (isMobile) {
        sidePanel.classList.add("panel-collapsed");
    }

    btnTogglePanel.addEventListener("click", () => {
        const isConnected = document.querySelector(".container").classList.contains("connected");
        
        if (sidePanel.classList.contains("panel-collapsed") || 
            (isConnected && !sidePanel.classList.contains("panel-force-open"))) {
            // Open panel
            sidePanel.classList.remove("panel-collapsed");
            sidePanel.classList.add("panel-force-open");
            btnTogglePanel.textContent = "\u2715"; // ✕ close icon
        } else {
            // Close panel
            sidePanel.classList.add("panel-collapsed");
            sidePanel.classList.remove("panel-force-open");
            btnTogglePanel.textContent = "\u2630"; // ☰ hamburger icon
        }
    });
}

// Active Modifiers (Toggled by Accessory Bar)
const toggledModifiers = {
    17: false, // Ctrl
    18: false, // Alt
    16: false, // Shift
    91: false  // Win
};

// --- IndexedDB Key Store Helpers ---
function openDB() {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open("bgrok_db", 1);
        request.onupgradeneeded = () => {
            request.result.createObjectStore("settings");
        };
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
    });
}

async function getStoredData(key) {
    const db = await openDB();
    return new Promise((resolve, reject) => {
        const tx = db.transaction("settings", "readonly");
        const req = tx.objectStore("settings").get(key);
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
    });
}

async function storeData(key, value) {
    const db = await openDB();
    return new Promise((resolve, reject) => {
        const tx = db.transaction("settings", "readwrite");
        const req = tx.objectStore("settings").put(value, key);
        req.onsuccess = () => resolve();
        req.onerror = () => reject(req.error);
    });
}

// --- Pure JS SHA-256 function ---
function sha256(ascii) {
    function rightRotate(value, amount) {
        return (value >>> amount) | (value << (32 - amount));
    }
    var mathPow = Math.pow;
    var maxWord = mathPow(2, 32);
    var lengthProperty = 'length';
    var i, j;
    var result = '';
    var words = [];
    var asciiLength = ascii[lengthProperty];
    var hash = [];
    var k = [];
    var primeCounter = 0;
    var isComposite = {};
    for (var candidate = 2; primeCounter < 64; candidate++) {
        if (!isComposite[candidate]) {
            for (i = 0; i < 313; i += candidate) {
                isComposite[i] = 1;
            }
            hash[primeCounter] = (mathPow(candidate, .5) * maxWord) | 0;
            k[primeCounter++] = (mathPow(candidate, 1 / 3) * maxWord) | 0;
        }
    }
    ascii += '\x80';
    while (ascii[lengthProperty] % 64 - 56) ascii += '\x00';
    for (i = 0; i < ascii[lengthProperty]; i++) {
        j = ascii.charCodeAt(i);
        if (j >> 8) return;
        words[i >> 2] |= j << (24 - (i % 4) * 8);
    }
    words[words[lengthProperty]] = ((asciiLength / maxWord) | 0);
    words[words[lengthProperty]] = (asciiLength * 8);
    for (j = 0; j < words[lengthProperty]; j += 16) {
        var w = words.slice(j, j + 16);
        var oldHash = hash.slice(0);
        for (i = 0; i < 64; i++) {
            var w15 = w[i - 15], w2 = w[i - 2];
            var a = hash[0], e = hash[4];
            var temp1 = hash[7]
                + (rightRotate(e, 6) ^ rightRotate(e, 11) ^ rightRotate(e, 25))
                + ((e & hash[5]) ^ ((~e) & hash[6]))
                + k[i]
                + (w[i] = (i < 16 ? w[i] : (
                        w[i - 16]
                        + (rightRotate(w15, 7) ^ rightRotate(w15, 18) ^ (w15 >>> 3))
                        + w[i - 7]
                        + (rightRotate(w2, 17) ^ rightRotate(w2, 19) ^ (w2 >>> 10))
                    ) | 0
                ));
            var temp2 = (rightRotate(a, 2) ^ rightRotate(a, 13) ^ rightRotate(a, 22))
                + ((a & hash[1]) ^ (a & hash[2]) ^ (hash[1] & hash[2]));
            hash = [(temp1 + temp2) | 0].concat(hash);
            hash[4] = (hash[4] + temp1) | 0;
            hash.length = 8;
        }
        for (i = 0; i < 8; i++) {
            hash[i] = (hash[i] + oldHash[i]) | 0;
        }
    }
    const bytes = [];
    for (i = 0; i < 8; i++) {
        var val = hash[i];
        if (val < 0) val += maxWord;
        bytes.push((val >>> 24) & 0xff);
        bytes.push((val >>> 16) & 0xff);
        bytes.push((val >>> 8) & 0xff);
        bytes.push(val & 0xff);
    }
    return bytes;
}

// --- Cryptography Identity Initialization via elliptic.js ---
let ec = null;
let keyPair = null;

async function initializeIdentity() {
    try {
        clientId = localStorage.getItem("client_id");
        if (!clientId) {
            clientId = "bgrok-client-" + Math.random().toString(36).substring(2, 8);
            localStorage.setItem("client_id", clientId);
        }
        log(`Client Identity ID: ${clientId}`, "info");

        // Initialize elliptic curve
        ec = new elliptic.ec('p256');

        // Load or generate keypair
        let privateKeyHex = localStorage.getItem("client_private_key");
        if (!privateKeyHex) {
            log("Generating new P-256 keypair via elliptic.js...", "warn");
            keyPair = ec.genKeyPair();
            privateKeyHex = keyPair.getPrivate('hex');
            localStorage.setItem("client_private_key", privateKeyHex);
            log("New keypair generated and saved in localStorage.", "success");
        } else {
            keyPair = ec.keyFromPrivate(privateKeyHex, 'hex');
            log("Client keys loaded successfully from localStorage.", "info");
        }

        // Auto-detect hosting hostname for relay defaults
        // Skip auto-detection on tunnel domains (relay is on a separate tunnel URL)
        // Also skip if the default is already set to bgrok.cc.cd (production domain)
        const tunnelDomains = ['.lhr.life', '.ngrok.io', '.ngrok-free.app', '.trycloudflare.com', '.pinggy.link'];
        const isTunneled = tunnelDomains.some(d => window.location.hostname.endsWith(d));
        const isProductionDefault = relayUrlInput.value.includes('bgrok.cc.cd');
        
        if (!isProductionDefault && !isTunneled && window.location.hostname && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1') {
            const protocol = window.location.protocol === 'https:' ? 'wss' : 'ws';
            relayUrlInput.value = `${protocol}://${window.location.hostname}:8765/ws`;
            log(`Auto-configured Relay URL to: ${protocol}://${window.location.hostname}:8765/ws`, "info");
        } else if (isTunneled) {
            relayUrlInput.value = '';
            log(`Tunnel domain detected. Please enter the Relay tunnel URL manually.`, "warn");
        }
    } catch (err) {
        log(`Failed to initialize identity: ${err.message}`, "error");
    }
}

// Export publicKey as SPKI PEM string compatible with Python cryptography loader
function exportPublicKeyPEM() {
    const pubBytes = keyPair.getPublic().encode(); 
    const header = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 
        0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 
        0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 
        0x42, 0x00
    ];
    const spki = new Uint8Array(header.length + pubBytes.length);
    spki.set(header, 0);
    spki.set(pubBytes, header.length);
    
    let binary = "";
    for (let i = 0; i < spki.byteLength; i++) {
        binary += String.fromCharCode(spki[i]);
    }
    const base64 = btoa(binary);
    const lines = base64.match(/.{1,64}/g);
    return `-----BEGIN PUBLIC KEY-----\n${lines.join("\n")}\n-----END PUBLIC KEY-----`;
}

// Sign message using P-256 private key and output raw 64-byte signature R || S in base64
function signMessage(textMessage) {
    const msgHash = sha256(textMessage);
    const signature = keyPair.sign(msgHash);
    
    const rBytes = signature.r.toArray('big', 32);
    const sBytes = signature.s.toArray('big', 32);
    
    const rawSig = new Uint8Array(64);
    rawSig.set(rBytes, 0);
    rawSig.set(sBytes, 32);
    
    let binary = "";
    for (let i = 0; i < rawSig.length; i++) {
        binary += String.fromCharCode(rawSig[i]);
    }
    return btoa(binary);
}

// --- Mode Switching ---
tabDirect.addEventListener("click", () => {
    activeInputMode = 'direct';
    tabDirect.classList.add("active");
    tabTrackpad.classList.remove("active");
    trackpadArea.classList.add("hidden");
    log("Switched to Direct Touch mode");
});

tabTrackpad.addEventListener("click", () => {
    activeInputMode = 'trackpad';
    tabTrackpad.classList.add("active");
    tabDirect.classList.remove("active");
    trackpadArea.classList.remove("hidden");
    log("Switched to Trackpad mode");
});

// --- Keyboard Grab Button ---
btnKeyboardGrab.addEventListener("click", () => {
    keyboardGrabActive = !keyboardGrabActive;
    btnKeyboardGrab.classList.toggle("active", keyboardGrabActive);
    log(`Keyboard Grab ${keyboardGrabActive ? 'ENABLED' : 'DISABLED'}`);
});

// --- Device Pairing ---
btnPair.addEventListener("click", async () => {
    const relayUrl = relayUrlInput.value.trim();
    const targetAgentId = agentIdInput.value.trim();
    const pairCode = pairCodeInput.value.trim();

    if (!relayUrl || !targetAgentId || !pairCode) {
        log("Please provide Relay URL, Agent ID, and Pairing Code.", "error");
        return;
    }

    log(`Initiating pairing request with Agent '${targetAgentId}'...`);
    btnPair.disabled = true;

    try {
        const pairingSocket = new WebSocket(relayUrl);
        
        pairingSocket.onopen = async () => {
            log("Relay pairing socket connected. Registering client...");
            pairingSocket.send(JSON.stringify({
                type: "register_client",
                client_id: clientId,
                agent_id: targetAgentId
            }));

            // Wait 200ms for registration to process on the relay
            setTimeout(async () => {
                log("Sending pairing request...");
                const pubKeyPEM = exportPublicKeyPEM();
                pairingSocket.send(JSON.stringify({
                    type: "pair_request",
                    agent_id: targetAgentId,
                    client_id: clientId,
                    pairing_code: pairCode,
                    client_pubkey: pubKeyPEM
                }));
            }, 200);
        };

        pairingSocket.onmessage = (e) => {
            try {
                const data = JSON.parse(e.data);
                if (data.type === "agent_status") {
                    // Ignore agent status notifications on the pairing socket
                    return;
                }
                if (data.type === "pair_response") {
                    if (data.status === "approved") {
                        log("Pairing APPROVED by Agent! Your keys are now registered.", "success");
                        alert("Pairing Successful!");
                        pairCodeInput.value = "";
                    } else {
                        log(`Pairing REJECTED: ${data.reason || 'Invalid code'}`, "error");
                        alert(`Pairing Failed: ${data.reason || 'Invalid code'}`);
                    }
                    pairingSocket.close();
                }
            } catch (err) {
                log(`Failed to parse pairing response: ${err.message}`, "error");
                pairingSocket.close();
            }
        };

        pairingSocket.onerror = (err) => {
            log(`Pairing socket error: WebSocket connection to ${relayUrl} failed (check relay is running with --ssl and port 8765 is reachable)`, "error");
            btnPair.disabled = false;
        };

        pairingSocket.onclose = () => {
            log("Pairing signaling socket closed.");
            btnPair.disabled = false;
        };

    } catch (err) {
        log(`Pairing failed: ${err.message}`, "error");
        btnPair.disabled = false;
    }
});

// --- Connection Handlers ---
btnConnect.addEventListener("click", startSession);
btnDisconnect.addEventListener("click", stopSession);

async function startSession() {
    const relayUrl = relayUrlInput.value.trim();
    const targetAgentId = agentIdInput.value.trim();

    if (!relayUrl || !targetAgentId) {
        log("Invalid Connection Parameters", "error");
        return;
    }

    log(`Opening signaling channel to relay: ${relayUrl}...`);
    btnConnect.disabled = true;
    relayUrlInput.disabled = true;
    agentIdInput.disabled = true;
    streamRes.disabled = true;
    streamFps.disabled = true;
    btnPair.disabled = true;
    
    connBadge.className = "status-badge status-connecting";
    connBadge.innerText = "Connecting";
    
    connectionOverlay.querySelector(".overlay-spinner").style.display = "block";
    connectionOverlay.querySelector(".overlay-title").innerText = "Negotiating Tunnel...";
    connectionOverlay.querySelector(".overlay-text").innerText = "Swapping SDP offers via WebSockets relay...";

    try {
        // Initialize WebSocket Signaling tunnel
        ws = new WebSocket(relayUrl);

        ws.onopen = () => {
            log("Signaling tunnel socket connected. Registering client...");
            ws.send(JSON.stringify({
                type: "register_client",
                client_id: clientId,
                agent_id: targetAgentId
            }));
        };

        ws.onmessage = async (e) => {
            try {
                const data = JSON.parse(e.data);
                
                if (data.type === "agent_status") {
                    log(`Target Agent is: ${data.status.toUpperCase()}`, data.status === "online" ? "info" : "warn");
                    if (data.status === "online" && !pc) {
                        // Agent is online, trigger peer negotiation
                        await initiatePeerNegotiation(ws, targetAgentId);
                    } else if (data.status === "offline") {
                        stopSession();
                    }
                }
                
                else if (data.type === "signal") {
                    const answerPayload = data.payload;
                    log("Received SDP Answer from agent, applying remote description...");
                    await pc.setRemoteDescription(new RTCSessionDescription(answerPayload));
                    startStatsPolling();
                }
                
                else if (data.type === "error") {
                    log(`Relay reported error: ${data.message}`, "error");
                    stopSession();
                }
            } catch (err) {
                log(`Error handling signaling frame: ${err.message}`, "error");
            }
        };

        ws.onerror = (err) => {
            log(`Signaling tunnel error: WebSocket connection to ${relayUrl} failed (check relay is running with --ssl and port 8765 is reachable)`, "error");
            stopSession();
        };

        ws.onclose = () => {
            log("Signaling WebSockets connection closed.");
            if (pc) {
                stopSession();
            }
        };

    } catch (err) {
        log(`Connection failed: ${err.message}`, "error");
        stopSession();
    }
}

async function initiatePeerNegotiation(signalingSocket, targetAgentId) {
    log("Initializing local peer connection...");
    try {
        // 1. Create Peer Connection
        pc = new RTCPeerConnection({
            iceServers: [{ urls: "stun:stun.l.google.com:19302" }]
        });

        // 2. Setup Data Channel
        dataChannel = pc.createDataChannel("bgrok-inputs", {
            ordered: true
        });

        dataChannel.onopen = () => {
            log("Inputs Data Channel established.", "success");
        };

        // 3. Setup Incoming Video Track
        pc.ontrack = (event) => {
            log("Received desktop video stream from Agent.", "success");
            remoteVideo.srcObject = event.streams[0];
            
            // Expand panel styling
            document.querySelector(".container").classList.add("connected");
            
            // Hide connection overlay
            connectionOverlay.style.opacity = "0";
            setTimeout(() => {
                connectionOverlay.style.display = "none";
            }, 300);
            
            connBadge.className = "status-badge status-connected";
            connBadge.innerText = "Connected";
            btnDisconnect.disabled = false;
            
            latencyIndicator.querySelector(".dot").className = "dot green";
        };

        pc.onconnectionstatechange = () => {
            log(`PeerConnection state: ${pc.connectionState}`);
            if (pc.connectionState === "failed" || pc.connectionState === "closed") {
                stopSession();
            }
        };

        // Connect media transceiver
        pc.addTransceiver('video', { direction: 'recvonly' });

        // Generate Offer
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);

        // 4. ECDSA cryptographic signature of the local SDP Offer
        // Verification payload: message = raw sdp string
        log("Cryptographically signing SDP offer using P-256 private key...");
        const signatureBase64 = signMessage(offer.sdp);
        
        const [targetWidth, targetHeight] = streamRes.value.split("x").map(Number);
        const targetFps = Number(streamFps.value);

        // 5. Send signed SDP offer to Agent via WebSocket Relay
        log("Transmitting signed SDP offer to Agent...");
        signalingSocket.send(JSON.stringify({
            type: "signal",
            dest: targetAgentId,
            payload: {
                sdp: offer.sdp,
                type: offer.type,
                signature: signatureBase64,
                width: targetWidth,
                height: targetHeight,
                fps: targetFps
            }
        }));

    } catch (err) {
        log(`Failed to negotiate peer handshake: ${err.message}`, "error");
        stopSession();
    }
}

function stopSession() {
    log("Tearing down current session...", "warn");
    
    // Stop stats
    if (statsIntervalId) {
        clearInterval(statsIntervalId);
        statsIntervalId = null;
    }

    // Close Peer connection
    if (pc) {
        pc.close();
        pc = null;
    }
    dataChannel = null;

    // Close signaling WebSocket
    if (ws) {
        ws.close();
        ws = null;
    }

    // Reset UI
    remoteVideo.srcObject = null;
    document.querySelector(".container").classList.remove("connected");
    
    connectionOverlay.style.display = "flex";
    connectionOverlay.style.opacity = "1";
    connectionOverlay.querySelector(".overlay-spinner").style.display = "none";
    connectionOverlay.querySelector(".overlay-title").innerText = "Awaiting Connection";
    connectionOverlay.querySelector(".overlay-text").innerText = "Input the agent local IP address and click Connect to start streaming.";

    btnConnect.disabled = false;
    btnDisconnect.disabled = true;
    relayUrlInput.disabled = false;
    agentIdInput.disabled = false;
    streamRes.disabled = false;
    streamFps.disabled = false;
    btnPair.disabled = false;

    connBadge.className = "status-badge status-disconnected";
    connBadge.innerText = "Disconnected";
    
    latencyIndicator.querySelector(".dot").className = "dot yellow";
    latencyIndicator.lastChild.textContent = " RTT: --";

    document.getElementById("stat-fps").innerText = "--";
    document.getElementById("stat-rtt").innerText = "--";
    document.getElementById("stat-bitrate").innerText = "--";
    document.getElementById("stat-lost").innerText = "--";
    
    lastBytesReceived = 0;
    lastTimestamp = 0;

    // Reset modifier highlights
    document.querySelectorAll(".key-btn").forEach(btn => {
        if (btn.id !== "btn-keyboard-grab") {
            btn.classList.remove("active");
        }
    });
    for (let key in toggledModifiers) {
        toggledModifiers[key] = false;
    }
}

// --- Send Event Over DataChannel ---
function sendInputEvent(payload) {
    if (dataChannel && dataChannel.readyState === "open") {
        dataChannel.send(JSON.stringify(payload));
    }
}

// --- Mouse Inputs (Direct Mode) ---
remoteVideo.addEventListener("pointerdown", (e) => {
    if (activeInputMode !== 'direct') return;
    e.preventDefault();
    remoteVideo.setPointerCapture(e.pointerId);

    const rect = remoteVideo.getBoundingClientRect();
    const x = (e.clientX - rect.left) / rect.width;
    const y = (e.clientY - rect.top) / rect.height;

    sendInputEvent({ type: "mouse_move_abs", x: x, y: y });
    
    let btn = "left";
    if (e.button === 2) btn = "right";
    else if (e.button === 1) btn = "middle";

    sendInputEvent({ type: "mouse_button", button: btn, state: "down" });
});

remoteVideo.addEventListener("pointermove", (e) => {
    if (activeInputMode !== 'direct' || !remoteVideo.hasPointerCapture(e.pointerId)) return;
    e.preventDefault();

    const rect = remoteVideo.getBoundingClientRect();
    const x = (e.clientX - rect.left) / rect.width;
    const y = (e.clientY - rect.top) / rect.height;

    sendInputEvent({ type: "mouse_move_abs", x: x, y: y });
});

remoteVideo.addEventListener("pointerup", (e) => {
    if (activeInputMode !== 'direct') return;
    e.preventDefault();
    try {
        remoteVideo.releasePointerCapture(e.pointerId);
    } catch(err) {}

    let btn = "left";
    if (e.button === 2) btn = "right";
    else if (e.button === 1) btn = "middle";

    sendInputEvent({ type: "mouse_button", button: btn, state: "up" });
});

remoteVideo.addEventListener("contextmenu", (e) => e.preventDefault());

// --- Mouse Scroll wheel support (Both modes) ---
viewportBox.addEventListener("wheel", (e) => {
    e.preventDefault();
    const dy = -e.deltaY / 100;
    const dx = -e.deltaX / 100;
    sendInputEvent({ type: "mouse_scroll", dx: dx, dy: dy });
}, { passive: false });

// --- Mouse Inputs (Trackpad Mode) ---
let trackpadStart = { x: 0, y: 0 };
const trackpadSensitivity = 1.3;

trackpadArea.addEventListener("pointerdown", (e) => {
    e.preventDefault();
    trackpadArea.setPointerCapture(e.pointerId);
    trackpadStart = { x: e.clientX, y: e.clientY };

    trackpadArea.dataset.hasMoved = "false";
    trackpadArea.dataset.startTime = Date.now();
});

trackpadArea.addEventListener("pointermove", (e) => {
    if (!trackpadArea.hasPointerCapture(e.pointerId)) return;
    e.preventDefault();

    const dx = (e.clientX - trackpadStart.x) * trackpadSensitivity;
    const dy = (e.clientY - trackpadStart.y) * trackpadSensitivity;

    if (Math.abs(dx) > 1 || Math.abs(dy) > 1) {
        trackpadArea.dataset.hasMoved = "true";
        sendInputEvent({ type: "mouse_move_rel", dx: dx, dy: dy });
        trackpadStart = { x: e.clientX, y: e.clientY };
    }
});

trackpadArea.addEventListener("pointerup", (e) => {
    e.preventDefault();
    try {
        trackpadArea.releasePointerCapture(e.pointerId);
    } catch(err) {}

    const hasMoved = trackpadArea.dataset.hasMoved === "true";
    const duration = Date.now() - Number(trackpadArea.dataset.startTime);

    if (!hasMoved && duration < 250) {
        sendInputEvent({ type: "mouse_button", button: "left", state: "down" });
        setTimeout(() => {
            sendInputEvent({ type: "mouse_button", button: "left", state: "up" });
        }, 30);
    }
});

// --- Keyboard Inputs (Global Page Grabber) ---
window.addEventListener("keydown", (e) => {
    if (!keyboardGrabActive || !pc) return;
    if (e.target.tagName === "INPUT" || e.target.tagName === "SELECT" || e.target.tagName === "TEXTAREA") return;
    if (e.repeat) return;

    const vk = e.keyCode;
    const keysToPrevent = ["Tab", "Backspace", "Space", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "F5"];
    if (keysToPrevent.includes(e.key) || e.ctrlKey || e.altKey) {
        e.preventDefault();
    }
    sendInputEvent({ type: "key", vk: vk, state: "down" });
});

window.addEventListener("keyup", (e) => {
    if (!keyboardGrabActive || !pc) return;
    if (e.target.tagName === "INPUT" || e.target.tagName === "SELECT" || e.target.tagName === "TEXTAREA") return;
    const vk = e.keyCode;
    sendInputEvent({ type: "key", vk: vk, state: "up" });
});

// --- Accessory Bar Buttons ---
document.querySelectorAll(".key-btn").forEach(btn => {
    const vk = Number(btn.dataset.vk);
    if (!vk) return; 

    btn.addEventListener("click", () => {
        toggledModifiers[vk] = !toggledModifiers[vk];
        btn.classList.toggle("active", toggledModifiers[vk]);

        const state = toggledModifiers[vk] ? "down" : "up";
        sendInputEvent({ type: "key", vk: vk, state: state });
        log(`Toggled key ${btn.innerText} ${state.toUpperCase()}`);
    });
});

// Ctrl+Alt+Del Combination
document.getElementById("btn-cad").addEventListener("click", () => {
    log("Sending Ctrl+Alt+Del combo...", "warn");
    sendInputEvent({ type: "key", vk: 17, state: "down" });
    sendInputEvent({ type: "key", vk: 18, state: "down" });
    sendInputEvent({ type: "key", vk: 46, state: "down" });
    
    setTimeout(() => {
        sendInputEvent({ type: "key", vk: 46, state: "up" });
        sendInputEvent({ type: "key", vk: 18, state: "up" });
        sendInputEvent({ type: "key", vk: 17, state: "up" });
    }, 100);
});

// --- WebRTC Stats Polling ---
function startStatsPolling() {
    if (statsIntervalId) clearInterval(statsIntervalId);
    
    statsIntervalId = setInterval(async () => {
        if (!pc) return;

        try {
            const stats = await pc.getStats();
            let videoStatsFound = false;

            stats.forEach(report => {
                if (report.type === "inbound-rtp" && report.kind === "video") {
                    videoStatsFound = true;
                    if (report.framesPerSecond !== undefined) {
                        document.getElementById("stat-fps").innerText = `${report.framesPerSecond} FPS`;
                    }

                    const now = report.timestamp;
                    const bytes = report.bytesReceived;
                    if (lastTimestamp > 0 && bytes > lastBytesReceived) {
                        const kbps = ((bytes - lastBytesReceived) * 8) / (now - lastTimestamp);
                        const mbps = (kbps / 1000).toFixed(2);
                        document.getElementById("stat-bitrate").innerText = `${mbps} Mbps`;
                    }
                    lastBytesReceived = bytes;
                    lastTimestamp = now;

                    if (report.packetsLost !== undefined) {
                        const card = document.getElementById("stat-lost");
                        card.innerText = report.packetsLost;
                        card.style.color = report.packetsLost > 0 ? "var(--error)" : "var(--text-main)";
                    }
                }
                
                if (report.type === "candidate-pair" && report.state === "succeeded") {
                    if (report.currentRoundTripTime !== undefined) {
                        const rttMs = (report.currentRoundTripTime * 1000).toFixed(1);
                        document.getElementById("stat-rtt").innerText = `${rttMs} ms`;
                        latencyIndicator.lastChild.textContent = ` RTT: ${rttMs} ms`;
                    }
                }
            });

            if (!videoStatsFound) {
                document.getElementById("stat-fps").innerText = "Connecting...";
            }
        } catch (e) {
            console.error("Error fetching WebRTC stats:", e);
        }
    }, 1000);
}

// --- Native iOS/Android Keyboard grab hack ---
const btnKeyboardToggle = document.getElementById("btn-keyboard-toggle");
const hiddenKeyboardInput = document.getElementById("hidden-keyboard-input");

btnKeyboardToggle.addEventListener("click", (e) => {
    e.preventDefault();
    hiddenKeyboardInput.focus();
    log("Opened keyboard context");
});

hiddenKeyboardInput.value = " "; // single-space placeholder
hiddenKeyboardInput.addEventListener("input", (e) => {
    const val = hiddenKeyboardInput.value;
    if (val.length === 0) {
        // Backspace detected (user deleted the space character)
        sendInputEvent({ type: "key", vk: 8, state: "down" });
        setTimeout(() => {
            sendInputEvent({ type: "key", vk: 8, state: "up" });
        }, 20);
        hiddenKeyboardInput.value = " "; // Reset
    } else if (val.length > 1) {
        // Character added (newValue is " <char>")
        const char = val.substring(1);
        const vk = mapCharToVk(char);
        if (vk) {
            sendInputEvent({ type: "key", vk: vk, state: "down" });
            setTimeout(() => {
                sendInputEvent({ type: "key", vk: vk, state: "up" });
            }, 20);
        }
        hiddenKeyboardInput.value = " "; // Reset
    }
});

// Map key character to Virtual Key Code
function mapCharToVk(char) {
    const code = char.charCodeAt(0);
    // Lowercase letter -> map to uppercase virtual key code (65-90)
    if (code >= 97 && code <= 122) {
        return code - 32;
    }
    // Uppercase letters (65-90) and digits 0-9 (48-57)
    if ((code >= 65 && code <= 90) || (code >= 48 && code <= 57)) {
        return code;
    }
    // Space
    if (char === " ") return 32;
    // Enter
    if (char === "\n" || char === "\r") return 13;
    // Common punctuation
    if (char === ".") return 190;
    if (char === ",") return 188;
    return null;
}

// --- Two-finger touch scrolling (Trackpad) ---
let lastTouchY = 0;
let lastTouchX = 0;

trackpadArea.addEventListener("touchstart", (e) => {
    if (e.touches.length === 2) {
        e.preventDefault();
        lastTouchY = (e.touches[0].clientY + e.touches[1].clientY) / 2;
        lastTouchX = (e.touches[0].clientX + e.touches[1].clientX) / 2;
    }
}, { passive: false });

trackpadArea.addEventListener("touchmove", (e) => {
    if (e.touches.length === 2) {
        e.preventDefault();
        const currentY = (e.touches[0].clientY + e.touches[1].clientY) / 2;
        const currentX = (e.touches[0].clientX + e.touches[1].clientX) / 2;
        
        const dy = (currentY - lastTouchY) / 10;
        const dx = (currentX - lastTouchX) / 10;
        
        if (Math.abs(dy) > 0.1 || Math.abs(dx) > 0.1) {
            sendInputEvent({ type: "mouse_scroll", dx: dx, dy: dy });
            lastTouchY = currentY;
            lastTouchX = currentX;
        }
    }
}, { passive: false });

// Initialize key identities on load
initializeIdentity();

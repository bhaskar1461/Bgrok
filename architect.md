# Architecture — Tether

Companion to prd.md (what/why) and plan.md (when). This is how it's built and why each choice was made.

## 1. Guiding principle
Don't rebuild solved, dangerous-to-get-wrong problems (encryption, video transport, NAT traversal). Build the parts that are actually specific to this product: the Windows agent, the wake path, the mobile UX, and the app launcher.

## 2. Components

| Component | Role | Runs on |
|---|---|---|
| **Tether App** | Mobile PWA client — view, control, wake, launcher UI | iPhone (Safari PWA) |
| **Tether Agent** | Captures screen, injects input, reports installed apps | Windows laptop, as a background service |
| **Tether Relay** | Signaling (matches app ↔ agent, exchanges connection info) + TURN fallback relay | Self-hosted VPS |
| **Wake Beacon** | Always-on listener on the home network; receives wake requests, sends the local WoL packet | A Raspberry Pi (or similar) at home |
| **Data store** | Pairing keys, app allowlist, activity log | Alongside the Relay |

## 3. Static shape

```
┌────────────┐          ┌────────────────────┐          ┌─────────────┐
│ Tether App │◄────────►│    Tether Relay     │◄────────►│ Tether Agent│
│  (iPhone)  │ signaling│ (signaling + TURN)  │ signaling│  (laptop)   │
└─────┬──────┘          └────────────────────┘          └──────┬──────┘
      │                                                          │
      └────────────────── direct or relayed WebRTC ──────────────┘
             screen video + input, DTLS-SRTP encrypted end-to-end —
             the Relay forwards bytes it cannot decrypt, even when
             a direct peer-to-peer path isn't possible

┌────────────┐  internet   ┌──────────────┐   LAN (WoL magic packet) ┌─────────────┐
│ Tether App │────────────►│ Tether Relay │─────────────────────────►│ Wake Beacon │──► laptop wakes
└────────────┘ wake request└──────────────┘                          │ (home, Pi)  │
                                                                       └─────────────┘
```

## 4. Core flows

**Pairing (one-time, per laptop):**
1. You install the Agent on the laptop; it generates a keypair and shows a QR code / one-time code on screen.
2. You scan it in the Tether App; the phone generates its own keypair and both public keys are registered with the Relay, tied to your account.
3. From here on, the Relay only ever handles public keys and connection metadata — never anything that lets it read a session.

**Wake:**
1. App sends an authenticated wake request to the Relay.
2. Relay forwards it to the Wake Beacon (which maintains a persistent authenticated connection to the Relay).
3. Beacon sends a WoL magic packet on the local network.
4. Laptop's network adapter (powered by AC standby power) wakes the machine; the Agent starts and registers itself as reachable with the Relay.
5. App polls/gets notified the Agent is online and offers to connect.

**Connect & control:**
1. App and Agent each send an SDP offer/answer and ICE candidates through the Relay (signaling only).
2. WebRTC attempts a direct peer-to-peer path (via STUN); if NAT on either end blocks that, it falls back to relaying encrypted packets through TURN on the same server.
3. Once connected, screen frames flow Agent → App and input events flow App → Agent, both inside the DTLS-SRTP-encrypted WebRTC session.

**Launch a favorite app:**
1. App sends a "launch" command over the existing encrypted DataChannel.
2. Agent resolves it against the reported app list and starts the process.

## 5. Security model

- **What's genuinely end-to-end encrypted**: the screen video and all input (mouse/keyboard/launch commands) — this rides inside WebRTC's mandatory DTLS-SRTP, with keys negotiated directly between the App and the Agent. The Relay never holds these keys, whether or not it ends up relaying the encrypted bytes as a TURN fallback.
- **What the Relay does see**: connection setup metadata (that a session started, roughly when, public keys involved) and, separately, the activity log and app list you've explicitly asked it to store. That's a deliberate, disclosed exception, not a gap in the encryption — see prd.md §6.6.
- **Pairing is the real security boundary.** Whoever holds a paired device's private key has full desktop control. The private key lives in the iOS Keychain, gated locally by Face ID, and never leaves the phone.
- **Hotspot/public wifi**: not a meaningful risk to the session content, because the encryption doesn't care what network it's carried over — that's the actual point of DTLS-SRTP. The real hotspot downsides are mobile data cost (video is heavy) and stricter NAT increasing how often TURN relay is needed. Recommend a soft in-app warning about data usage rather than a hard network block, since blocking it buys you no real security.

## 6. Technology choices & Language Stack

**Tether Agent (Windows Service)**:
- **Language**: **Rust** (preferred for memory safety, utilizing `windows-rs` for Win32/WinRT capture and input APIs, and `webrtc-rs` for native transport) or **C++** (linked directly against `libwebrtc`).
- **Screen capture**: Windows.Graphics.Capture API (modern, hardware-accelerated, works without admin), falling back to Desktop Duplication API (DXGI) where needed.
- **Input injection**: Win32 `SendInput` (switching thread desktop context to the interactive `Default` desktop to bypass UIPI/UAC limits).
- **Constraints**: Do *not* use plain C (no memory safety benefits, high overhead) or Python (poor native WebRTC support, high resource footprint for an always-on background service; Python is strictly for Phase 0 throwaway prototyping).

**Tether Relay (Signaling Server)**:
- **Language/Stack**: **Python** using **FastAPI + asyncio** for fast, asynchronous, pure I/O performance.
- **NAT Traversal**: **coturn** for STUN/TURN brokerage.
- **Production Endpoint**: `wss://bgrok.cc.cd:8765` / `https://bgrok.cc.cd`

**Wake Beacon**:
- **Language**: **Python** (lightweight, highly portable, easy to deploy and iterate on Raspberry Pi).
- **Role**: Listens for wake commands and broadcasts Wake-on-LAN magic packets.

**Tether App (iOS Client)**:
- **Language/Framework**: **Swift / SwiftUI** (required for native performance, direct Keychain security access, local Face ID gating, and iOS integration).

## 7. Room to grow (not built now, but not blocked either)
- Multi-user: the Relay already keys everything off per-device public keys, so adding a proper user/account layer on top later doesn't require ripping out the pairing model — it means adding accounts that *own* multiple device pairs instead of assuming one implicit owner.
- Additional OS agents (macOS/Linux) would sit behind the same Relay and protocol; only the capture/input-injection code is Windows-specific.
- The "favorites" launcher could later become real access control (e.g., a restricted session mode) without changing the transport — it would sit as an additional permission check in the Agent before honoring a launch/input command.

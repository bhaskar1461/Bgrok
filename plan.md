# Build Plan — Tether

Companion to prd.md (what/why) and architect.md (how). Phases are ordered by risk and dependency, not by what's most exciting to build first — the riskiest assumptions get tested earliest, on purpose.

Estimates are relative (a solo project around classes doesn't run on a calendar), and each phase lists what "done" actually looks like so it's obvious when to move on.

---

## Phase 0 — Feasibility spikes
**Goal:** kill the assumptions that would sink the whole project before writing any real code.
- Confirm Wake-on-LAN actually works on your exact laptop: test from another device on the same wifi first. Check specifically whether it works from a full shutdown, not just sleep, and whether it works on battery or only on AC power — this is a very common gotcha.
- Build a throwaway WebRTC screen-share between two browser tabs on the same wifi (using `getDisplayMedia`) to get a feel for real latency and confirm the DTLS-SRTP encryption story before touching Windows-specific APIs.
- Write a five-line script using `SendInput` to confirm programmatic mouse/keyboard control works as expected on your machine.

**Done when:** you've personally verified WoL works on your hardware (and under exactly which power state), and you've seen a basic encrypted screen share work locally.

## Phase 1 — LAN-only MVP
**Goal:** prove the real pipeline, same wifi network only, no internet relay yet.
- Build Tether Agent v0: a Windows service that captures the screen (Desktop Duplication API) and streams it over WebRTC.
- Wire up input injection: receive input events over a WebRTC DataChannel, inject via `SendInput`.
- A test client is fine as a plain browser page here — don't build the real iOS app yet.
- Pairing/auth can be minimal in this phase (same-wifi is an acceptable trust boundary for a local prototype) — but note explicitly in the code that this is temporary, so it doesn't quietly ship as-is.

**Done when:** from a browser on the same wifi, you can see and control the target laptop's live desktop.

## Phase 2 — Mobile PWA client + input UX
**Goal:** replace the throwaway test client with the actual mobile product experience.
- Build the client as a mobile-optimized Progressive Web App (PWA) running in Safari on iOS.
- Implement trackpad-mode relative touch input gestures (scrolling, taps, long presses), direct absolute touch mode, on-screen virtual keyboard integrations, and the modifier-key accessory bar (architect.md §6, prd.md §6.3).
- Still LAN-only.

**Done when:** using the laptop from your iPhone Safari (saved to Home Screen), on the same wifi, feels genuinely usable — not just technically functional.

## Phase 3 — Real remote connectivity
**Goal:** the actual "I'm at college" scenario.
- Stand up Tether Relay: signaling server + `coturn` (STUN/TURN) on a cheap VPS.
- Replace the placeholder pairing from Phase 1 with the real QR-code pairing flow and per-device keys (prd.md §6.5).
- Test for real from an off-network location — college wifi or mobile data connecting home.

**Done when:** you can reliably connect to and control your laptop from outside your home network.

## Phase 4 — Wake-from-anywhere
**Goal:** close the loop on the feature that started this whole project.
- Set up the Wake Beacon (Raspberry Pi or similar) on the home network.
- Wire the full path end to end: tap Wake in the app → Relay → Beacon → local WoL packet → laptop wakes → Agent comes online → app detects it and offers to connect.

**Done when:** the laptop is genuinely asleep, you're at college, you tap Wake, and within roughly a minute you're looking at a live desktop.

## Phase 5 — App launcher, activity log, polish
**Goal:** the everyday-usable version.
- Installed-app scanning, favorites UI, manual add/remove (prd.md §6.4).
- Activity log / session history (prd.md §6.6).
- Reconnect-on-network-change handling, adaptive bitrate tuning.
- A dedicated security pass: review the pairing/auth flow, key storage, Agent privilege level, and add a device-revocation path (prd.md §8's lost-phone risk).

**Done when:** it's something you'd actually rely on without babysitting it.

---

## Notes
- Resist folding later-phase features in early because "it's easy while I'm in there" — plan.md and airules.md both exist partly to keep this discipline when momentum tempts otherwise.
- Update this file's checkboxes/phase markers as you go — it's meant to reflect where the project actually is, not just where it started.

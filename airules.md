# AI Collaboration Rules — Tether

Read this first, every session. If you're using Claude Code, you can save a copy of this as `CLAUDE.md` at the repo root — it loads automatically at session start and is re-read after context compaction. Kept intentionally short: point to the other docs instead of duplicating them, since long rule files eat context budget and can make instructions less reliable, not more.

## Source of truth
- `prd.md` — what we're building and why
- `architect.md` — how it's structured, and why each technical choice was made
- `plan.md` — current phase, what's next
- This file — how to work in this repo

If a request conflicts with these docs, say so and ask, rather than silently picking a side.

## Stack (don't deviate without discussion)
- **Agent (Windows):** Rust (using `windows-rs` + `webrtc-rs`) or C++ (using `libwebrtc`). Capture via WinRT Windows.Graphics.Capture, input via Win32 `SendInput`. (Do *not* use plain C, do *not* use Python).
- **Transport:** WebRTC — DTLS-SRTP for media and data channels.
- **Relay:** Python, FastAPI + asyncio + `coturn` for STUN/TURN.
- **Wake Beacon:** Python on Raspberry Pi (WoL broadcasting).
- **App (iOS):** Swift / SwiftUI.

## Non-negotiables
- Never weaken, bypass, or "temporarily disable for testing" the end-to-end encryption on the screen/input stream. If a debugging need seems to require it, stop and ask — don't ship a workaround.
- Never log screen content, keystrokes, or clipboard data in plaintext, including local debug logs.
- Never add telemetry or analytics beyond what `prd.md` §6.6 specifies, without flagging it first.
- Never commit secrets, private keys, or pairing codes. Use environment variables / local config, `.gitignore`d.
- The Relay must never hold or gain access to session media encryption keys — that's the whole point of the architecture (see `architect.md` §5).

## Working style
- Solo, learning-oriented project — prefer code that's easy to read and modify over clever code.
- Match `plan.md`'s current phase. Don't quietly pull forward a later phase's feature because it's convenient.
- If something in `prd.md` or `architect.md` turns out to be wrong once you're actually building it, say so and propose a specific edit — don't silently diverge from the doc while leaving it stale.
- Prefer proven libraries for anything security- or networking-critical (WebRTC implementations, `coturn`, standard crypto libraries) over hand-rolled versions.

## Before marking a phase done
Check it against that phase's "Done when" line in `plan.md` — not against "the code runs."

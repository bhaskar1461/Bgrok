# Product Requirements Document — Tether
*(working title — rename freely; used consistently across prd.md / architect.md / plan.md / airules.md)*

## 1. Summary
Tether lets you see and fully control your home Windows laptop from your iPhone, over the internet, including waking it from sleep or a Wake-on-LAN-enabled shutdown. One primary scenario: you're at college, the laptop is at home, and you need it — right now, from your pocket.

## 2. Problem
Laptop stays at home. You don't. Sometimes you need a file, an app, or to check on something running, and physically going home isn't an option. Existing remote-desktop tools (TeamViewer, AnyDesk, Chrome Remote Desktop) solve "control a PC remotely" but not "wake a fully sleeping PC from a phone with a UX built for a phone screen" as a first-class, integrated flow — and they route your session through a company's infrastructure, not one you fully trust and control.

## 3. Scope for v1

**In scope (personal use, single user: you):**
- Wake the laptop from sleep, or from shutdown with Wake-on-LAN armed
- View and fully control the desktop from the iPhone, from any network
- Touch-first input model (trackpad-style), not a straight touch-to-click mirror
- A curated quick-launch list of favorite apps, editable by you
- A simple personal activity log (when you connected, what you launched)
- End-to-end encryption of the screen/input stream that not even you, running the relay server, can decrypt

**Explicitly out of scope for v1** (see Section 9 for later):
- Multiple users / accounts / a real product
- macOS or Linux laptop support
- App Store distribution
- Hard access-control sandboxing of which apps can be opened mid-session (the launcher is a convenience shortcut, not a security boundary — once connected, you have full desktop control regardless of what's "favorited")

## 4. Users
Just you, for v1. The architecture is deliberately kept from painting itself into a corner (see architect.md §7) in case you want to open this to a few friends later, but every v1 decision optimizes for "excellent for one person" over "scales to thousands."

## 5. Core user stories
- As the user, I open the app, tap Wake, and within about a minute my laptop is on and reachable — even though it was fully asleep and I'm on college wifi.
- As the user, I see my desktop live on my phone and can move the cursor, click, type, and scroll, in a way that feels natural on a small touchscreen rather than like a shrunk-down mirror.
- As the user, I tap a favorited app and it opens on the laptop without me hunting for it.
- As the user, I trust that nobody — including a compromised relay server I run — can see my screen or keystrokes in transit.
- As the user, I can add or remove apps from my quick-launch list in a couple of taps.

## 6. Functional requirements

### 6.1 Wake
- Tapping "Wake" brings the laptop from sleep, or from a WoL-armed shutdown, to fully reachable.
- Works when the phone and laptop are on completely different networks.
- If the laptop is already awake, skip straight to connecting.

### 6.2 Connect & control
- Live view of the desktop, low latency, adaptive quality on poor connections rather than disconnecting.
- Full mouse and keyboard equivalent input — anything the laptop can natively receive.
- Session should attempt to survive brief network hiccups (e.g., phone moving from wifi to cellular) rather than hard-dropping.
- Clipboard sync and file transfer: nice-to-have, deliberately deferred (see §9) to avoid scope creep in v1.

### 6.3 Input translation
- Default **trackpad mode**: relative-motion touch → cursor movement; tap = left click; two-finger tap = right click; two-finger drag = scroll; press-and-drag = click-and-drag.
- Optional **direct mode**: absolute tap-to-point, useful in full-screen mirrored landscape view.
- On-screen keyboard, plus first-class support for pairing a physical Bluetooth keyboard.
- An accessory bar for keys with no gesture equivalent: Ctrl, Alt, Win, Esc, function keys, Ctrl+Alt+Del.
- Both portrait (compact, trackpad-first) and landscape (mirrored) layouts supported.

### 6.4 App launcher (favorites)
- Agent enumerates installed applications (Start Menu shortcuts + registry uninstall entries) and reports them.
- You mark apps as favorites; favorites show in a quick-launch row in the app.
- You can add an app manually (by path) if it wasn't auto-detected, and remove/hide anything from the list.
- Tapping a favorite while connected launches it on the laptop.

### 6.5 Pairing & auth
- First-time setup: install the agent on the laptop, pair via a one-time code or QR shown on the laptop screen (avoids typing anything sensitive on the phone; mirrors how Signal/WhatsApp link a device).
- After pairing, the phone holds a device-specific key for future sessions — no password re-entry for daily use, gated locally by Face ID.
- Needs a recovery path if the phone is lost — this is a single-user single-device system, so losing the phone is a real lockout risk. Flagged as an open question in §8.

### 6.6 Activity log
- Agent logs session start/end and which favorited apps were launched, visible in the app as a simple history list. For v1 this is just your own usage history, not oversight of anyone else.

## 7. Non-functional requirements
- **Security**: screen/input stream is end-to-end encrypted — the relay server can route bytes it cannot read. Signaling metadata (connection setup only, never screen content) travels over TLS. No plaintext secrets in any log.
- **Latency**: rough target under 200ms on a good connection, gracefully degrading — not a hard guarantee, since it depends heavily on both networks.
- **Reliability**: prefer lowering resolution/framerate over dropping the session; auto-reconnect after transient network loss.
- **Network**: works over home wifi, cellular, cafe wifi, or a mobile hotspot. Hotspot isn't blocked (a properly encrypted tunnel is just as safe there — see architect.md §5), but the app should warn about likely data usage.

## 8. Risks & open questions
- **Laptop hardware/BIOS support for WoL varies**, and many laptops only arm Wake-on-LAN while plugged into AC power, not on battery — this needs to be verified on your exact laptop before anything else is built (Phase 0 in plan.md).
- **CGNAT on either network** could force relay (TURN) use more often than direct peer-to-peer, adding latency — the architecture already accounts for this, but it's worth knowing it'll happen sometimes.
- **iOS background execution limits** mean the phone app likely can't just "listen" in the background indefinitely — push notifications (APNs) are the realistic way to alert the app when something needs attention.
- **Single point of failure on the phone**: if it's lost, you need a way back in. Needs a deliberate recovery mechanism, not an afterthought.
- **The pairing/auth strength is the entire security boundary** — anyone who can wake and authenticate has full desktop control. Worth treating with real care, not glossed over because "it's just me."

## 9. Future ideas (explicitly post-v1)
- Opening this to a small trusted group, or a real multi-user product
- macOS / Linux agents
- Native App Store distribution
- Clipboard sync, file transfer
- Optional kiosk-mode app restriction (a real access-control boundary, not just a launcher)

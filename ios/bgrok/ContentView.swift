import SwiftUI
import WebRTC

struct ContentView: View {
    @StateObject private var webRTC = WebRTCManager()
    
    // Connection Settings
    @State private var agentUrl: String = "wss://bgrok.cc.cd:8765/ws"
    @State private var selectedResolution = "1280x720"
    @State private var selectedFps = 30
    
    // Input Configuration
    @State private var inputMode: String = "Direct" // "Direct" or "Trackpad"
    @State private var showSettings = true
    
    // Native Keyboard Grab Hack
    @State private var keyboardText: String = " " // Initialized with a space to capture backspaces
    @FocusState private var isKeyboardFocused: Bool
    
    // Trackpad last translation cache to compute frame deltas
    @State private var lastDragTranslation: CGSize = .zero
    
    // Modifier states
    @State private var ctrlActive = false
    @State private var altActive = false
    @State private var shiftActive = false
    @State private var winActive = false
    
    let resolutions = ["1280x720", "1920x1080", "960x540"]
    let frameRates = [15, 30, 60]
    
    var body: some View {
        ZStack {
            // Background gradient
            Color(red: 11/255, green: 15/255, blue: 25/255)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Bar
                HStack {
                    Text("bgrok")
                        .font(.custom("Outfit-Bold", size: 24))
                        .fontWeight(.black)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 167/255, green: 139/255, blue: 250/255), Color(red: 34/255, green: 211/255, blue: 238/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Spacer()
                    
                    if webRTC.isConnected {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("RTT: \(webRTC.rttMs)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                    }
                    
                    Text(webRTC.connectionStateString.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            webRTC.isConnected ? Color.green.opacity(0.15) : Color.red.opacity(0.15)
                        )
                        .foregroundColor(webRTC.isConnected ? .green : .red)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(webRTC.isConnected ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding()
                .background(Color(red: 17/255, green: 25/255, blue: 40/255).opacity(0.8))
                
                if showSettings && !webRTC.isConnected {
                    // Settings Panel
                    VStack(alignment: .leading, spacing: 14) {
                        Text("CONNECTION CONFIG")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.gray)
                            .tracking(1)
                        
                        VStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Agent Address")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                TextField("http://192.168.1.XX:8080", text: $agentUrl)
                                    .keyboardType(.URL)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .padding(10)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                            
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Resolution")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Picker("Resolution", selection: $selectedResolution) {
                                        ForEach(resolutions, id: \.self) {
                                            Text($0)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(8)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("FPS Limit")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Picker("FPS", selection: $selectedFps) {
                                        ForEach(frameRates, id: \.self) {
                                            Text("\($0) FPS")
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        
                        Button(action: {
                            let parts = selectedResolution.split(separator: "x").map(String.init)
                            let w = Int(parts[0]) ?? 1280
                            let h = Int(parts[1]) ?? 720
                            webRTC.connect(agentUrlString: agentUrl, width: w, height: h, fps: selectedFps)
                        }) {
                            Text("Connect Session")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    LinearGradient(colors: [Color.purple, Color.blue], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color(red: 17/255, green: 25/255, blue: 40/255).opacity(0.6))
                    .cornerRadius(12)
                    .padding()
                }
                
                // Viewport Box
                ZStack {
                    Color.black
                    
                    if let track = webRTC.remoteVideoTrack {
                        // Render desktop screen
                        VideoPlayerView(videoTrack: track)
                            .ignoresSafeArea()
                            .overlay(
                                // Track absolute clicking on Direct Touch Mode
                                GeometryReader { geo in
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onEnded { value in
                                                    if inputMode == "Direct" {
                                                        let xNorm = value.location.x / geo.size.width
                                                        let yNorm = value.location.y / geo.size.height
                                                        
                                                        // absolute tap
                                                        webRTC.sendInput(event: ["type": "mouse_move_abs", "x": xNorm, "y": yNorm])
                                                        webRTC.sendInput(event: ["type": "mouse_button", "button": "left", "state": "down"])
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                                                            webRTC.sendInput(event: ["type": "mouse_button", "button": "left", "state": "up"])
                                                        }
                                                    }
                                                }
                                        )
                                }
                            )
                    } else {
                        // Waiting overlay
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                                .scaleEffect(1.2)
                            Text(webRTC.connectionStateString == "Connecting" ? "Establishing WebRTC Tunnels..." : "Awaiting Remote Session")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Input the agent URL and connect to capture desktop.")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cornerRadius(webRTC.isConnected ? 0 : 12)
                .padding(webRTC.isConnected ? 0 : 16)
                
                // Active Controls
                if webRTC.isConnected {
                    VStack(spacing: 8) {
                        // Hidden keyboard inputs anchor
                        TextField("", text: $keyboardText)
                            .focused($isKeyboardFocused)
                            .keyboardType(.asciiCapable)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .frame(width: 1, height: 1)
                            .opacity(0)
                            .onChange(of: keyboardText) { newValue in
                                handleKeyboardInput(newValue)
                            }
                        
                        // Mode Switch tabs
                        HStack(spacing: 0) {
                            Button(action: { inputMode = "Direct" }) {
                                Text("Direct Touch")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(inputMode == "Direct" ? Color.purple : Color.clear)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                            
                            Button(action: { inputMode = "Trackpad" }) {
                                Text("Relative Trackpad")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(inputMode == "Trackpad" ? Color.purple : Color.clear)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                        }
                        .padding(4)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(8)
                        .padding(.horizontal)
                        
                        if inputMode == "Trackpad" {
                            // Large Trackpad Area
                            VStack {
                                Text("Drag cursor. Single Tap = Left Click. Long Press = Right Click.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                                    .padding(.top, 4)
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        let deltaX = (value.translation.width - lastDragTranslation.width) * 1.4
                                        let deltaY = (value.translation.height - lastDragTranslation.height) * 1.4
                                        
                                        webRTC.sendInput(event: ["type": "mouse_move_rel", "dx": deltaX, "dy": deltaY])
                                        lastDragTranslation = value.translation
                                    }
                                    .onEnded { _ in
                                        lastDragTranslation = .zero
                                    }
                            )
                            .gesture(
                                TapGesture()
                                    .onEnded {
                                        // Left Click Tap
                                        webRTC.sendInput(event: ["type": "mouse_button", "button": "left", "state": "down"])
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                                            webRTC.sendInput(event: ["type": "mouse_button", "button": "left", "state": "up"])
                                        }
                                    }
                            )
                            .gesture(
                                LongPressGesture(minimumDuration: 0.5)
                                    .onEnded { _ in
                                        // Right Click Long Press
                                        webRTC.sendInput(event: ["type": "mouse_button", "button": "right", "state": "down"])
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                                            webRTC.sendInput(event: ["type": "mouse_button", "button": "right", "state": "up"])
                                        }
                                    }
                            )
                        }
                        
                        // Accessory Key Bar
                        HStack(spacing: 6) {
                            Group {
                                Button("Ctrl") {
                                    ctrlActive.toggle()
                                    webRTC.sendInput(event: ["type": "key", "vk": 17, "state": ctrlActive ? "down" : "up"])
                                }.background(ctrlActive ? Color.purple : Color.white.opacity(0.08))
                                
                                Button("Alt") {
                                    altActive.toggle()
                                    webRTC.sendInput(event: ["type": "key", "vk": 18, "state": altActive ? "down" : "up"])
                                }.background(altActive ? Color.purple : Color.white.opacity(0.08))
                                
                                Button("Shift") {
                                    shiftActive.toggle()
                                    webRTC.sendInput(event: ["type": "key", "vk": 16, "state": shiftActive ? "down" : "up"])
                                }.background(shiftActive ? Color.purple : Color.white.opacity(0.08))
                                
                                Button("Win") {
                                    winActive.toggle()
                                    webRTC.sendInput(event: ["type": "key", "vk": 91, "state": winActive ? "down" : "up"])
                                }.background(winActive ? Color.purple : Color.white.opacity(0.08))
                                
                                Button("Esc") {
                                    webRTC.sendInput(event: ["type": "key", "vk": 27, "state": "down"])
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        webRTC.sendInput(event: ["type": "key", "vk": 27, "state": "up"])
                                    }
                                }.background(Color.white.opacity(0.08))
                            }
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .bold))
                            .frame(height: 38)
                            .cornerRadius(6)
                            
                            // Keyboard toggler
                            Button(action: {
                                isKeyboardFocused.toggle()
                            }) {
                                Image(systemName: isKeyboardFocused ? "keyboard.chevron.compact.down" : "keyboard")
                                    .foregroundColor(.cyan)
                                    .frame(width: 44, height: 38)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(6)
                            }
                            
                            // Ctrl+Alt+Del Combo
                            Button(action: sendCAD) {
                                Text("C-A-D")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.red)
                                    .frame(width: 44, height: 38)
                                    .background(Color.red.opacity(0.15))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            
                            // Disconnect Button
                            Button(action: { webRTC.disconnect() }) {
                                Image(systemName: "power")
                                    .foregroundColor(.white)
                                    .frame(width: 38, height: 38)
                                    .background(Color.red)
                                    .cornerRadius(6)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                    .background(Color(red: 17/255, green: 25/255, blue: 40/255))
                    .transition(.move(edge: .bottom))
                }
            }
        }
    }
    
    // Trigger keyboard actions
    private func handleKeyboardInput(_ input: String) {
        if input.isEmpty {
            // String became empty: Backspace delete triggered
            webRTC.sendInput(event: ["type": "key", "vk": 8, "state": "down"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                webRTC.sendInput(event: ["type": "key", "vk": 8, "state": "up"])
            }
            keyboardText = " " // reset to capture next delete
        } else if input.count > 1 {
            // Character was typed (newValue is " <char>")
            let typedChar = input.last!
            if let vk = mapCharToVk(typedChar) {
                webRTC.sendInput(event: ["type": "key", "vk": vk, "state": "down"])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    webRTC.sendInput(event: ["type": "key", "vk": vk, "state": "up"])
                }
            }
            keyboardText = " " // reset
        }
    }
    
    // Map typed letters to Windows Virtual Keys
    private func mapCharToVk(_ char: Character) -> Int? {
        guard let ascii = char.asciiValue else { return nil }
        
        // Lowercase a-z -> translate to uppercase VK (65-90)
        if ascii >= 97 && ascii <= 122 {
            return Int(ascii - 32)
        }
        // Uppercase A-Z or digits 0-9
        if (ascii >= 65 && ascii <= 90) || (ascii >= 48 && ascii <= 57) {
            return Int(ascii)
        }
        // Spacebar
        if ascii == 32 { return 32 }
        // Enter / Newline
        if ascii == 10 || ascii == 13 { return 13 }
        
        return nil
    }
    
    private func sendCAD() {
        // Sequenced Ctrl+Alt+Del
        webRTC.sendInput(event: ["type": "key", "vk": 17, "state": "down"])
        webRTC.sendInput(event: ["type": "key", "vk": 18, "state": "down"])
        webRTC.sendInput(event: ["type": "key", "vk": 46, "state": "down"])
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            webRTC.sendInput(event: ["type": "key", "vk": 46, "state": "up"])
            webRTC.sendInput(event: ["type": "key", "vk": 18, "state": "up"])
            webRTC.sendInput(event: ["type": "key", "vk": 17, "state": "up"])
        }
    }
}

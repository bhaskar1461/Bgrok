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
    
    // Scale Mode (Aspect Fit vs Aspect Fill)
    @State private var scaleMode: UIView.ContentMode = .scaleAspectFit
    
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
    
    // Side Menu States
    @State private var showSideMenu = false
    @State private var sideMenuSide: Edge = .leading
    @State private var dragToXDistance: CGFloat = 100
    @State private var isDraggingOverX = false
    @State private var showConnectedSettings = false
    
    let resolutions = ["1280x720", "1920x1080", "960x540"]
    let frameRates = [15, 30, 60]
    
    var body: some View {
        ZStack {
            // Background gradient
            Color(red: 11/255, green: 15/255, blue: 25/255)
                .ignoresSafeArea()
            
            if !webRTC.isConnected {
                // Connection setup view
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
                        
                        Text(webRTC.connectionStateString.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .padding()
                    .background(Color(red: 17/255, green: 25/255, blue: 40/255).opacity(0.8))
                    
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
                    
                    Spacer()
                }
            } else {
                // Connected view: full screen desktop, sliding side menu
                GeometryReader { geo in
                    ZStack {
                        // Desktop Viewport
                        if let track = webRTC.remoteVideoTrack {
                            VideoPlayerView(videoTrack: track, scaleMode: scaleMode)
                                .ignoresSafeArea()
                                .overlay(
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    if inputMode == "Trackpad" {
                                                        let deltaX = (value.translation.width - lastDragTranslation.width) * 1.4
                                                        let deltaY = (value.translation.height - lastDragTranslation.height) * 1.4
                                                        webRTC.sendInput(event: ["type": "mouse_move_rel", "dx": deltaX, "dy": deltaY])
                                                        lastDragTranslation = value.translation
                                                    } else {
                                                        let xNorm = value.location.x / geo.size.width
                                                        let yNorm = value.location.y / geo.size.height
                                                        webRTC.sendInput(event: ["type": "mouse_move_abs", "x": xNorm, "y": yNorm])
                                                    }
                                                }
                                                .onEnded { value in
                                                    if inputMode == "Trackpad" {
                                                        lastDragTranslation = .zero
                                                    } else {
                                                        let xNorm = value.location.x / geo.size.width
                                                        let yNorm = value.location.y / geo.size.height
                                                        webRTC.sendInput(event: ["type": "mouse_move_abs", "x": xNorm, "y": yNorm])
                                                        webRTC.sendInput(event: ["type": "mouse_button", "button": "left", "state": "down"])
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                                                            webRTC.sendInput(event: ["type": "mouse_button", "button": "left", "state": "up"])
                                                        }
                                                    }
                                                }
                                        )
                                        .simultaneousGesture(
                                            TapGesture()
                                                .onEnded {
                                                    if inputMode == "Trackpad" {
                                                        webRTC.sendInput(event: ["type": "mouse_button", "button": "left", "state": "down"])
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                                                            webRTC.sendInput(event: ["type": "mouse_button", "button": "left", "state": "up"])
                                                        }
                                                    }
                                                }
                                        )
                                        .simultaneousGesture(
                                            LongPressGesture(minimumDuration: 0.5)
                                                .onEnded { _ in
                                                    if inputMode == "Trackpad" {
                                                        webRTC.sendInput(event: ["type": "mouse_button", "button": "right", "state": "down"])
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                                                            webRTC.sendInput(event: ["type": "mouse_button", "button": "right", "state": "up"])
                                                        }
                                                    }
                                                }
                                        )
                                )
                        } else {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                                    .scaleEffect(1.2)
                                Text("Awaiting Remote Session...")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        
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
                        
                        // Edge Swipe visual indicator cues (non-blocking)
                        HStack {
                            Capsule()
                                .fill(Color.white.opacity(0.25))
                                .frame(width: 4, height: 60)
                                .padding(.leading, 4)
                            
                            Spacer()
                            
                            Capsule()
                                .fill(Color.white.opacity(0.25))
                                .frame(width: 4, height: 60)
                                .padding(.trailing, 4)
                        }
                        .allowsHitTesting(false)
                        
                        // Edge Swipe Zones
                        HStack {
                            // Left swipe zone
                            Color.clear
                                .frame(width: 25)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 10)
                                        .onChanged { value in
                                            if value.translation.width > 20 {
                                                withAnimation(.spring()) {
                                                    sideMenuSide = .leading
                                                    showSideMenu = true
                                                }
                                            }
                                        }
                                )
                            
                            Spacer()
                            
                            // Right swipe zone
                            Color.clear
                                .frame(width: 25)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 10)
                                        .onChanged { value in
                                            if value.translation.width < -20 {
                                                withAnimation(.spring()) {
                                                    sideMenuSide = .trailing
                                                    showSideMenu = true
                                                }
                                            }
                                        }
                                )
                        }
                        .ignoresSafeArea()
                        
                        // Side Menu Drawer/Overlay
                        if showSideMenu {
                            // Full-screen backdrop to handle taps/drags when menu is open
                            Color.black.opacity(0.15)
                                .ignoresSafeArea()
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring()) {
                                        showSideMenu = false
                                    }
                                }
                                .gesture(
                                    DragGesture(coordinateSpace: .global)
                                        .onChanged { value in
                                            let xDest = sideMenuSide == .leading ? 40.0 : (geo.size.width - 40.0)
                                            let yDest = geo.size.height - 65.0
                                            
                                            let dx = value.location.x - xDest
                                            let dy = value.location.y - yDest
                                            let dist = sqrt(dx * dx + dy * dy)
                                            
                                            dragToXDistance = dist
                                            isDraggingOverX = dist < 45
                                        }
                                        .onEnded { value in
                                            if isDraggingOverX {
                                                webRTC.disconnect()
                                                showSideMenu = false
                                            } else {
                                                let trans = value.translation.width
                                                if (sideMenuSide == .leading && trans < -30) || (sideMenuSide == .trailing && trans > 30) {
                                                    withAnimation(.spring()) {
                                                        showSideMenu = false
                                                    }
                                                }
                                            }
                                            isDraggingOverX = false
                                        }
                                )
                            
                            // Floating Buttons Panel
                            HStack {
                                if sideMenuSide == .leading {
                                    floatingButtonsPanel(side: .leading, screenHeight: geo.size.height)
                                        .transition(.move(edge: .leading))
                                    Spacer()
                                } else {
                                    Spacer()
                                    floatingButtonsPanel(side: .trailing, screenHeight: geo.size.height)
                                        .transition(.move(edge: .trailing))
                                }
                            }
                            .ignoresSafeArea()
                        }
                        
                        // Settings Overlay
                        if showConnectedSettings {
                            settingsOverlay
                        }
                        
                        // Floating Accessory Keys (Slides up with keyboard)
                        VStack {
                            Spacer()
                            if isKeyboardFocused {
                                accessoryKeysBar
                            }
                        }
                    }
                }
                .ignoresSafeArea()
            }
        }
    }
    
    @ViewBuilder
    private func floatingButtonsPanel(side: Edge, screenHeight: CGFloat) -> some View {
        VStack(spacing: 24) {
            // Gear Button (Settings)
            Button(action: {
                showConnectedSettings = true
                showSideMenu = false
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color(red: 239/255, green: 68/255, blue: 68/255))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 5, x: 0, y: 3)
            }
            .padding(.top, 40)
            
            // Keyboard Button
            Button(action: {
                isKeyboardFocused.toggle()
                showSideMenu = false
            }) {
                Image(systemName: "keyboard")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color(red: 239/255, green: 68/255, blue: 68/255))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 5, x: 0, y: 3)
            }
            
            Spacer()
            
            // X Button (Disconnect)
            Button(action: {
                webRTC.disconnect()
                showSideMenu = false
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color(red: 239/255, green: 68/255, blue: 68/255))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 1.5)
                    )
                    .scaleEffect(isDraggingOverX ? 1.3 : 1.0)
                    .shadow(color: isDraggingOverX ? Color.red.opacity(0.6) : Color.black.opacity(0.35), radius: isDraggingOverX ? 12 : 5, x: 0, y: 3)
                    .animation(.spring(response: 0.25, dampingFraction: 0.55), value: isDraggingOverX)
            }
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func accessoryButton(label: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(isActive ? Color.purple : Color.white.opacity(0.12))
        .cornerRadius(6)
    }
    
    private var accessoryKeysBar: some View {
        HStack(spacing: 6) {
            accessoryButton(label: "Ctrl", isActive: ctrlActive) {
                ctrlActive.toggle()
                webRTC.sendInput(event: ["type": "key", "vk": 17, "state": ctrlActive ? "down" : "up"])
            }
            
            accessoryButton(label: "Alt", isActive: altActive) {
                altActive.toggle()
                webRTC.sendInput(event: ["type": "key", "vk": 18, "state": altActive ? "down" : "up"])
            }
            
            accessoryButton(label: "Shift", isActive: shiftActive) {
                shiftActive.toggle()
                webRTC.sendInput(event: ["type": "key", "vk": 16, "state": shiftActive ? "down" : "up"])
            }
            
            accessoryButton(label: "Win", isActive: winActive) {
                winActive.toggle()
                webRTC.sendInput(event: ["type": "key", "vk": 91, "state": winActive ? "down" : "up"])
            }
            
            Button(action: {
                webRTC.sendInput(event: ["type": "key", "vk": 27, "state": "down"])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    webRTC.sendInput(event: ["type": "key", "vk": 27, "state": "up"])
                }
            }) {
                Text("Esc")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.white.opacity(0.12))
            .cornerRadius(6)
            
            // CAD Combo
            Button(action: sendCAD) {
                Text("C-A-D")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
                    .frame(width: 44, height: .infinity)
            }
            .background(Color.red.opacity(0.18))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.red.opacity(0.25), lineWidth: 1)
            )
            
            // Keyboard Toggler
            Button(action: {
                isKeyboardFocused = false
            }) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .foregroundColor(.cyan)
                    .frame(width: 44, height: .infinity)
            }
            .background(Color.white.opacity(0.12))
            .cornerRadius(6)
        }
        .frame(height: 38)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(red: 17/255, green: 25/255, blue: 40/255).opacity(0.95))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.35), radius: 5, x: 0, y: -2)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
    
    private var settingsOverlay: some View {
        ZStack {
            // Blur background
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    showConnectedSettings = false
                }
            
            // Modal content
            VStack(spacing: 20) {
                HStack {
                    Text("SESSION SETTINGS")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { showConnectedSettings = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title2)
                    }
                }
                .padding(.bottom, 5)
                
                VStack(alignment: .leading, spacing: 16) {
                    // Input Mode
                    VStack(alignment: .leading, spacing: 6) {
                        Text("INPUT MODE")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        HStack(spacing: 10) {
                            Button(action: { inputMode = "Direct" }) {
                                Text("Direct Touch")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(inputMode == "Direct" ? Color.purple : Color.white.opacity(0.1))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            
                            Button(action: { inputMode = "Trackpad" }) {
                                Text("Relative Trackpad")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(inputMode == "Trackpad" ? Color.purple : Color.white.opacity(0.1))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    
                    // Screen Scaling
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SCREEN SCALING")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        HStack(spacing: 10) {
                            Button(action: { scaleMode = .scaleAspectFit }) {
                                Text("Aspect Fit")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(scaleMode == .scaleAspectFit ? Color.purple : Color.white.opacity(0.1))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            
                            Button(action: { scaleMode = .scaleAspectFill }) {
                                Text("Aspect Fill")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(scaleMode == .scaleAspectFill ? Color.purple : Color.white.opacity(0.1))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    
                    Divider().background(Color.white.opacity(0.2))
                    
                    // Session Info
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CONNECTION DETAILS")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        HStack {
                            Text("Agent URL:")
                                .foregroundColor(.gray)
                            Spacer()
                            Text(agentUrl)
                                .foregroundColor(.white)
                        }
                        .font(.footnote)
                        
                        HStack {
                            Text("Latency (RTT):")
                                .foregroundColor(.gray)
                            Spacer()
                            Text(webRTC.rttMs)
                                .foregroundColor(.white)
                        }
                        .font(.footnote)
                    }
                }
                
                Button(action: {
                    showConnectedSettings = false
                    webRTC.disconnect()
                }) {
                    Text("Disconnect Session")
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.red)
                        .cornerRadius(8)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 17/255, green: 25/255, blue: 40/255))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 320)
            .padding(.horizontal, 20)
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

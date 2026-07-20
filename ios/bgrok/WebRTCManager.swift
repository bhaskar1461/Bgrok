import Foundation
import WebRTC
import Combine

class WebRTCManager: NSObject, ObservableObject {
    @Published var connectionStateString: String = "Disconnected"
    @Published var remoteVideoTrack: RTCVideoTrack? = nil
    @Published var rttMs: String = "--"
    @Published var isConnected: Bool = false
    
    private var peerConnectionFactory: RTCPeerConnectionFactory!
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var statsTimer: Timer?
    
    override init() {
        super.init()
        
        // Initialize WebRTC SSL and thread contexts
        RTCInitializeSSL()
        
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        self.peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
    }
    
    func connect(agentUrlString: String, width: Int, height: Int, fps: Int) {
        guard let agentUrl = URL(string: agentUrlString) else {
            print("bgrok: Invalid Agent URL format: \(agentUrlString)")
            return
        }
        
        DispatchQueue.main.async {
            self.connectionStateString = "Connecting"
        }
        
        // WebRTC peer connection configuration
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        self.peerConnection = self.peerConnectionFactory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )
        
        // Create inputs DataChannel
        let dataConfig = RTCDataChannelConfiguration()
        dataConfig.isOrdered = true
        self.dataChannel = self.peerConnection?.dataChannel(
            forLabel: "bgrok-inputs",
            configuration: dataConfig
        )
        self.dataChannel?.delegate = self
        
        // Request video stream from peer (essential for SDP offer structure)
        let transceiverInit = RTCRtpTransceiverInit()
        transceiverInit.direction = .recvOnly
        self.peerConnection?.addTransceiver(of: .video, init: transceiverInit)
        
        // Create WebRTC SDP Offer
        let sdpConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        self.peerConnection?.offer(for: sdpConstraints) { [weak self] (sdp, error) in
            guard let self = self else { return }
            if let error = error {
                print("bgrok: Error creating local offer: \(error)")
                DispatchQueue.main.async { self.disconnect() }
                return
            }
            
            guard let localSdp = sdp else { return }
            
            self.peerConnection?.setLocalDescription(localSdp) { [weak self] (error) in
                guard let self = self else { return }
                if let error = error {
                    print("bgrok: Error setting local description: \(error)")
                    DispatchQueue.main.async { self.disconnect() }
                    return
                }
                
                // Perform HTTP Signaling exchange with the Agent
                self.sendOfferToAgent(
                    agentUrl: agentUrl, 
                    sdp: localSdp.sdp, 
                    width: width, 
                    height: height, 
                    fps: fps
                )
            }
        }
    }
    
    private func sendOfferToAgent(agentUrl: URL, sdp: String, width: Int, height: Int, fps: Int) {
        let offerUrl = agentUrl.appendingPathComponent("offer")
        var request = URLRequest(url: offerUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "sdp": sdp,
            "type": "offer",
            "width": width,
            "height": height,
            "fps": fps
        ]
        
        guard let requestBody = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            print("bgrok: Failed to serialize offer request body.")
            DispatchQueue.main.async { self.disconnect() }
            return
        }
        request.httpBody = requestBody
        
        URLSession.shared.dataTask(with: request) { [weak self] (data, response, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("bgrok: HTTP signaling connection failed: \(error)")
                DispatchQueue.main.async { self.disconnect() }
                return
            }
            
            guard let responseData = data,
                  let responseJson = try? JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any],
                  let answerSdp = responseJson["sdp"] as? String else {
                print("bgrok: Signaling returned invalid JSON payload.")
                DispatchQueue.main.async { self.disconnect() }
                return
            }
            
            let remoteAnswer = RTCSessionDescription(type: .answer, sdp: answerSdp)
            self.peerConnection?.setRemoteDescription(remoteAnswer) { [weak self] (error) in
                if let error = error {
                    print("bgrok: Error applying remote SDP Answer: \(error)")
                    DispatchQueue.main.async { self?.disconnect() }
                } else {
                    print("bgrok: WebRTC handshake successfully negotiated.")
                    DispatchQueue.main.async {
                        self?.startStatsTimer()
                    }
                }
            }
        }.resume()
    }
    
    func sendInput(event: [String: Any]) {
        guard let channel = self.dataChannel, channel.readyState == .open else {
            return
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: event, options: []) else {
            return
        }
        
        let buffer = RTCDataBuffer(data: jsonData, isBinary: false)
        channel.send(buffer)
    }
    
    func disconnect() {
        self.statsTimer?.invalidate()
        self.statsTimer = nil
        
        self.dataChannel?.close()
        self.dataChannel = nil
        
        self.peerConnection?.close()
        self.peerConnection = nil
        
        DispatchQueue.main.async {
            self.remoteVideoTrack = nil
            self.connectionStateString = "Disconnected"
            self.isConnected = false
            self.rttMs = "--"
        }
    }
    
    private func startStatsTimer() {
        self.statsTimer?.invalidate()
        self.statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.queryStats()
        }
    }
    
    private func queryStats() {
        self.peerConnection?.statistics { [weak self] (report) in
            guard let self = self else { return }
            for (_, stat) in report.statistics {
                if stat.type == "candidate-pair" && stat.values["state"] == "succeeded" {
                    if let rttString = stat.values["currentRoundTripTime"],
                       let rttSeconds = Double(rttString) {
                        DispatchQueue.main.async {
                            self.rttMs = String(format: "%.1f ms", rttSeconds * 1000)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCManager: RTCPeerConnectionDelegate {
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCIceConnectionState) {
        print("bgrok: ICE Connection State changed to \(stateChanged.rawValue)")
        DispatchQueue.main.async {
            switch stateChanged {
            case .connected, .completed:
                self.connectionStateString = "Connected"
                self.isConnected = true
            case .failed:
                self.connectionStateString = "Failed"
                self.disconnect()
            case .closed:
                self.connectionStateString = "Disconnected"
                self.disconnect()
            case .checking:
                self.connectionStateString = "Checking"
            default:
                break
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCIceGatheringState) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // LAN connection exchange relies fully on offer/answer gathering candidates before handshake completes.
        // If gathering takes place post-handshake, candidates can be ignored as direct routing is already active.
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    
    // Remote Video Track received
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd receiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        if let videoTrack = receiver.track as? RTCVideoTrack {
            print("bgrok: Incoming Video Stream Track detected.")
            DispatchQueue.main.async {
                self.remoteVideoTrack = videoTrack
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {}
}

// MARK: - RTCDataChannelDelegate
extension WebRTCManager: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("bgrok: DataChannel State: \(dataChannel.readyState.rawValue)")
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        // App is a transmitter of mouse/key actions; client is not expecting incoming data streams in v1.
    }
}

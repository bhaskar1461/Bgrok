import SwiftUI
import WebRTC

struct VideoPlayerView: UIViewRepresentable {
    /// The WebRTC video track to render
    let videoTrack: RTCVideoTrack?
    let scaleMode: UIView.ContentMode
    let onMouseMove: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let metalView = RTCMTLVideoView()
        metalView.videoContentMode = scaleMode
        
        let hoverGesture = UIHoverGestureRecognizer(
            target: context.coordinator, 
            action: #selector(Coordinator.handleHover(_:))
        )
        metalView.addGestureRecognizer(hoverGesture)
        
        return metalView
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        if uiView.videoContentMode != scaleMode {
            uiView.videoContentMode = scaleMode
        }
        
        context.coordinator.onMouseMove = onMouseMove
        
        // Track changes to prevent redundant listeners and leaks
        if context.coordinator.currentTrack != videoTrack {
            // Remove view renderer from previous track if it exists
            if let oldTrack = context.coordinator.currentTrack {
                oldTrack.remove(uiView)
            }
            
            // Set new track and attach view
            context.coordinator.currentTrack = videoTrack
            if let newTrack = videoTrack {
                newTrack.add(uiView)
                logger.info("VideoPlayerView attached RTCMTLVideoView to remote video track.")
            }
        }
    }
    
    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        if let activeTrack = coordinator.currentTrack {
            activeTrack.remove(uiView)
        }
    }

    class Coordinator: NSObject {
        var currentTrack: RTCVideoTrack?
        var onMouseMove: ((CGPoint) -> Void)?
        
        @objc func handleHover(_ gesture: UIHoverGestureRecognizer) {
            guard let view = gesture.view, let onMouseMove = onMouseMove else { return }
            let location = gesture.location(in: view)
            if gesture.state == .changed || gesture.state == .began {
                onMouseMove(location)
            }
        }
    }
}

// Lightweight logger
private let logger = Logger(label: "bgrok.VideoPlayerView")
private struct Logger {
    let label: String
    func info(_ msg: String) { print("[\(label)] INFO: \(msg)") }
}

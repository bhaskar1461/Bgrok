import SwiftUI
import WebRTC

struct VideoPlayerView: UIViewRepresentable {
    /// The WebRTC video track to render
    let videoTrack: RTCVideoTrack?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let metalView = RTCMTLVideoView()
        // scaleAspectFit maintains desktop aspect ratio with black bars as needed
        metalView.videoContentMode = .scaleAspectFit
        return metalView
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
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

    class Coordinator {
        var currentTrack: RTCVideoTrack?
    }
}

// Lightweight logger
private let logger = Logger(label: "bgrok.VideoPlayerView")
private struct Logger {
    let label: String
    func info(_ msg: String) { print("[\(label)] INFO: \(msg)") }
}

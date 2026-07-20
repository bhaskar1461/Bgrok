use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tokio::time::sleep;
use tokio_tungstenite::connect_async_tls_with_config;
use tokio_tungstenite::tungstenite::protocol::Message;
use futures::sink::SinkExt;
use futures::stream::StreamExt;
use serde::{Deserialize, Serialize};
use openh264::formats::{RgbSliceU8, YUVBuffer};
use openh264::encoder::Encoder;
use webrtc::api::media_engine::MediaEngine;
use webrtc::api::APIBuilder;
use webrtc::media::Sample;
use webrtc::peer_connection::configuration::RTCConfiguration;
use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;
use webrtc::rtp_transceiver::rtp_codec::RTCRtpCodecCapability;
use webrtc::track::track_local::track_local_static_sample::TrackLocalStaticSample;
use webrtc::track::track_local::TrackLocal;
use webrtc::data_channel::data_channel_message::DataChannelMessage;
use webrtc::ice_transport::ice_candidate::RTCIceCandidateInit;

mod screen_capture;
mod input_injector;

use screen_capture::ScreenCapture;
use input_injector::InputInjector;

// --- Relay protocol messages ---

/// What the relay forwards to us when a client sends a signal
#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "type")]
enum RelayMessage {
    #[serde(rename = "registered")]
    Registered { role: String },
    #[serde(rename = "signal")]
    Signal {
        sender: String,
        payload: serde_json::Value,
    },
    #[serde(rename = "pair_request")]
    PairRequest {
        client_id: String,
        pairing_code: Option<String>,
        client_pubkey: Option<String>,
    },
    #[serde(rename = "error")]
    Error { message: String },
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    println!("Tether Native Rust Agent Starting...");

    // Initialize screen capture and input injector
    ScreenCapture::start()?;
    let injector = Arc::new(InputInjector::new());

    // Connect to signaling relay (with self-signed cert support)
    let relay_url = "wss://bgrok.cc.cd:8765/ws";
    let agent_id = "bgrok-laptop-default";
    println!("Connecting to Signaling Relay at: {}", relay_url);

    // Build a TLS connector that accepts self-signed certificates (dev mode)
    let tls_connector = native_tls::TlsConnector::builder()
        .danger_accept_invalid_certs(true)
        .build()?;
    let tls_connector = tokio_tungstenite::Connector::NativeTls(tls_connector);

    let (ws_stream, _) = connect_async_tls_with_config(
        relay_url,
        None,
        false,
        Some(tls_connector),
    ).await?;
    let (ws_write, mut ws_read) = ws_stream.split();
    let ws_write = Arc::new(Mutex::new(ws_write));
    println!("Connected to Signaling Relay.");

    // Register as agent with the relay
    {
        let register_msg = serde_json::json!({
            "type": "register_agent",
            "agent_id": agent_id
        });
        let mut ws_w = ws_write.lock().await;
        ws_w.send(Message::Text(register_msg.to_string())).await?;
        println!("Sent agent registration for ID: {}", agent_id);
    }

    // WebRTC connection state
    let active_connection: Arc<Mutex<Option<Arc<webrtc::peer_connection::RTCPeerConnection>>>> = Arc::new(Mutex::new(None));

    // Handle WebSocket messages from relay
    while let Some(msg_res) = ws_read.next().await {
        let msg = match msg_res {
            Ok(m) => m,
            Err(e) => {
                println!("WebSocket read error: {}", e);
                break;
            }
        };

        if let Message::Text(text) = msg {
            let parsed: Result<RelayMessage, _> = serde_json::from_str(&text);
            match parsed {
                Ok(RelayMessage::Registered { role }) => {
                    println!("Successfully registered with relay as: {}", role);
                }
                Ok(RelayMessage::Signal { sender, payload }) => {
                    // Extract the SDP from the signal payload
                    let sdp_type = payload.get("type").and_then(|v| v.as_str()).unwrap_or("");
                    let sdp_str = payload.get("sdp").and_then(|v| v.as_str()).unwrap_or("");

                    if sdp_type == "offer" && !sdp_str.is_empty() {
                        println!("Received WebRTC SDP Offer from client '{}'.", sender);

                        // Initialize WebRTC API
                        let mut m = MediaEngine::default();
                        m.register_default_codecs()?;
                        let api = APIBuilder::new().with_media_engine(m).build();

                        let config = RTCConfiguration::default();
                        let peer_connection = Arc::new(api.new_peer_connection(config).await?);

                        // Create video track
                        let video_track = Arc::new(TrackLocalStaticSample::new(
                            RTCRtpCodecCapability {
                                mime_type: "video/H264".to_owned(),
                                ..Default::default()
                            },
                            "video".to_owned(),
                            "webrtc-rs".to_owned(),
                        ));

                        let rtp_sender = peer_connection
                            .add_track(Arc::clone(&video_track) as Arc<dyn TrackLocal + Send + Sync>)
                            .await?;

                        // Spawn RTCP reader
                        tokio::spawn(async move {
                            let mut rtp_buf = vec![0u8; 1500];
                            while let Ok((_, _)) = rtp_sender.read(&mut rtp_buf).await {}
                        });

                        // Set up Data Channel for input events
                        let injector_clone = Arc::clone(&injector);
                        peer_connection.on_data_channel(Box::new(move |d| {
                            let d_label = d.label().to_owned();
                            let injector_data = Arc::clone(&injector_clone);
                            Box::pin(async move {
                                if d_label == "bgrok-inputs" {
                                    d.on_message(Box::new(move |msg: DataChannelMessage| {
                                        let text = String::from_utf8(msg.data.to_vec()).unwrap_or_default();
                                        let injector_data = Arc::clone(&injector_data);
                                        Box::pin(async move {
                                            if let Ok(val) = serde_json::from_str::<serde_json::Value>(&text) {
                                                if let Some(event_type) = val.get("type").and_then(|v| v.as_str()) {
                                                    match event_type {
                                                        "mouse_move_abs" => {
                                                            let x = val.get("x").and_then(|v| v.as_f64()).unwrap_or(0.0);
                                                            let y = val.get("y").and_then(|v| v.as_f64()).unwrap_or(0.0);
                                                            injector_data.mouse_move_abs(x, y);
                                                        }
                                                        "mouse_move_rel" => {
                                                            let dx = val.get("dx").and_then(|v| v.as_f64()).unwrap_or(0.0);
                                                            let dy = val.get("dy").and_then(|v| v.as_f64()).unwrap_or(0.0);
                                                            injector_data.mouse_move_rel(dx as i32, dy as i32);
                                                        }
                                                        "mouse_button" => {
                                                            let button = val.get("button").and_then(|v| v.as_str()).unwrap_or("left");
                                                            let state = val.get("state").and_then(|v| v.as_str()).unwrap_or("down");
                                                            injector_data.mouse_click(button, state);
                                                        }
                                                        "mouse_scroll" => {
                                                            let dx = val.get("dx").and_then(|v| v.as_f64()).unwrap_or(0.0);
                                                            let dy = val.get("dy").and_then(|v| v.as_f64()).unwrap_or(0.0);
                                                            injector_data.mouse_scroll(dx, dy);
                                                        }
                                                        "key" => {
                                                            let vk = val.get("vk").and_then(|v| v.as_u64()).unwrap_or(0) as u16;
                                                            let state = val.get("state").and_then(|v| v.as_str()).unwrap_or("down");
                                                            injector_data.keyboard_key(vk, state);
                                                        }
                                                        _ => {}
                                                    }
                                                }
                                            }
                                        })
                                    }));
                                }
                            })
                        }));

                        // Forward ICE candidates back to the client through the relay
                        let ws_write_ice = Arc::clone(&ws_write);
                        let sender_id = sender.clone();
                        peer_connection.on_ice_candidate(Box::new(move |candidate| {
                            if let Some(c) = candidate {
                                let ws_w = Arc::clone(&ws_write_ice);
                                let dest = sender_id.clone();
                                Box::pin(async move {
                                    if let Ok(candidate_json) = c.to_json() {
                                        let ice_msg = serde_json::json!({
                                            "type": "signal",
                                            "dest": dest,
                                            "payload": {
                                                "type": "candidate",
                                                "candidate": candidate_json.candidate,
                                                "sdpMLineIndex": candidate_json.sdp_mline_index,
                                                "sdpMid": candidate_json.sdp_mid
                                            }
                                        });
                                        let mut ws_w = ws_w.lock().await;
                                        let _ = ws_w.send(Message::Text(ice_msg.to_string())).await;
                                    }
                                })
                            } else {
                                Box::pin(async {})
                            }
                        }));

                        // Set remote SDP description
                        let desc = RTCSessionDescription::offer(sdp_str.to_string())?;
                        peer_connection.set_remote_description(desc).await?;

                        // Create answer SDP
                        let answer = peer_connection.create_answer(None).await?;
                        peer_connection.set_local_description(answer.clone()).await?;

                        // Send local SDP answer back to client through relay signal envelope
                        let answer_msg = serde_json::json!({
                            "type": "signal",
                            "dest": sender,
                            "payload": {
                                "sdp": answer.sdp,
                                "type": "answer"
                            }
                        });
                        {
                            let mut ws_w = ws_write.lock().await;
                            ws_w.send(Message::Text(answer_msg.to_string())).await?;
                        }
                        println!("Sent SDP Answer back to client '{}'.", sender);

                        // Spawn frame capturing and encoding task
                        let peer_conn_status = Arc::clone(&peer_connection);
                        tokio::spawn(async move {
                            println!("Starting frame encoding loop...");
                            let mut encoder = match Encoder::new() {
                                Ok(enc) => enc,
                                Err(e) => {
                                    println!("Failed to create openh264 encoder: {:?}", e);
                                    return;
                                }
                            };

                            loop {
                                let state = peer_conn_status.connection_state();
                                if state == RTCPeerConnectionState::Failed
                                    || state == RTCPeerConnectionState::Closed
                                    || state == RTCPeerConnectionState::Disconnected
                                {
                                    break;
                                }

                                let start_time = tokio::time::Instant::now();

                                if let Some(rgb_frame) = ScreenCapture::grab() {
                                    let rgb_slice = RgbSliceU8::new(&rgb_frame, (1280, 720));
                                    let yuv_buffer = YUVBuffer::from_rgb_source(rgb_slice);

                                    let mut h264_bytes = Vec::new();
                                    let mut encode_success = false;
                                    {
                                        if let Ok(bitstream) = encoder.encode(&yuv_buffer) {
                                            h264_bytes = bitstream.to_vec();
                                            encode_success = true;
                                        }
                                    }

                                    if encode_success && !h264_bytes.is_empty() {
                                        let sample = Sample {
                                            data: h264_bytes.into(),
                                            duration: Duration::from_millis(33),
                                            ..Default::default()
                                        };
                                        if let Err(e) = video_track.write_sample(&sample).await {
                                            println!("Track write sample error: {}", e);
                                            break;
                                        }
                                    }
                                }

                                let elapsed = start_time.elapsed();
                                let target_delay = Duration::from_millis(33);
                                if elapsed < target_delay {
                                    sleep(target_delay - elapsed).await;
                                }
                            }
                            println!("Frame encoding loop ended.");
                        });

                        // Store active connection
                        let mut active_conn_lock = active_connection.lock().await;
                        *active_conn_lock = Some(peer_connection);
                    }
                    // Handle ICE candidate from client
                    else if sdp_type == "candidate" || payload.get("candidate").is_some() {
                        let active_conn_lock = active_connection.lock().await;
                        if let Some(ref peer_connection) = *active_conn_lock {
                            let candidate = payload.get("candidate").and_then(|v| v.as_str()).unwrap_or("").to_string();
                            let sdp_mline_index = payload.get("sdpMLineIndex").and_then(|v| v.as_u64()).map(|v| v as u16);
                            let sdp_mid = payload.get("sdpMid").and_then(|v| v.as_str()).map(|s| s.to_string());

                            let candidate_init = RTCIceCandidateInit {
                                candidate,
                                sdp_mline_index,
                                sdp_mid,
                                username_fragment: None,
                            };
                            if let Err(e) = peer_connection.add_ice_candidate(candidate_init).await {
                                println!("Failed to add ICE candidate: {}", e);
                            }
                        }
                    }
                }
                Ok(RelayMessage::PairRequest { client_id, pairing_code, .. }) => {
                    println!("Received pairing request from client '{}' with code {:?}", client_id, pairing_code);
                    // Auto-approve for now (TODO: implement proper pairing verification)
                    let response = serde_json::json!({
                        "type": "pair_response",
                        "client_id": client_id,
                        "status": "approved"
                    });
                    let mut ws_w = ws_write.lock().await;
                    let _ = ws_w.send(Message::Text(response.to_string())).await;
                    println!("Auto-approved pairing for client '{}'.", client_id);
                }
                Ok(RelayMessage::Error { message }) => {
                    println!("Relay error: {}", message);
                }
                Err(e) => {
                    println!("Signaling JSON parse error: {} — raw: {}", e, text);
                }
            }
        }
    }

    Ok(())
}

use std::sync::{Arc, Mutex};
use lazy_static::lazy_static;
use windows_capture::{
    capture::{Context, GraphicsCaptureApiHandler, CaptureControl},
    frame::Frame,
    graphics_capture_api::InternalCaptureControl,
    monitor::Monitor,
    settings::{ColorFormat, CursorCaptureSettings, DirtyRegionSettings, DrawBorderSettings, MinimumUpdateIntervalSettings, SecondaryWindowSettings, Settings},
};

lazy_static! {
    static ref LATEST_FRAME: Arc<Mutex<Option<Vec<u8>>>> = Arc::new(Mutex::new(None));
    static ref CAPTURE_CONTROL: Arc<Mutex<Option<CaptureControl<WgcHandler, Box<dyn std::error::Error + Send + Sync>>>>> = Arc::new(Mutex::new(None));
}

pub struct WgcHandler;

impl GraphicsCaptureApiHandler for WgcHandler {
    type Flags = ();
    type Error = Box<dyn std::error::Error + Send + Sync>;

    fn new(_ctx: Context<Self::Flags>) -> Result<Self, Self::Error> {
        Ok(WgcHandler)
    }

    fn on_frame_arrived(
        &mut self,
        frame: &mut Frame,
        _capture_control: InternalCaptureControl,
    ) -> Result<(), Self::Error> {
        let mut frame_buffer = frame.buffer()?;
        let width = frame_buffer.width() as usize;
        let height = frame_buffer.height() as usize;
        let row_pitch = frame_buffer.row_pitch() as usize;
        let buffer = frame_buffer.as_raw_buffer();

        // Target dimensions: 1280x720
        let target_width = 1280usize;
        let target_height = 720usize;
        let mut rgb_dest = vec![0u8; target_width * target_height * 3];

        let scale_x = width as f32 / target_width as f32;
        let scale_y = height as f32 / target_height as f32;

        for y in 0..target_height {
            let src_y = ((y as f32 * scale_y) as usize).min(height - 1);
            let src_row_offset = src_y * row_pitch;
            let dest_row_offset = y * target_width * 3;

            for x in 0..target_width {
                let src_x = ((x as f32 * scale_x) as usize).min(width - 1);
                let src_idx = src_row_offset + src_x * 4;
                let dest_idx = dest_row_offset + x * 3;

                // BGRA -> RGB (windows-capture Rgba8 is BGRA internally)
                rgb_dest[dest_idx] = buffer[src_idx + 2];     // R
                rgb_dest[dest_idx + 1] = buffer[src_idx + 1]; // G
                rgb_dest[dest_idx + 2] = buffer[src_idx];     // B
            }
        }

        // Store the downscaled RGB frame
        let mut latest_frame_lock = LATEST_FRAME.lock().unwrap();
        *latest_frame_lock = Some(rgb_dest);

        Ok(())
    }

    fn on_closed(&mut self) -> Result<(), Self::Error> {
        println!("Tether: Capture closed.");
        Ok(())
    }
}

pub struct ScreenCapture;

impl ScreenCapture {
    pub fn start() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        // Find primary monitor
        let monitor = Monitor::primary().map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        
        let settings = Settings::new(
            monitor,
            CursorCaptureSettings::Default,
            DrawBorderSettings::Default,
            SecondaryWindowSettings::Default,
            MinimumUpdateIntervalSettings::Default,
            DirtyRegionSettings::Default,
            ColorFormat::Rgba8, 
            (),
        );

        let control = WgcHandler::start_free_threaded(settings).map_err(|e| {
            let boxed_err = format!("GraphicsCaptureApiError: {:?}", e);
            Box::new(std::io::Error::new(std::io::ErrorKind::Other, boxed_err)) as Box<dyn std::error::Error + Send + Sync>
        })?;
        
        let mut control_lock = CAPTURE_CONTROL.lock().unwrap();
        *control_lock = Some(control);
        println!("Tether: Started WGC screen capture on background thread.");
        Ok(())
    }

    pub fn grab() -> Option<Vec<u8>> {
        let latest_frame_lock = LATEST_FRAME.lock().unwrap();
        latest_frame_lock.clone()
    }

    pub fn stop() {
        let mut control_lock = CAPTURE_CONTROL.lock().unwrap();
        if let Some(control) = control_lock.take() {
            let _ = control.stop();
        }
    }
}

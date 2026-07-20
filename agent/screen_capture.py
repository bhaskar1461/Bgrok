"""
Screen capture using Windows Graphics Capture (WGC) API via windows-capture.

GDI BitBlt (mss, Pillow) and DXGI DuplicateOutput (dxcam) both fail on this
system due to GPU-accelerated scheduling and UIPI restrictions.  WGC is the
modern Windows 10+ capture API and works reliably without elevation.
"""

import asyncio
import logging
import threading
import time
import numpy as np
import cv2
from aiortc import VideoStreamTrack
from av import VideoFrame
from windows_capture import WindowsCapture, Frame, CaptureControl

logger = logging.getLogger(__name__)


class _WGCGrabber:
    """
    Background thread that continuously captures frames via WGC and stores
    the latest one for the WebRTC track to consume.
    """

    def __init__(self):
        self._latest_frame = None
        self._lock = threading.Lock()
        self._started = threading.Event()
        self._capture_control = None
        self._width = 0
        self._height = 0
        self._thread = None

    def start(self):
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        # Wait up to 5 seconds for the first frame
        if not self._started.wait(timeout=5.0):
            raise RuntimeError("WGC capture did not produce a frame in 5 seconds")
        logger.info(
            f"WGC grabber running: {self._width}x{self._height}"
        )

    def _run(self):
        capture = WindowsCapture(
            cursor_capture=None,
            draw_border=None,
            monitor_index=None,
            window_name=None,
        )

        grabber = self  # capture reference for closures

        @capture.event
        def on_frame_arrived(frame: Frame, capture_control: CaptureControl):
            # frame.frame_buffer is a numpy array in BGRA format (H, W, 4)
            # We must copy it because the buffer is invalidated after callback returns
            try:
                bgra = frame.frame_buffer.copy()
                with grabber._lock:
                    grabber._latest_frame = bgra
                    grabber._width = frame.width
                    grabber._height = frame.height
                if not grabber._started.is_set():
                    grabber._started.set()
                    grabber._capture_control = capture_control
            except Exception as e:
                logger.error(f"WGC on_frame_arrived error: {e}")


        @capture.event
        def on_closed():
            logger.info("WGC capture session closed.")

        # This blocks the thread — runs the WGC message pump
        try:
            capture.start_free_threaded()
        except Exception as e:
            logger.error(f"WGC capture.start() failed: {e}")

    def grab(self):
        """Return the latest BGR numpy frame, or None."""
        with self._lock:
            return self._latest_frame

    def stop(self):
        if self._capture_control:
            try:
                self._capture_control.stop()
            except Exception:
                pass


# Module-level singleton so multiple ScreenCaptureTracks share one grabber
_wgc_grabber = None
_wgc_lock = threading.Lock()


def _get_grabber():
    global _wgc_grabber
    with _wgc_lock:
        if _wgc_grabber is None:
            _wgc_grabber = _WGCGrabber()
            _wgc_grabber.start()
        return _wgc_grabber


class ScreenCaptureTrack(VideoStreamTrack):
    """WebRTC video track that streams the desktop via WGC."""

    def __init__(self, fps=30, target_width=1280, target_height=720):
        super().__init__()
        self.fps = fps
        self.target_width = target_width
        self.target_height = target_height
        self.frame_interval = 1.0 / fps
        self.last_frame_time = 0
        self._error_count = 0

        # Start (or reuse) the WGC grabber
        self._grabber = _get_grabber()
        logger.info(
            f"ScreenCaptureTrack (WGC): "
            f"Streaming {target_width}x{target_height} @ {fps} FPS"
        )

    async def recv(self):
        pts, time_base = await self.next_timestamp()

        # Throttle to target FPS
        now = time.time()
        elapsed = now - self.last_frame_time
        if elapsed < self.frame_interval:
            await asyncio.sleep(self.frame_interval - elapsed)
        self.last_frame_time = time.time()

        try:
            bgr = self._grabber.grab()
            if bgr is None:
                raise RuntimeError("No frame available from WGC")

            # Convert BGRA -> RGB
            rgb = cv2.cvtColor(bgr, cv2.COLOR_BGRA2RGB)

            # Resize to target dimensions
            h, w = rgb.shape[:2]
            if w != self.target_width or h != self.target_height:
                rgb = cv2.resize(
                    rgb,
                    (self.target_width, self.target_height),
                    interpolation=cv2.INTER_AREA,
                )

            frame = VideoFrame.from_ndarray(rgb, format="rgb24")
            frame.pts = pts
            frame.time_base = time_base

            if self._error_count > 0:
                logger.info(
                    f"Screen capture recovered after {self._error_count} errors."
                )
                self._error_count = 0

            return frame

        except Exception as e:
            self._error_count += 1
            if self._error_count <= 3 or self._error_count % 60 == 0:
                logger.error(f"Screen capture error: {e}")

            blank = np.zeros(
                (self.target_height, self.target_width, 3), dtype=np.uint8
            )
            cv2.putText(
                blank,
                "Screen Capture Error",
                (50, self.target_height // 2),
                cv2.FONT_HERSHEY_SIMPLEX,
                1.0,
                (0, 0, 255),
                2,
            )
            frame = VideoFrame.from_ndarray(blank, format="rgb24")
            frame.pts = pts
            frame.time_base = time_base
            return frame

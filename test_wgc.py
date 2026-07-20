from windows_capture import WindowsCapture, Frame, CaptureControl
import time
import numpy as np

capture = WindowsCapture(cursor_capture=None, draw_border=None, monitor_index=None, window_name=None)

@capture.event
def on_frame_arrived(frame: Frame, capture_control: CaptureControl):
    bgr = frame.convert_to_bgr()
    print("type:", type(bgr))
    has_shape = hasattr(bgr, "shape")
    print("has shape:", has_shape)
    if has_shape:
        print("shape:", bgr.shape, "dtype:", bgr.dtype)
    else:
        attrs = [x for x in dir(bgr) if not x.startswith("_")]
        print("dir:", attrs)
        arr = np.array(bgr)
        print("np.array shape:", arr.shape, "dtype:", arr.dtype)

    fb = frame.frame_buffer
    print("frame_buffer type:", type(fb))
    has_shape2 = hasattr(fb, "shape")
    print("frame_buffer has shape:", has_shape2)
    if has_shape2:
        print("frame_buffer shape:", fb.shape, "dtype:", fb.dtype)
    else:
        arr2 = np.array(fb)
        print("frame_buffer np.array shape:", arr2.shape, "dtype:", arr2.dtype)

    capture_control.stop()

@capture.event
def on_closed():
    pass

capture.start_free_threaded()
time.sleep(3)

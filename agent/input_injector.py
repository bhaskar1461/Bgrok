import ctypes
import logging

# Set up logging
logger = logging.getLogger(__name__)

# Win32 Constants
INPUT_MOUSE = 0
INPUT_KEYBOARD = 1

# Mouse Event Flags
MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_RIGHTDOWN = 0x0008
MOUSEEVENTF_RIGHTUP = 0x0010
MOUSEEVENTF_MIDDLEDOWN = 0x0020
MOUSEEVENTF_MIDDLEUP = 0x0040
MOUSEEVENTF_WHEEL = 0x0800
MOUSEEVENTF_HWHEEL = 0x01000
MOUSEEVENTF_ABSOLUTE = 0x8000
MOUSEEVENTF_VIRTUALDESK = 0x4000

# Keyboard Event Flags
KEYEVENTF_EXTENDEDKEY = 0x0001
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_UNICODE = 0x0004
KEYEVENTF_SCANCODE = 0x0008

# Structs for Win32 SendInput
class MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", ctypes.c_long),
        ("dy", ctypes.c_long),
        ("mouseData", ctypes.c_ulong),
        ("dwFlags", ctypes.c_ulong),
        ("time", ctypes.c_ulong),
        ("dwExtraInfo", ctypes.c_void_p)
    ]

class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", ctypes.c_ushort),
        ("wScan", ctypes.c_ushort),
        ("dwFlags", ctypes.c_ulong),
        ("time", ctypes.c_ulong),
        ("dwExtraInfo", ctypes.c_void_p)
    ]

class HARDWAREINPUT(ctypes.Structure):
    _fields_ = [
        ("uMsg", ctypes.c_ulong),
        ("wParamL", ctypes.c_ushort),
        ("wParamH", ctypes.c_ushort)
    ]

class INPUT_UNION(ctypes.Union):
    _fields_ = [
        ("mi", MOUSEINPUT),
        ("ki", KEYBDINPUT),
        ("hi", HARDWAREINPUT)
    ]

class INPUT(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_ulong),
        ("u", INPUT_UNION)
    ]

class InputInjector:
    def __init__(self):
        self.extra = ctypes.c_void_p(0)
        # Declare prototype for User32.SendInput to prevent 64-bit pointer truncation
        try:
            ctypes.windll.user32.SendInput.argtypes = [ctypes.c_uint, ctypes.POINTER(INPUT), ctypes.c_int]
            ctypes.windll.user32.SendInput.restype = ctypes.c_uint
        except Exception as e:
            logger.warning(f"Failed to declare SendInput prototype: {e}")

        # Pre-open the interactive Default desktop
        try:
            # DESKTOP_ALL_ACCESS = 0x1FF
            self.h_default = ctypes.windll.user32.OpenDesktopW('Default', 0, False, 0x1FF)
            if self.h_default:
                logger.info("Successfully opened 'Default' desktop handle")
            else:
                logger.error(f"Failed to open 'Default' desktop: {ctypes.GetLastError()}")
        except Exception as e:
            logger.error(f"Error opening 'Default' desktop: {e}")
            self.h_default = None

        logger.info("Win32 InputInjector initialized successfully")

    def _send_input(self, inp):
        """Helper to invoke User32.SendInput API on the interactive 'Default' desktop."""
        h_orig = None
        switched = False
        try:
            user32 = ctypes.windll.user32
            kernel32 = ctypes.windll.kernel32
            
            if self.h_default:
                h_orig = user32.GetThreadDesktop(kernel32.GetCurrentThreadId())
                switched = bool(user32.SetThreadDesktop(self.h_default))
                
            result = user32.SendInput(1, ctypes.pointer(inp), ctypes.sizeof(inp))
            if result == 0:
                err = ctypes.GetLastError()
                logger.error(f"SendInput returned 0, GetLastError={err}")
            return result > 0
        except Exception as e:
            logger.error(f"Error executing SendInput: {e}")
            return False
        finally:
            if switched and h_orig:
                try:
                    ctypes.windll.user32.SetThreadDesktop(h_orig)
                except Exception:
                    pass

    def __del__(self):
        if hasattr(self, 'h_default') and self.h_default:
            try:
                ctypes.windll.user32.CloseDesktop(self.h_default)
            except Exception:
                pass

    def mouse_move_rel(self, dx, dy):
        """Relative mouse movement."""
        ii = INPUT_UNION()
        ii.mi = MOUSEINPUT(int(dx), int(dy), 0, MOUSEEVENTF_MOVE, 0, self.extra)
        inp = INPUT(INPUT_MOUSE, ii)
        self._send_input(inp)

    def mouse_move_abs(self, x_norm, y_norm):
        """Absolute mouse movement. x_norm and y_norm should be between 0.0 and 1.0."""
        # Map normalized coordinates to Win32 absolute range: 0 to 65535
        # We also include VIRTUALDESK to ensure compatibility with multi-monitor set-ups
        x_win = int(max(0.0, min(1.0, x_norm)) * 65535)
        y_win = int(max(0.0, min(1.0, y_norm)) * 65535)
        
        ii = INPUT_UNION()
        ii.mi = MOUSEINPUT(x_win, y_win, 0, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK, 0, self.extra)
        inp = INPUT(INPUT_MOUSE, ii)
        self._send_input(inp)

    def mouse_click(self, button, state):
        """
        Mouse button state trigger.
        button: 'left', 'right', 'middle'
        state: 'down', 'up'
        """
        flags = 0
        if button == 'left':
            flags = MOUSEEVENTF_LEFTDOWN if state == 'down' else MOUSEEVENTF_LEFTUP
        elif button == 'right':
            flags = MOUSEEVENTF_RIGHTDOWN if state == 'down' else MOUSEEVENTF_RIGHTUP
        elif button == 'middle':
            flags = MOUSEEVENTF_MIDDLEDOWN if state == 'down' else MOUSEEVENTF_MIDDLEUP
        else:
            logger.warning(f"Unknown mouse button click event: {button}")
            return
            
        ii = INPUT_UNION()
        ii.mi = MOUSEINPUT(0, 0, 0, flags, 0, self.extra)
        inp = INPUT(INPUT_MOUSE, ii)
        self._send_input(inp)

    def mouse_scroll(self, dx, dy):
        """
        Mouse scrolling event.
        dy: Vertical scroll (positive = scroll up, negative = scroll down)
        dx: Horizontal scroll (positive = scroll right, negative = scroll left)
        """
        if dy != 0:
            # Vertical scroll: amount in mouseData
            # Win32 WHEEL_DELTA = 120
            # Scale the scroll input (e.g., dy * 120)
            amount = int(dy * 120)
            ii = INPUT_UNION()
            ii.mi = MOUSEINPUT(0, 0, amount, MOUSEEVENTF_WHEEL, 0, self.extra)
            inp = INPUT(INPUT_MOUSE, ii)
            self._send_input(inp)
            
        if dx != 0:
            # Horizontal scroll
            amount = int(dx * 120)
            ii = INPUT_UNION()
            ii.mi = MOUSEINPUT(0, 0, amount, MOUSEEVENTF_HWHEEL, 0, self.extra)
            inp = INPUT(INPUT_MOUSE, ii)
            self._send_input(inp)

    def keyboard_key(self, vk_code, state):
        """
        Keyboard key state trigger.
        vk_code: Virtual Key Code (integer)
        state: 'down', 'up'
        """
        flags = 0
        if state == 'up':
            flags |= KEYEVENTF_KEYUP
            
        # Optional: check if key is extended (e.g., arrow keys, Insert, Delete, etc.)
        # Extended keys need the KEYEVENTF_EXTENDEDKEY flag.
        # Common extended keys: PageUp, PageDown, End, Home, Left, Up, Right, Down, Insert, Delete.
        extended_vks = [0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E]
        if vk_code in extended_vks:
            flags |= KEYEVENTF_EXTENDEDKEY

        ii = INPUT_UNION()
        ii.ki = KEYBDINPUT(int(vk_code), 0, flags, 0, self.extra)
        inp = INPUT(INPUT_KEYBOARD, ii)
        self._send_input(inp)
        
    def process_event(self, data):
        """Parses inputs received over WebRTC Data Channel JSON."""
        try:
            event_type = data.get("type")
            if not event_type:
                return

            if event_type == "mouse_move_rel":
                self.mouse_move_rel(data.get("dx", 0), data.get("dy", 0))
            elif event_type == "mouse_move_abs":
                self.mouse_move_abs(data.get("x", 0.0), data.get("y", 0.0))
            elif event_type == "mouse_button":
                self.mouse_click(data.get("button"), data.get("state"))
            elif event_type == "mouse_scroll":
                self.mouse_scroll(data.get("dx", 0), data.get("dy", 0))
            elif event_type == "key":
                self.keyboard_key(data.get("vk"), data.get("state"))
            else:
                logger.warning(f"Unrecognized event payload: {data}")
        except Exception as e:
            logger.error(f"Error parsing event: {e}")

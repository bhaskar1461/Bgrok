import ctypes
import time

# Input types
INPUT_MOUSE = 0
INPUT_KEYBOARD = 1

# Mouse flags
MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_ABSOLUTE = 0x8000

# Keyboard flags
KEYEVENTF_EXTENDEDKEY = 0x0001
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_SCANCODE = 0x0008
KEYEVENTF_UNICODE = 0x0004

# Virtual Key Codes
VK_LWIN = 0x5B  # Left Windows Key

# Ctypes structures for Win32 SendInput
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

def move_mouse_relative(dx, dy):
    """Move mouse relative to current position using SendInput."""
    extra = ctypes.c_void_p(0)
    ii_ = INPUT_UNION()
    ii_.mi = MOUSEINPUT(dx, dy, 0, MOUSEEVENTF_MOVE, 0, extra)
    command = INPUT(INPUT_MOUSE, ii_)
    
    # SendInput takes (nInputs, pInputs, cbSize)
    result = ctypes.windll.user32.SendInput(1, ctypes.pointer(command), ctypes.sizeof(command))
    return result

def press_and_release_key(vk_code):
    """Press and release a virtual key code using SendInput."""
    extra = ctypes.c_void_p(0)
    
    # Key Down
    ii_down = INPUT_UNION()
    ii_down.ki = KEYBDINPUT(vk_code, 0, 0, 0, extra)
    cmd_down = INPUT(INPUT_KEYBOARD, ii_down)
    ctypes.windll.user32.SendInput(1, ctypes.pointer(cmd_down), ctypes.sizeof(cmd_down))
    
    time.sleep(0.1)
    
    # Key Up
    ii_up = INPUT_UNION()
    ii_up.ki = KEYBDINPUT(vk_code, 0, KEYEVENTF_KEYUP, 0, extra)
    cmd_up = INPUT(INPUT_KEYBOARD, ii_up)
    ctypes.windll.user32.SendInput(1, ctypes.pointer(cmd_up), ctypes.sizeof(cmd_up))

def main():
    print("==================================================")
    print("      bgrok SendInput Input Injection Spike       ")
    print("==================================================")
    print("This script will execute in 3 seconds.")
    print("Please keep your eyes on the cursor and the Windows menu.")
    print("Actions to take:")
    print("1. Relatives mouse movements (drawing a square).")
    print("2. Safe Win32 keypress (tapping Left Windows key twice).")
    print("==================================================")
    
    for i in range(3, 0, -1):
        print(f"Starting in {i}...")
        time.sleep(1)
        
    print("\nExecuting relative mouse movements...")
    # Move in a small square pattern
    for _ in range(5):
        move_mouse_relative(30, 0)
        time.sleep(0.05)
    for _ in range(5):
        move_mouse_relative(0, 30)
        time.sleep(0.05)
    for _ in range(5):
        move_mouse_relative(-30, 0)
        time.sleep(0.05)
    for _ in range(5):
        move_mouse_relative(0, -30)
        time.sleep(0.05)
        
    print("Mouse movements completed.")
    time.sleep(1)
    
    print("Tapping Left Windows key (Open Start Menu)...")
    press_and_release_key(VK_LWIN)
    
    time.sleep(1.5)
    
    print("Tapping Left Windows key again (Close Start Menu)...")
    press_and_release_key(VK_LWIN)
    
    print("\nFeasibility Spike executed successfully.")

if __name__ == "__main__":
    main()

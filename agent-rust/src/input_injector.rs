use std::os::raw::{c_int, c_long, c_uint, c_ulong, c_ushort, c_void};
use std::sync::Mutex;
use lazy_static::lazy_static;

// --- Win32 Structs ---

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MOUSEINPUT {
    pub dx: c_long,
    pub dy: c_long,
    pub mouse_data: c_ulong,
    pub dw_flags: c_ulong,
    pub time: c_ulong,
    pub dw_extra_info: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct KEYBDINPUT {
    pub w_vk: c_ushort,
    pub w_scan: c_ushort,
    pub dw_flags: c_ulong,
    pub time: c_ulong,
    pub dw_extra_info: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct HARDWAREINPUT {
    pub u_msg: c_ulong,
    pub w_param_l: c_ushort,
    pub w_param_h: c_ushort,
}

#[repr(C)]
#[derive(Copy, Clone)]
pub union INPUT_UNION {
    pub mi: MOUSEINPUT,
    pub ki: KEYBDINPUT,
    pub hi: HARDWAREINPUT,
}

#[repr(C)]
#[derive(Copy, Clone)]
pub struct INPUT {
    pub r#type: c_ulong,
    pub u: INPUT_UNION,
}

// --- Win32 FFI Signatures ---
extern "system" {
    fn SendInput(c_inputs: c_uint, p_inputs: *const INPUT, cb_size: c_int) -> c_uint;
    fn OpenDesktopW(lpszDesktop: *const u16, dwFlags: u32, fInherit: bool, dwDesiredAccess: u32) -> *mut c_void;
    fn CloseDesktop(hDesktop: *mut c_void) -> bool;
    fn GetThreadDesktop(dwThreadId: u32) -> *mut c_void;
    fn SetThreadDesktop(hDesktop: *mut c_void) -> bool;
    fn GetCurrentThreadId() -> u32;
    fn GetLastError() -> u32;
}

// Win32 constants
const INPUT_MOUSE: c_ulong = 0;
const INPUT_KEYBOARD: c_ulong = 1;

const MOUSEEVENTF_MOVE: c_ulong = 0x0001;
const MOUSEEVENTF_LEFTDOWN: c_ulong = 0x0002;
const MOUSEEVENTF_LEFTUP: c_ulong = 0x0004;
const MOUSEEVENTF_RIGHTDOWN: c_ulong = 0x0008;
const MOUSEEVENTF_RIGHTUP: c_ulong = 0x0010;
const MOUSEEVENTF_MIDDLEDOWN: c_ulong = 0x0020;
const MOUSEEVENTF_MIDDLEUP: c_ulong = 0x0040;
const MOUSEEVENTF_WHEEL: c_ulong = 0x0800;
const MOUSEEVENTF_HWHEEL: c_ulong = 0x1000;
const MOUSEEVENTF_ABSOLUTE: c_ulong = 0x8000;
const MOUSEEVENTF_VIRTUALDESK: c_ulong = 0x4000;

const KEYEVENTF_EXTENDEDKEY: c_ulong = 0x0001;
const KEYEVENTF_KEYUP: c_ulong = 0x0002;

lazy_static! {
    static ref INPUT_MUTEX: Mutex<()> = Mutex::new(());
    // Pre-open the Default desktop handle
    static ref DEFAULT_DESKTOP_HANDLE: Mutex<Option<usize>> = Mutex::new(None);
}

pub struct InputInjector;

impl InputInjector {
    pub fn new() -> Self {
        let mut handle_lock = DEFAULT_DESKTOP_HANDLE.lock().unwrap();
        if handle_lock.is_none() {
            // Open 'Default' desktop
            let desktop_name: Vec<u16> = "Default\0".encode_utf16().collect();
            // DESKTOP_ALL_ACCESS = 0x1FF
            unsafe {
                let h = OpenDesktopW(desktop_name.as_ptr(), 0, false, 0x1FF);
                if !h.is_null() {
                    *handle_lock = Some(h as usize);
                    println!("Tether: Opened 'Default' desktop handle successfully.");
                } else {
                    println!("Tether: Failed to open 'Default' desktop. GetLastError: {}", GetLastError());
                }
            }
        }
        InputInjector
    }

    fn send_input_on_desktop(&self, inp: &INPUT) -> bool {
        let _lock = INPUT_MUTEX.lock().unwrap();
        let handle_lock = DEFAULT_DESKTOP_HANDLE.lock().unwrap();
        
        let mut h_orig = std::ptr::null_mut();
        let mut switched = false;
        
        unsafe {
            if let Some(h_default) = *handle_lock {
                h_orig = GetThreadDesktop(GetCurrentThreadId());
                if !h_orig.is_null() {
                    switched = SetThreadDesktop(h_default as *mut c_void);
                }
            }
            
            let res = SendInput(1, inp as *const INPUT, std::mem::size_of::<INPUT>() as c_int);
            
            if switched {
                SetThreadDesktop(h_orig);
            }
            
            if res == 0 {
                let err = GetLastError();
                println!("Tether: SendInput returned 0, GetLastError={}", err);
                false
            } else {
                true
            }
        }
    }

    pub fn mouse_move_rel(&self, dx: i32, dy: i32) {
        let ii = INPUT_UNION {
            mi: MOUSEINPUT {
                dx: dx as c_long,
                dy: dy as c_long,
                mouse_data: 0,
                dw_flags: MOUSEEVENTF_MOVE,
                time: 0,
                dw_extra_info: 0,
            }
        };
        let inp = INPUT {
            r#type: INPUT_MOUSE,
            u: ii,
        };
        self.send_input_on_desktop(&inp);
    }

    pub fn mouse_move_abs(&self, x_norm: f64, y_norm: f64) {
        let x_win = (x_norm.max(0.0).min(1.0) * 65535.0) as i32;
        let y_win = (y_norm.max(0.0).min(1.0) * 65535.0) as i32;

        let ii = INPUT_UNION {
            mi: MOUSEINPUT {
                dx: x_win as c_long,
                dy: y_win as c_long,
                mouse_data: 0,
                dw_flags: MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK,
                time: 0,
                dw_extra_info: 0,
            }
        };
        let inp = INPUT {
            r#type: INPUT_MOUSE,
            u: ii,
        };
        self.send_input_on_desktop(&inp);
    }

    pub fn mouse_click(&self, button: &str, state: &str) {
        let flags = match (button, state) {
            ("left", "down") => MOUSEEVENTF_LEFTDOWN,
            ("left", "up") => MOUSEEVENTF_LEFTUP,
            ("right", "down") => MOUSEEVENTF_RIGHTDOWN,
            ("right", "up") => MOUSEEVENTF_RIGHTUP,
            ("middle", "down") => MOUSEEVENTF_MIDDLEDOWN,
            ("middle", "up") => MOUSEEVENTF_MIDDLEUP,
            _ => return,
        };

        let ii = INPUT_UNION {
            mi: MOUSEINPUT {
                dx: 0,
                dy: 0,
                mouse_data: 0,
                dw_flags: flags,
                time: 0,
                dw_extra_info: 0,
            }
        };
        let inp = INPUT {
            r#type: INPUT_MOUSE,
            u: ii,
        };
        self.send_input_on_desktop(&inp);
    }

    pub fn mouse_scroll(&self, dx: f64, dy: f64) {
        if dy != 0.0 {
            let amount = (dy * 120.0) as i32 as u32;
            let ii = INPUT_UNION {
                mi: MOUSEINPUT {
                    dx: 0,
                    dy: 0,
                    mouse_data: amount as c_ulong,  // Two's complement preserves sign
                    dw_flags: MOUSEEVENTF_WHEEL,
                    time: 0,
                    dw_extra_info: 0,
                }
            };
            let inp = INPUT {
                r#type: INPUT_MOUSE,
                u: ii,
            };
            self.send_input_on_desktop(&inp);
        }

        if dx != 0.0 {
            let amount = (dx * 120.0) as i32 as u32;
            let ii = INPUT_UNION {
                mi: MOUSEINPUT {
                    dx: 0,
                    dy: 0,
                    mouse_data: amount as c_ulong,
                    dw_flags: MOUSEEVENTF_HWHEEL,
                    time: 0,
                    dw_extra_info: 0,
                }
            };
            let inp = INPUT {
                r#type: INPUT_MOUSE,
                u: ii,
            };
            self.send_input_on_desktop(&inp);
        }
    }

    pub fn keyboard_key(&self, vk_code: u16, state: &str) {
        let mut flags = 0;
        if state == "up" {
            flags |= KEYEVENTF_KEYUP;
        }

        let extended_vks = [0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E];
        if extended_vks.contains(&vk_code) {
            flags |= KEYEVENTF_EXTENDEDKEY;
        }

        let ii = INPUT_UNION {
            ki: KEYBDINPUT {
                w_vk: vk_code,
                w_scan: 0,
                dw_flags: flags,
                time: 0,
                dw_extra_info: 0,
            }
        };
        let inp = INPUT {
            r#type: INPUT_KEYBOARD,
            u: ii,
        };
        self.send_input_on_desktop(&inp);
    }
}

// Reports the state of the caps lock LED on stdout, one line per change.
//
// This reads EV_LED events from the keyboards that have a caps lock LED. The
// sysfs LED under /sys/class/leds looks like an easier source, but the LED
// class never calls sysfs_notify, so poll(2) on it sleeps through every change
// and only a timer would notice.

use std::fs::File;
use std::io::{Read, Write};
use std::os::fd::AsRawFd;
use std::process::ExitCode;

const EV_LED: u16 = 0x11;
const LED_CAPSL: u16 = 0x01;
const POLLIN: i16 = 0x001;

// struct input_event on a 64 bit kernel: two timeval longs, then the event.
const EVENT_SIZE: usize = 24;

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

extern "C" {
    fn poll(fds: *mut PollFd, nfds: u64, timeout: i32) -> i32;
    fn ioctl(fd: i32, request: u64, ...) -> i32;
}

// _IOC(_IOC_READ, type, nr, size), per asm-generic/ioctl.h.
const fn ioc_read(kind: u64, nr: u64, size: u64) -> u64 {
    (2 << 30) | (size << 16) | (kind << 8) | nr
}

fn bit_set(bits: &[u8], bit: u16) -> bool {
    bits
        .get(bit as usize / 8)
        .is_some_and(|byte| byte & (1 << (bit % 8)) != 0)
}

/// Whether this device is a keyboard that owns a caps lock LED.
fn has_capslock_led(file: &File) -> bool {
    let mut bits = [0u8; 4];
    let request = ioc_read(b'E' as u64, 0x20 + EV_LED as u64, bits.len() as u64);
    if unsafe { ioctl(file.as_raw_fd(), request, bits.as_mut_ptr()) } < 0 {
        return false;
    }
    bit_set(&bits, LED_CAPSL)
}

fn led_state(file: &File) -> Option<bool> {
    let mut bits = [0u8; 4];
    let request = ioc_read(b'E' as u64, 0x19, bits.len() as u64);
    if unsafe { ioctl(file.as_raw_fd(), request, bits.as_mut_ptr()) } < 0 {
        return None;
    }
    Some(bit_set(&bits, LED_CAPSL))
}

fn keyboards() -> Vec<File> {
    let Ok(entries) = std::fs::read_dir("/dev/input") else {
        return Vec::new();
    };
    let mut paths: Vec<_> = entries
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("event"))
        })
        .collect();
    paths.sort();
    paths
        .into_iter()
        .filter_map(|path| File::open(path).ok())
        .filter(has_capslock_led)
        .collect()
}

fn main() -> ExitCode {
    let mut devices = keyboards();
    if devices.is_empty() {
        eprintln!("no input device with a caps lock LED");
        return ExitCode::FAILURE;
    }

    let mut stdout = std::io::stdout();
    // Any one of them reflects the state; they're kept in sync by the
    // compositor.
    let mut lit = devices.iter().find_map(led_state).unwrap_or(false);

    let mut report = |lit: bool, stdout: &mut std::io::Stdout| {
        writeln!(stdout, "{}", u8::from(lit)).and_then(|_| stdout.flush())
    };
    if report(lit, &mut stdout).is_err() {
        return ExitCode::SUCCESS;
    }

    let mut buffer = [0u8; EVENT_SIZE * 32];
    loop {
        let mut fds: Vec<PollFd> = devices
            .iter()
            .map(|device| PollFd {
                fd: device.as_raw_fd(),
                events: POLLIN,
                revents: 0,
            })
            .collect();
        if unsafe { poll(fds.as_mut_ptr(), fds.len() as u64, -1) } < 0 {
            eprintln!("poll failed");
            return ExitCode::FAILURE;
        }

        for (index, poll_fd) in fds.iter().enumerate() {
            if poll_fd.revents & POLLIN == 0 {
                continue;
            }
            let Ok(read) = devices[index].read(&mut buffer) else {
                continue;
            };
            for event in buffer[..read].chunks_exact(EVENT_SIZE) {
                let kind = u16::from_ne_bytes([event[16], event[17]]);
                let code = u16::from_ne_bytes([event[18], event[19]]);
                let value = i32::from_ne_bytes([event[20], event[21], event[22], event[23]]);
                if kind == EV_LED && code == LED_CAPSL && (value != 0) != lit {
                    lit = value != 0;
                    if report(lit, &mut stdout).is_err() {
                        return ExitCode::SUCCESS;
                    }
                }
            }
        }
    }
}

// Reports the state of the caps lock LED on stdout, one line per change.
//
// The LED can only be observed by polling: sysfs emits no inotify events for
// attribute changes, and sway's IPC doesn't report lock state. sysfs does
// support poll(2) with POLLPRI, but only once the file has been read to EOF,
// so the read below is what arms the next wakeup.

use std::fs;
use std::io::{Read, Seek, SeekFrom, Write};
use std::os::fd::AsRawFd;
use std::path::PathBuf;
use std::process::ExitCode;

const POLLPRI: i16 = 0x002;
const POLLERR: i16 = 0x008;

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

extern "C" {
    fn poll(fds: *mut PollFd, nfds: u64, timeout: i32) -> i32;
}

fn find_led() -> Option<PathBuf> {
    let mut found: Vec<PathBuf> = fs::read_dir("/sys/class/leds")
        .ok()?
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.ends_with("::capslock"))
        })
        .collect();
    // The input device number isn't stable across boots, so just take the
    // lowest-numbered one.
    found.sort();
    found.into_iter().next().map(|path| path.join("brightness"))
}

fn main() -> ExitCode {
    let path = match std::env::args().nth(1) {
        Some(arg) => PathBuf::from(arg),
        None => match find_led() {
            Some(path) => path,
            None => {
                eprintln!("no ::capslock LED under /sys/class/leds");
                return ExitCode::FAILURE;
            }
        },
    };

    let mut file = match fs::File::open(&path) {
        Ok(file) => file,
        Err(err) => {
            eprintln!("{}: {err}", path.display());
            return ExitCode::FAILURE;
        }
    };

    let mut stdout = std::io::stdout();
    let mut contents = String::new();
    loop {
        contents.clear();
        if let Err(err) = file
            .seek(SeekFrom::Start(0))
            .and_then(|_| file.read_to_string(&mut contents))
        {
            eprintln!("{}: {err}", path.display());
            return ExitCode::FAILURE;
        }

        let lit = contents.trim() != "0";
        // A closed stdout means the shell went away; that's not an error.
        if writeln!(stdout, "{}", u8::from(lit)).is_err() || stdout.flush().is_err() {
            return ExitCode::SUCCESS;
        }

        let mut fds = PollFd {
            fd: file.as_raw_fd(),
            events: POLLPRI | POLLERR,
            revents: 0,
        };
        if unsafe { poll(&mut fds, 1, -1) } < 0 {
            eprintln!("poll failed");
            return ExitCode::FAILURE;
        }
    }
}

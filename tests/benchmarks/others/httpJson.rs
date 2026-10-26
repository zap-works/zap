// httpJson: TechEmpower's plaintext and JSON tests in one run. An HTTP/1.1 server (std::net, a thread per
// connection) answers 16 clients on the loopback, each with its own connection kept alive: every client
// writes its n requests in pipelined batches of 16 (a plaintext request, then a JSON one, alternating) and
// reads the responses; each JSON response is serialized anew. Prints the requests the clients made and the
// server served, the response bytes read, and the sum of the bodies' bytes.
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;

const CLIENTS: usize = 16;
const DEPTH: i64 = 16;
const BUF: usize = 65536;

const HELLO: &str = "Hello, World!";
const PLAIN: &[u8] =
    b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nHello, World!";

// the bytes a connection read: [start, stop) are unread
struct Input {
    bytes: Vec<u8>,
    start: usize,
    stop: usize,
}

impl Input {
    fn new() -> Input {
        Input { bytes: vec![0; BUF], start: 0, stop: 0 }
    }

    fn window(&self) -> &[u8] {
        &self.bytes[self.start..self.stop]
    }

    // reads more; false when the peer closed
    fn fill(&mut self, stream: &mut TcpStream) -> bool {
        if self.start == self.stop {
            self.start = 0;
            self.stop = 0;
        } else if self.stop == self.bytes.len() {
            self.bytes.copy_within(self.start..self.stop, 0);
            self.stop -= self.start;
            self.start = 0;
        }
        match stream.read(&mut self.bytes[self.stop..]) {
            Ok(n) if n > 0 => {
                self.stop += n;
                true
            }
            _ => false,
        }
    }
}

// the index after the blank line ending the head in text
fn head_end(text: &[u8]) -> Option<usize> {
    let mut i = 0;
    while i + 3 < text.len() {
        let c = text[i + 3];
        if c != b'\n' && c != b'\r' {
            i += 4;
        } else if c == b'\n' && text[i + 2] == b'\r' && text[i + 1] == b'\n' && text[i] == b'\r' {
            return Some(i + 4);
        } else {
            i += 1;
        }
    }
    None
}

fn parse_number(text: &[u8]) -> i64 {
    let mut v = 0i64;
    for &b in text {
        if !b.is_ascii_digit() {
            break;
        }
        v = v * 10 + (b - b'0') as i64;
    }
    v
}

fn content_length(head: &[u8]) -> usize {
    const KEY: &[u8] = b"\nContent-Length: ";
    match head.windows(KEY.len()).position(|w| w == KEY) {
        Some(at) => parse_number(&head[at + KEY.len()..]) as usize,
        None => 0,
    }
}

fn serve(mut stream: TcpStream) -> i64 {
    let mut input = Input::new();
    let mut out: Vec<u8> = Vec::with_capacity(BUF * 4);
    let mut served = 0;
    loop {
        while let Some(end) = head_end(input.window()) {
            let window = input.window();
            if window.starts_with(b"GET /plaintext ") {
                out.extend_from_slice(PLAIN);
            } else {
                let id = parse_number(&window[13..]); // GET /json?id=
                let body = format!("{{\"id\":{},\"message\":\"{}\",\"square\":{}}}", id, HELLO, id * id);
                write!(
                    out,
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                    body.len(),
                    body
                )
                .unwrap();
            }
            input.start += end;
            served += 1;
            if out.len() > BUF * 4 - 512 {
                let _ = stream.write_all(&out);
                out.clear();
            }
        }
        if !out.is_empty() {
            if stream.write_all(&out).is_err() {
                break;
            }
            out.clear();
        }
        if !input.fill(&mut stream) {
            break;
        }
    }
    served
}

#[derive(Default)]
struct Totals {
    responses: i64,
    bytes: i64,
    checksum: i64,
}

fn client(port: u16, c: i64, n: i64) -> Totals {
    let mut totals = Totals::default();
    let mut stream = match TcpStream::connect(("127.0.0.1", port)) {
        Ok(s) => s,
        Err(_) => return totals,
    };
    let mut input = Input::new();
    let mut req: Vec<u8> = Vec::with_capacity(DEPTH as usize * 80);
    let mut j = 0;
    while j < n {
        let batch = (n - j).min(DEPTH);
        req.clear();
        for k in j..j + batch {
            if k % 2 == 0 {
                req.extend_from_slice(b"GET /plaintext HTTP/1.1\r\nHost: localhost\r\n\r\n");
            } else {
                write!(req, "GET /json?id={} HTTP/1.1\r\nHost: localhost\r\n\r\n", c * n + k).unwrap();
            }
        }
        if stream.write_all(&req).is_err() {
            return totals;
        }
        let mut got = 0;
        while got < batch {
            let window = input.window();
            if let Some(end) = head_end(window) {
                let len = content_length(&window[..end]);
                if window.len() >= end + len {
                    totals.checksum += window[end..end + len].iter().map(|&b| b as i64).sum::<i64>();
                    totals.bytes += (end + len) as i64;
                    totals.responses += 1;
                    input.start += end + len;
                    got += 1;
                    continue;
                }
            }
            if !input.fill(&mut stream) {
                return totals;
            }
        }
        j += batch;
    }
    totals
}

fn main() {
    let n: i64 = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(64);
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let clients: Vec<_> = (0..CLIENTS as i64).map(|c| thread::spawn(move || client(port, c, n))).collect();
    let servers: Vec<_> = (0..CLIENTS)
        .map(|_| {
            let (stream, _) = listener.accept().unwrap();
            thread::spawn(move || serve(stream))
        })
        .collect();
    let mut all = Totals::default();
    for c in clients {
        let t = c.join().unwrap();
        all.responses += t.responses;
        all.bytes += t.bytes;
        all.checksum += t.checksum;
    }
    let served: i64 = servers.into_iter().map(|s| s.join().unwrap()).sum();
    println!("requests {}\nserved {}\nbytes {}\nchecksum {}", all.responses, served, all.bytes, all.checksum);
}

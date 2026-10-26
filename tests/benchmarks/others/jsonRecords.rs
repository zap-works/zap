// jsonRecords: n generated records written as {"records": [...]} and parsed back; prints the
// JSON's size and byte sum, sums over the parsed records and whether they equal the originals.
use std::fmt::Write as _;

#[derive(PartialEq, Default)]
struct Record {
    id: i64,
    name: String,
    email: String,
    score: i64,
    active: bool,
    tags: Vec<String>,
}

const TAG_NAMES: [&str; 6] = ["red", "green", "blue", "admin", "guest", "beta"];

struct Generator(u64);

impl Generator {
    // the next number, 31 bits
    fn next(&mut self) -> i64 {
        self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        (self.0 >> 33) as i64
    }
}

fn generate(n: i64) -> Vec<Record> {
    let mut random = Generator(7);
    (0..n)
        .map(|i| {
            let letters = 5 + random.next() % 8;
            let word: String = (0..letters).map(|_| (b'a' + (random.next() % 26) as u8) as char).collect();
            let score = random.next() % 100000 - 50000;
            let active = random.next() % 3 != 0;
            let tags = (0..random.next() % 4).map(|_| TAG_NAMES[(random.next() % 6) as usize].to_string()).collect();
            let name = if i % 10 == 0 { format!("{word} \"jr\"") } else { word.clone() };
            let email = format!("{word}{i}@mail.test");
            Record { id: i, name, email, score, active, tags }
        })
        .collect()
}

// ---------- writing ----------

// s as a JSON string: " \ and the control characters escaped
fn write_string(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => write!(out, "\\u{:04x}", c as u32).unwrap(),
            c => out.push(c),
        }
    }
    out.push('"');
}

fn write_records(records: &[Record]) -> String {
    let mut out = String::from("{\"records\":[");
    for (i, r) in records.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        write!(out, "{{\"id\":{},\"name\":", r.id).unwrap();
        write_string(&mut out, &r.name);
        out.push_str(",\"email\":");
        write_string(&mut out, &r.email);
        write!(out, ",\"score\":{},\"active\":{},\"tags\":[", r.score, r.active).unwrap();
        for (t, tag) in r.tags.iter().enumerate() {
            if t > 0 {
                out.push(',');
            }
            write_string(&mut out, tag);
        }
        out.push_str("]}");
    }
    out.push_str("]}");
    out
}

// ---------- reading ----------

struct Parser<'a> {
    text: &'a [u8],
    at: usize,
}

type Parsed<T> = Result<T, ()>;

impl<'a> Parser<'a> {
    fn space(&mut self) {
        while self.at < self.text.len() && matches!(self.text[self.at], b' ' | b'\n' | b'\r' | b'\t') {
            self.at += 1;
        }
    }

    // the byte c next (after white space): consumed when it is
    fn next_is(&mut self, c: u8) -> bool {
        self.space();
        if self.text.get(self.at) == Some(&c) {
            self.at += 1;
            return true;
        }
        false
    }

    fn expect(&mut self, c: u8) -> Parsed<()> {
        if self.next_is(c) { Ok(()) } else { Err(()) }
    }

    // a list of values between open and close, separated by commas, each read by item
    fn list(&mut self, open: u8, close: u8, mut item: impl FnMut(&mut Self) -> Parsed<()>) -> Parsed<()> {
        self.expect(open)?;
        if self.next_is(close) {
            return Ok(());
        }
        loop {
            item(self)?;
            if !self.next_is(b',') {
                return self.expect(close);
            }
        }
    }

    fn string(&mut self) -> Parsed<String> {
        self.expect(b'"')?;
        let start = self.at;
        while self.at < self.text.len() && self.text[self.at] != b'"' && self.text[self.at] != b'\\' {
            self.at += 1;
        }
        let mut bytes = self.text[start..self.at].to_vec();
        while self.at < self.text.len() && self.text[self.at] != b'"' {
            let mut c = self.text[self.at];
            self.at += 1;
            if c == b'\\' && self.at < self.text.len() {
                let e = self.text[self.at];
                self.at += 1;
                c = match e {
                    b'n' => b'\n',
                    b'r' => b'\r',
                    b't' => b'\t',
                    b'b' => 8,
                    b'f' => 12,
                    b'u' => {
                        let hex = std::str::from_utf8(self.text.get(self.at..self.at + 4).ok_or(())?).map_err(|_| ())?;
                        self.at += 4;
                        u8::from_str_radix(hex, 16).map_err(|_| ())?
                    }
                    e => e,
                };
            }
            bytes.push(c);
        }
        self.expect(b'"')?;
        String::from_utf8(bytes).map_err(|_| ())
    }

    fn int(&mut self) -> Parsed<i64> {
        self.space();
        let negative = self.text.get(self.at) == Some(&b'-');
        if negative {
            self.at += 1;
        }
        let start = self.at;
        let mut v: i64 = 0;
        while self.at < self.text.len() && self.text[self.at].is_ascii_digit() {
            v = v * 10 + (self.text[self.at] - b'0') as i64;
            self.at += 1;
        }
        if self.at == start {
            return Err(());
        }
        Ok(if negative { -v } else { v })
    }

    fn literal(&mut self, word: &[u8]) -> bool {
        self.space();
        if self.text[self.at..].starts_with(word) {
            self.at += word.len();
            return true;
        }
        false
    }

    fn bool(&mut self) -> Parsed<bool> {
        if self.literal(b"true") {
            Ok(true)
        } else if self.literal(b"false") {
            Ok(false)
        } else {
            Err(())
        }
    }

    fn skip(&mut self) -> Parsed<()> {
        self.space();
        match self.text.get(self.at) {
            Some(b'"') => self.string().map(|_| ()),
            Some(b'[') => self.list(b'[', b']', |p| p.skip()),
            Some(b'{') => self.list(b'{', b'}', |p| {
                p.string()?;
                p.expect(b':')?;
                p.skip()
            }),
            Some(_) if self.literal(b"true") || self.literal(b"false") || self.literal(b"null") => Ok(()),
            Some(_) => {
                while self.at < self.text.len() && b"+-.0123456789eE".contains(&self.text[self.at]) {
                    self.at += 1;
                }
                Ok(())
            }
            None => Err(()),
        }
    }

    fn record(&mut self) -> Parsed<Record> {
        let mut r = Record::default();
        let mut seen = 0;
        self.list(b'{', b'}', |p| {
            let key = p.string()?;
            p.expect(b':')?;
            match key.as_str() {
                "id" => r.id = p.int()?,
                "name" => r.name = p.string()?,
                "email" => r.email = p.string()?,
                "score" => r.score = p.int()?,
                "active" => r.active = p.bool()?,
                "tags" => {
                    r.tags.clear();
                    p.list(b'[', b']', |p| {
                        r.tags.push(p.string()?);
                        Ok(())
                    })?
                }
                _ => return p.skip(),
            }
            seen |= match key.as_str() {
                "id" => 1,
                "name" => 2,
                "email" => 4,
                "score" => 8,
                "active" => 16,
                _ => 32,
            };
            Ok(())
        })?;
        if seen == 63 { Ok(r) } else { Err(()) }
    }

    fn records(&mut self) -> Parsed<Vec<Record>> {
        let mut records = Vec::new();
        self.list(b'{', b'}', |p| {
            if p.string()? == "records" {
                p.expect(b':')?;
                p.list(b'[', b']', |p| {
                    records.push(p.record()?);
                    Ok(())
                })
            } else {
                p.expect(b':')?;
                p.skip()
            }
        })?;
        self.space();
        if self.at == self.text.len() { Ok(records) } else { Err(()) }
    }
}

fn main() {
    let n: i64 = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(100);
    let records = generate(n);
    let text = write_records(&records);
    let sum: u64 = text.bytes().map(|c| c as u64).sum();
    println!("json {} bytes, checksum {}", text.len(), sum);
    let back = Parser { text: text.as_bytes(), at: 0 }.records().unwrap_or_default();
    let scores: i64 = back.iter().map(|r| r.score).sum();
    let active = back.iter().filter(|r| r.active).count();
    let tags: usize = back.iter().map(|r| r.tags.len()).sum();
    let same = if back == records { "same" } else { "DIFFERENT" };
    println!("read {} records: scores {}, active {}, tags {}, {}", back.len(), scores, active, tags, same);
}

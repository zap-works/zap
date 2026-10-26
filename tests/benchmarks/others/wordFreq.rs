// wordFreq: n generated words counted in a hash map keyed by the words; prints the distinct
// count and the ten most frequent.
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::io::Write;

#[derive(Default)]
struct Fnv(u64);

impl Hasher for Fnv {
    fn finish(&self) -> u64 {
        self.0
    }

    fn write(&mut self, bytes: &[u8]) {
        let mut h = if self.0 == 0 { 14695981039346656037 } else { self.0 };
        for &b in bytes {
            h = (h ^ b as u64).wrapping_mul(1099511628211);
        }
        self.0 = h;
    }
}

fn generate(n: u64) -> Vec<u8> {
    let mut text = Vec::new();
    let mut state: u64 = 1;
    for i in 0..n {
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        let mut k = (state >> 44) % ((state >> 24 & 1048575) + 1);
        loop {
            text.push(b'a' + (k % 26) as u8);
            k /= 26;
            if k == 0 {
                break;
            }
        }
        text.push(if i % 20 == 19 || i == n - 1 { b'\n' } else { b' ' });
    }
    text
}

fn main() {
    let n: u64 = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(1000);
    let text = generate(n);
    let mut counts: HashMap<&[u8], u32, BuildHasherDefault<Fnv>> = HashMap::default();
    for line in text.split(|&c| c == b'\n').filter(|l| !l.is_empty()) {
        for word in line.split(|&c| c == b' ') {
            *counts.entry(word).or_insert(0) += 1;
        }
    }
    let mut entries: Vec<(&[u8], u32)> = counts.into_iter().collect();
    entries.sort_unstable_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    let mut out = std::io::stdout().lock();
    writeln!(out, "{} words, {} distinct", n, entries.len()).unwrap();
    for (word, count) in entries.iter().take(10) {
        writeln!(out, "{:>8} {}", count, std::str::from_utf8(word).unwrap()).unwrap();
    }
}

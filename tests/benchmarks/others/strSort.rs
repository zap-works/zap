// strSort: n generated strings of 1 to 40 letters, each from an alphabet of 2 to 26 letters (long
// shared prefixes among the small ones) sorted by bytes; prints how many are distinct, a hash of the sorted sequence and the
// first and last.
struct Generator(u64);

impl Generator {
    // the next number, 31 bits
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        self.0 >> 33
    }
}

fn main() {
    let n: usize = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(1000);
    let mut random = Generator(1);
    let mut words: Vec<String> = (0..n)
        .map(|_| {
            let len = 1 + random.next() % 40;
            let letters = 2 + random.next() % 25;
            (0..len).map(|_| (b'a' + (random.next() % letters) as u8) as char).collect()
        })
        .collect();
    words.sort_unstable();
    let mut distinct = 0;
    let mut hash: u64 = 14695981039346656037;
    for (i, word) in words.iter().enumerate() {
        if i == 0 || *word != words[i - 1] {
            distinct += 1;
        }
        for &c in word.as_bytes().iter().chain(b"\n") {
            hash = (hash ^ c as u64).wrapping_mul(1099511628211);
        }
    }
    println!("{} strings, {} distinct, hash {:x}\n{}\n{}", n, distinct, hash, words[0], words[n - 1]);
}

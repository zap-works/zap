// regex-redux for the Zap benchmarks game, in Rust over the regex crate (bytes, no Unicode: the
// text is ASCII): the headers and newlines taken out by a regular expression, the nine variants
// counted one thread each beside the five substitutions made in turn.
use regex::bytes::{Regex, RegexBuilder};
use std::io::{Read, Write};

const VARIANTS: [&str; 9] = [
    "agggtaaa|tttaccct",
    "[cgt]gggtaaa|tttaccc[acg]",
    "a[act]ggtaaa|tttacc[agt]t",
    "ag[act]gtaaa|tttac[agt]ct",
    "agg[act]taaa|ttta[agt]cct",
    "aggg[acg]aaa|ttt[cgt]ccct",
    "agggt[cgt]aa|tt[acg]accct",
    "agggta[cgt]a|t[acg]taccct",
    "agggtaa[cgt]|[acg]ttaccct",
];

const SUBSTITUTIONS: [(&str, &str); 5] = [
    ("tHa[Nt]", "<4>"),
    ("aND|caN|Ha[DS]|WaS", "<3>"),
    ("a[NSt]|BY", "<2>"),
    ("<[^>]*>", "|"),
    ("\\|[^|][^|]*\\|", "-"),
];

fn compiled(pattern: &str) -> Regex {
    RegexBuilder::new(pattern).unicode(false).build().unwrap()
}

fn main() {
    let mut original = Vec::new();
    std::io::stdin().lock().read_to_end(&mut original).unwrap();
    let sequence = compiled(">.*\n|\n").replace_all(&original, &b""[..]).into_owned();
    let original_length = original.len();
    drop(original);

    // the substitutions go on in this thread while one thread for each variant counts it
    let (counts, text_length): (Vec<usize>, usize) = std::thread::scope(|scope| {
        let workers: Vec<_> = VARIANTS
            .iter()
            .map(|pattern| {
                let sequence = &sequence;
                scope.spawn(move || compiled(pattern).find_iter(sequence).count())
            })
            .collect();
        let (pattern, by) = SUBSTITUTIONS[0];
        let mut text = compiled(pattern).replace_all(&sequence, by.as_bytes()).into_owned();
        for (pattern, by) in &SUBSTITUTIONS[1..] {
            text = compiled(pattern).replace_all(&text, by.as_bytes()).into_owned();
        }
        (workers.into_iter().map(|w| w.join().unwrap()).collect(), text.len())
    });
    let mut out = String::new();
    for (pattern, count) in VARIANTS.iter().zip(&counts) {
        out.push_str(&format!("{} {}\n", pattern, count));
    }
    out.push_str(&format!("\n{}\n{}\n{}\n", original_length, sequence.len(), text_length));
    std::io::stdout().write_all(out.as_bytes()).unwrap();
}

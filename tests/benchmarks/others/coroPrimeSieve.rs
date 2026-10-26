// coroPrimeSieve: the first n primes by a chain of threads joined by bounded channels
// (the programming-language-benchmarks suite's coro-prime-sieve): a generator sends 2, 3, 4...
// and each thread holds consecutive filters, a prime and its multiples out of what comes in;
// as many threads as processors less two, so a number meets the primes in order as in a thread per prime.
use std::io::Write;
use std::sync::mpsc::{channel, sync_channel, Receiver, Sender, SyncSender};
use std::thread::{self, JoinHandle};

const CAPACITY: usize = 64;

fn generate(out: SyncSender<i32>) {
    let mut n = 2;
    while out.send(n).is_ok() {
        n += 1;
    }
}

fn filters(input: Receiver<i32>, out: SyncSender<i32>, found: Sender<i32>, room: usize, last: bool) {
    let mut primes: Vec<i32> = Vec::with_capacity(room);
    for v in input {
        if primes.iter().any(|p| v % p == 0) {
            continue;
        }
        if primes.len() < room {
            primes.push(v);
            let _ = found.send(v);
            if last && primes.len() == room {
                break;
            }
        } else if out.send(v).is_err() {
            break;
        }
    }
}

fn main() {
    let n: usize = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(10);
    let cpus = thread::available_parallelism().map(|c| c.get()).unwrap_or(1);
    let tasks = cpus.saturating_sub(2).max(1).min(n);
    let share = (n + tasks - 1) / tasks;
    let tasks = (n + share - 1) / share;
    let (found_tx, found) = channel();
    let (tx, mut rx) = sync_channel(CAPACITY);
    let mut handles: Vec<JoinHandle<()>> = vec![thread::spawn(move || generate(tx))];
    for k in 0..tasks {
        let (tx, next) = sync_channel(CAPACITY);
        let input = std::mem::replace(&mut rx, next);
        let found_tx = found_tx.clone();
        let room = share.min(n - k * share);
        let last = k == tasks - 1;
        handles.push(thread::spawn(move || filters(input, tx, found_tx, room, last)));
    }
    drop(rx);
    drop(found_tx);
    let stdout = std::io::stdout();
    let mut o = stdout.lock();
    for _ in 0..n {
        writeln!(o, "{}", found.recv().unwrap()).unwrap();
    }
    for h in handles {
        h.join().unwrap();
    }
}

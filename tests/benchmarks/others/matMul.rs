// matMul: the product of two n by n f64 matrices, loops in i, k, j order so each element sums in
// k order and every language prints the same digits.
fn matrix(n: usize) -> Vec<f64> {
    let scale = 1.0 / n as f64 / n as f64;
    let mut m = vec![0.0; n * n];
    for i in 0..n {
        for j in 0..n {
            m[i * n + j] = scale * (i as f64 - j as f64) * (i + j) as f64;
        }
    }
    m
}

fn product(a: &[f64], b: &[f64], n: usize) -> Vec<f64> {
    let mut c = vec![0.0; n * n];
    for (ci, ai) in c.chunks_exact_mut(n).zip(a.chunks_exact(n)) {
        for (&aik, bk) in ai.iter().zip(b.chunks_exact(n)) {
            for (cij, &bkj) in ci.iter_mut().zip(bk) {
                *cij += aik * bkj;
            }
        }
    }
    c
}

fn main() {
    let n: usize = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(30);
    let a = matrix(n);
    let b = matrix(n);
    let c = product(&a, &b, n);
    let trace: f64 = (0..n).map(|i| c[i * n + i]).sum();
    println!("{:.9}", c[n / 2 * n + n / 2]);
    println!("{:.9}", trace);
}

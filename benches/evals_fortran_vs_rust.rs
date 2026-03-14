//! Benchmark: Fortran vs Rust for evals_from_points (EqPolynomial)
//!
//! Run:
//!   export LD_LIBRARY_PATH=fortran/build:$LD_LIBRARY_PATH
//!   cargo bench --bench evals_fortran_vs_rust --features fortran
//!
//! What we measure: evals_from_points(r) where r has N variables → 2^N evaluations
//! This is the butterfly computation inside Nova's Sumcheck protocol.

use criterion::{criterion_group, criterion_main, BenchmarkId, Criterion};
use ff::{Field, PrimeField};
use nova_snark::{provider::Bn256EngineKZG, traits::Engine};
use rand_core::OsRng;
use std::hint::black_box;
use std::time::Duration;

type E = Bn256EngineKZG;
type F = <E as Engine>::Scalar;

/// Pure-Rust butterfly for EqPolynomial — mirrors Nova's EqPolynomial::evals_from_points.
/// Inlined here because spartan::polys is pub(crate).
fn rust_evals_from_points<Scalar: PrimeField>(r: &[Scalar]) -> Vec<Scalar> {
  let ell = r.len();
  let n = 1 << ell;
  let mut evals = vec![Scalar::ZERO; n];
  evals[0] = Scalar::ONE;

  let mut size = 1usize;
  for r_i in r.iter().rev() {
    for j in (0..size).rev() {
      let tmp = evals[j] * r_i;
      evals[size + j] = tmp;
      evals[j] -= tmp;
    }
    size *= 2;
  }
  evals
}

fn bench_evals_from_points(c: &mut Criterion) {
  // n = number of variables, output = 2^n field elements
  // n=10 →   1K  (fast baseline)
  // n=16 →  64K  (typical Nova circuit)
  // n=20 →   1M  (where parallelism matters)
  let ns: &[usize] = &[10, 14, 16, 18, 20];

  let mut group = c.benchmark_group("evals_from_points");
  group.warm_up_time(Duration::from_millis(1000));
  group.sample_size(20);

  for &n in ns {
    let r: Vec<F> = (0..n).map(|_| F::random(OsRng)).collect();

    // --- Rust butterfly (reference) ---
    group.bench_with_input(BenchmarkId::new("rust", n), &r, |b, r| {
      b.iter(|| black_box(rust_evals_from_points(r)))
    });

    // --- Fortran + DO CONCURRENT ---
    #[cfg(feature = "fortran")]
    group.bench_with_input(BenchmarkId::new("fortran", n), &r, |b, r| {
      b.iter(|| {
        black_box(
          nova_snark::fortran::evals_from_points_fortran(r)
            .expect("Fortran evals_from_points failed"),
        )
      })
    });
  }

  group.finish();
}

criterion_group!(benches, bench_evals_from_points);
criterion_main!(benches);

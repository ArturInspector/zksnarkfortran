//! Benchmarking polynomial operations for Fortran acceleration research
//! This benchmark establishes baseline performance for Rust implementations
//! before integrating Fortran-accelerated versions.
//!
//! Target operations:
//! - Multilinear polynomial evaluations
//! - Univariate polynomial operations
//! - Equality polynomial evaluations
//! - Gaussian elimination for interpolation

use core::time::Duration;
use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion};
use ff::Field;
use nova_snark::{
  provider::Bn256EngineKZG,
  spartan::polys::{eq::EqPolynomial, multilinear::MultilinearPolynomial, univariate::UniPoly},
  traits::Engine,
};
use rand::Rng;
use rayon::prelude::*;

type E = Bn256EngineKZG;
type Scalar = <E as Engine>::Scalar;

criterion_group! {
  name = polynomial_ops;
  config = Criterion::default()
    .warm_up_time(Duration::from_millis(3000))
    .sample_size(10)
    .measurement_time(Duration::from_secs(10));
  targets = bench_multilinear, bench_univariate, bench_eq_polynomial
}

criterion_main!(polynomial_ops);

/// Generate random scalar values
fn random_scalars(n: usize) -> Vec<Scalar> {
  let mut rng = rand::thread_rng();
  (0..n)
    .into_par_iter()
    .map(|_| Scalar::random(&mut rng))
    .collect()
}

/// Generate random point for evaluation (num_vars scalars)
fn random_point(num_vars: usize) -> Vec<Scalar> {
  random_scalars(num_vars)
}

/// Benchmarks for multilinear polynomial operations
fn bench_multilinear(c: &mut Criterion) {
  let mut group = c.benchmark_group("multilinear");

  // Test sizes: 2^10, 2^12, 2^14, 2^16, 2^18, 2^20
  for num_vars in [10, 12, 14, 16, 18, 20] {
    let size = 1 << num_vars;
    let Z = random_scalars(size);
    let poly = MultilinearPolynomial::new(Z.clone());
    let r = random_point(num_vars);

    // Benchmark: MultilinearPolynomial::evaluate()
    group.bench_with_input(
      BenchmarkId::new("evaluate", num_vars),
      &(poly.clone(), r.clone()),
      |b, (poly, r)| {
        b.iter(|| black_box(poly.evaluate(r)))
      },
    );

    // Benchmark: MultilinearPolynomial::bind_poly_var_top()
    group.bench_with_input(
      BenchmarkId::new("bind_poly_var_top", num_vars),
      &mut poly.clone(),
      |b, poly| {
        let r = Scalar::random(&mut rand::thread_rng());
        b.iter(|| {
          let mut p = poly.clone();
          p.bind_poly_var_top(&r);
          black_box(p)
        })
      },
    );

    // Benchmark: MultilinearPolynomial::evaluate_with()
    group.bench_with_input(
      BenchmarkId::new("evaluate_with", num_vars),
      &(Z.clone(), r.clone()),
      |b, (Z, r)| {
        b.iter(|| black_box(MultilinearPolynomial::evaluate_with(Z, r)))
      },
    );
  }

  group.finish();
}

/// Benchmarks for univariate polynomial operations
fn bench_univariate(c: &mut Criterion) {
  let mut group = c.benchmark_group("univariate");

  // Test degrees: 10, 50, 100, 500, 1000, 5000
  for degree in [10, 50, 100, 500, 1000, 5000] {
    let coeffs = random_scalars(degree + 1);
    let poly = UniPoly { coeffs };
    let r = Scalar::random(&mut rand::thread_rng());

    // Benchmark: UniPoly::evaluate()
    group.bench_with_input(
      BenchmarkId::new("evaluate", degree),
      &(poly.clone(), r),
      |b, (poly, r)| {
        b.iter(|| black_box(poly.evaluate(r)))
      },
    );

    // Benchmark: UniPoly::eval_at_one() (uses parallel sum)
    group.bench_with_input(
      BenchmarkId::new("eval_at_one", degree),
      &poly.clone(),
      |b, poly| {
        b.iter(|| black_box(poly.eval_at_one()))
      },
    );
  }

  // Benchmark: from_evals (interpolation via gaussian elimination)
  // NOTE: Requires "experimental" feature, commented out for now
  // Smaller sizes due to O(n^3) complexity
  // for size in [10, 50, 100, 500] {
  //   let evals = random_scalars(size);
  //   group.bench_with_input(
  //     BenchmarkId::new("from_evals", size),
  //     &evals,
  //     |b, evals| {
  //       b.iter(|| black_box(UniPoly::from_evals(evals)))
  //     },
  //   );
  // }

  group.finish();
}

/// Benchmarks for equality polynomial operations
fn bench_eq_polynomial(c: &mut Criterion) {
  let mut group = c.benchmark_group("eq_polynomial");

  // Test sizes: 10, 12, 14, 16, 18, 20 variables
  for num_vars in [10, 12, 14, 16, 18, 20] {
    let r = random_point(num_vars);
    let rx = random_point(num_vars);
    let poly = EqPolynomial::new(r.clone());

    // Benchmark: EqPolynomial::evals_from_points()
    group.bench_with_input(
      BenchmarkId::new("evals_from_points", num_vars),
      &r.clone(),
      |b, r| {
        b.iter(|| black_box(EqPolynomial::evals_from_points(r)))
      },
    );

    // Benchmark: EqPolynomial::evaluate()
    group.bench_with_input(
      BenchmarkId::new("evaluate", num_vars),
      &(poly.clone(), rx.clone()),
      |b, (poly, rx)| {
        b.iter(|| black_box(poly.evaluate(rx)))
      },
    );
  }

  group.finish();
}

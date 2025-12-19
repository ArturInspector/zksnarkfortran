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
  spartan::{EqPolynomial, MultilinearPolynomial, UniPoly},
  traits::Engine,
};

type E = Bn256EngineKZG;
type Scalar = <E as Engine>::Scalar;

criterion_group! {
  name = polynomial_ops;
  config = Criterion::default()
    .warm_up_time(Duration::from_millis(3000))
    .sample_size(200)  // increased for statistical confidence (was 10)
    .measurement_time(Duration::from_secs(30));  // increased for better accuracy
  targets = bench_multilinear, bench_univariate, bench_eq_polynomial
}

criterion_main!(polynomial_ops);

/// Generate random scalar values
fn random_scalars(n: usize) -> Vec<Scalar> {
  use rand::thread_rng;
  (0..n)
    .map(|_| {
      let mut rng = thread_rng();
      Scalar::random(&mut rng)
    })
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
    let z = random_scalars(size);
    let poly = MultilinearPolynomial::new(z.clone());
    let r = random_point(num_vars);

    // Benchmark: MultilinearPolynomial::evaluate()
    let poly_clone = poly.clone();
    let r_clone = r.clone();
    group.bench_with_input(
      BenchmarkId::new("evaluate", num_vars),
      &(poly_clone, r_clone),
      |b, input: &(MultilinearPolynomial<Scalar>, Vec<Scalar>)| {
        let (poly, r) = input;
        b.iter(|| black_box(poly.evaluate(r)))
      },
    );

    // Benchmark: MultilinearPolynomial::bind_poly_var_top()
    let poly_clone = poly.clone();
    let r_bind = Scalar::random(&mut rand::thread_rng());
    group.bench_with_input(
      BenchmarkId::new("bind_poly_var_top", num_vars),
      &poly_clone,
      |b, poly: &MultilinearPolynomial<Scalar>| {
        b.iter(|| {
          let mut p = poly.clone();
          p.bind_poly_var_top(&r_bind);
          black_box(p)
        })
      },
    );

    // Benchmark: MultilinearPolynomial::evaluate_with()
    let z_clone = z.clone();
    let r_clone2 = r.clone();
    group.bench_with_input(
      BenchmarkId::new("evaluate_with", num_vars),
      &(z_clone, r_clone2),
      |b, input: &(Vec<Scalar>, Vec<Scalar>)| {
        let (z, r) = input;
        b.iter(|| black_box(MultilinearPolynomial::evaluate_with(z, r)))
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
    let poly = UniPoly::new(coeffs);
    let r = Scalar::random(&mut rand::thread_rng());

    // Benchmark: UniPoly::evaluate()
    let poly_clone = poly.clone();
    let r_clone = r;
    group.bench_with_input(
      BenchmarkId::new("evaluate", degree),
      &(poly_clone, r_clone),
      |b, input: &(UniPoly<Scalar>, Scalar)| {
        let (poly, r) = input;
        b.iter(|| black_box(poly.evaluate(r)))
      },
    );

    // Benchmark: UniPoly::eval_at_one() (uses parallel sum)
    let poly_clone2 = poly.clone();
    group.bench_with_input(
      BenchmarkId::new("eval_at_one", degree),
      &poly_clone2,
      |b, poly: &UniPoly<Scalar>| {
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
    let r_clone = r.clone();
    group.bench_with_input(
      BenchmarkId::new("evals_from_points", num_vars),
      &r_clone,
      |b, r: &Vec<Scalar>| {
        b.iter(|| black_box(EqPolynomial::evals_from_points(r)))
      },
    );

    // Benchmark: EqPolynomial::evaluate()
    let poly_clone = poly.clone();
    let rx_clone = rx.clone();
    group.bench_with_input(
      BenchmarkId::new("evaluate", num_vars),
      &(poly_clone, rx_clone),
      |b, input: &(EqPolynomial<Scalar>, Vec<Scalar>)| {
        let (poly, rx) = input;
        b.iter(|| black_box(poly.evaluate(rx)))
      },
    );
  }

  group.finish();
}

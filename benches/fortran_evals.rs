//! Benchmark comparing Rust and Fortran implementations of evals_from_points
//! 
//! To run:
//!   export LD_LIBRARY_PATH=fortran/build:$LD_LIBRARY_PATH
//!   cargo bench --features fortran --bench fortran_evals

#![allow(non_snake_case)]
use criterion::*;
use ff::PrimeField;
use nova_snark::{
    fortran::evals_from_points_fortran,
    provider::bn256_grumpkin::bn256,
    spartan::polys::eq::EqPolynomial,
};
use std::time::Duration;

type F = bn256::Scalar;

fn bench_rust_evals(c: &mut Criterion) {
    let mut group = c.benchmark_group("evals_from_points");
    group.warm_up_time(Duration::from_millis(100));
    group.measurement_time(Duration::from_secs(5));

    for size in [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 18, 20] {
        let r: Vec<F> = (0..size)
            .map(|i| F::from(i as u64))
            .collect();

        group.bench_with_input(
            BenchmarkId::new("Rust", size),
            &r,
            |b, r| {
                b.iter(|| {
                    black_box(EqPolynomial::evals_from_points(r))
                });
            },
        );
    }

    group.finish();
}

#[cfg(feature = "fortran")]
fn bench_fortran_evals(c: &mut Criterion) {
    let mut group = c.benchmark_group("evals_from_points");
    group.warm_up_time(Duration::from_millis(100));
    group.measurement_time(Duration::from_secs(5));

    for size in [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 18, 20] {
        let r: Vec<F> = (0..size)
            .map(|i| F::from(i as u64))
            .collect();

        group.bench_with_input(
            BenchmarkId::new("Fortran", size),
            &r,
            |b, r| {
                b.iter(|| {
                    black_box(evals_from_points_fortran(r).unwrap())
                });
            },
        );
    }

    group.finish();
}

#[cfg(feature = "fortran")]
fn bench_comparison(c: &mut Criterion) {
    let mut group = c.benchmark_group("evals_from_points_comparison");
    group.warm_up_time(Duration::from_millis(100));
    group.measurement_time(Duration::from_secs(5));

    for size in [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 18, 20] {
        let r: Vec<F> = (0..size)
            .map(|i| F::from(i as u64))
            .collect();

        // Rust implementation
        group.bench_with_input(
            BenchmarkId::new("Rust", size),
            &r,
            |b, r| {
                b.iter(|| {
                    black_box(EqPolynomial::evals_from_points(r))
                });
            },
        );

        // Fortran implementation
        group.bench_with_input(
            BenchmarkId::new("Fortran", size),
            &r,
            |b, r| {
                b.iter(|| {
                    black_box(evals_from_points_fortran(r).unwrap())
                });
            },
        );
    }

    group.finish();
}

criterion_group! {
    name = benches;
    config = Criterion::default()
        .warm_up_time(Duration::from_millis(500))
        .measurement_time(Duration::from_secs(10));
    targets = bench_rust_evals
}

#[cfg(feature = "fortran")]
criterion_group! {
    name = fortran_benches;
    config = Criterion::default()
        .warm_up_time(Duration::from_millis(500))
        .measurement_time(Duration::from_secs(10));
    targets = bench_fortran_evals, bench_comparison
}

#[cfg(not(feature = "fortran"))]
criterion_main!(benches);

#[cfg(feature = "fortran")]
criterion_main!(benches, fortran_benches);


# Beginning: Current Performance Baseline

## project overview
This project explores high-speed SNARK acceleration through Fortran integration, investigating whether an old language can provide new performance solutions for polynomial computations in Nova SNARK.

## Current Architecture
- **Language**: Rust (primary)
- **Target Optimization**: Polynomial computations (multilinear, univariate, sumcheck)
- **Approach**: Hybrid Rust + Fortran (modular migration)
- **Platform**: Linux

## Performance Bottlenecks (Identified)

### Polynomial Operations
Key polynomial computation modules:
- `src/spartan/polys/multilinear.rs` - Multilinear polynomial evaluations
- `src/spartan/polys/univariate.rs` - Univariate polynomial operations
- `src/spartan/polys/eq.rs` - Equality polynomial evaluations
- `src/spartan/sumcheck.rs` - Sumcheck protocol implementation

### Current Benchmarks
Available benchmark suites:
- `benches/recursive-snark.rs` - Recursive SNARK proving/verification
- `benches/compressed-snark.rs` - Compressed SNARK operations
- `benches/sha256.rs` - SHA-256 proving benchmarks
- `benches/ppsnark.rs` - Preprocessing SNARK benchmarks
- `benches/sumcheckeq.rs` - Sumcheck with equality polynomials
- `benches/commit.rs` - Commitment scheme benchmarks

### Known Performance Characteristics
- Uses `rayon` for parallelization (`par_iter`, `par_iter_mut`)
- Polynomial evaluations use parallel iterators extensively
- Matrix operations in `gaussian_elimination` (univariate polynomial construction)
- Memory-intensive operations with large polynomial vectors

## Recompilation Problem
The main challenge is the recompilation overhead when making changes. This affects:
- Development iteration speed
- Testing cycle time
- Performance optimization workflow

## Target Areas for Fortran Optimization
1. **Polynomial evaluations** - `MultilinearPolynomial::evaluate()`, `UniPoly::evaluate()`
2. **Sumcheck operations** - Equality polynomial evaluations, binding operations
3. **Matrix operations** - Gaussian elimination for polynomial interpolation
4. **Parallel computations** - Large-scale vector operations on polynomial coefficients

## Next Steps
1. Run baseline benchmarks to establish current performance metrics
2. Identify specific hot paths in polynomial computations
3. Design FFI interface for Rust-Fortran integration
4. Implement proof-of-concept Fortran module for one polynomial operation
5. Measure performance improvements and recompilation impact


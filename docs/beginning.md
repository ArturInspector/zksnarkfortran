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

## Benchmark Results Analysis

### Current Baseline (rust-baseline.json)
- **Total benchmarks**: 42 operations parsed
- **Operations**: multilinear (18), univariate (12), eq_polynomial (12)
- **Zero values**: 9 operations show 0.0 ms (operations < 0.01ms, too fast to measure accurately)
- **Parser status**: ✅ All results correctly parsed from Criterion JSON format

### Statistical Significance
**Current settings**: `sample_size(10)` - **TOO LOW for reliable measurements**

**Recommendations**:
- **Development/quick checks**: sample_size(10-20) is acceptable
- **Baseline/final measurements**: sample_size(100) minimum (Criterion default)
- **Critical comparisons**: sample_size(200+) for statistical confidence
- **Measurement time**: Current 10s is reasonable, but increase to 30s for final baselines

**Why it matters**:
- With 10 samples, confidence intervals are wide (±20-30% typical)
- For detecting 10-20% performance improvements, need 50-100+ samples
- Zero values (0.0 ms) indicate operations < 0.01ms - consider microsecond precision or larger test sizes

## Fortran Integration Architecture

### FFI Overhead Analysis

**Key Decision**: Where to minimize speed loss - FFI boundary or computation?

**FFI Overhead Components**:
1. **Data marshalling**: Rust Vec<Scalar> → Fortran array conversion
2. **Function call overhead**: ~10-50ns per call (negligible for large operations)
3. **Memory layout**: Rust Vec vs Fortran array (may need copying)
4. **Type conversion**: Scalar (field element) representation compatibility

**Critical Insight**: FFI overhead is **amortized** over computation size:
- **Small operations** (< 1ms): FFI overhead significant (10-20% loss)
- **Large operations** (> 10ms): FFI overhead negligible (< 1% loss)
- **Batch operations**: Process multiple operations in single FFI call

### Recommended Architecture

**Hybrid Approach - Batch Processing**:

```
Rust (orchestration) → Fortran (batch computation) → Rust (results)
```

**Strategy**:
1. **Batch multiple operations** into single FFI call
2. **Minimize data copying**: Use raw pointers or shared memory where possible
3. **Keep small operations in Rust**: Only migrate operations > 1ms to Fortran
4. **Use Fortran for hot loops**: Core polynomial evaluation loops, not wrapper functions

**Target Operations for Fortran** (by priority):

1. **High priority** (large, compute-intensive):
   - `MultilinearPolynomial::evaluate()` - size 16+ (1.88ms+)
   - `MultilinearPolynomial::evaluate_with()` - size 16+ (1.91ms+)
   - `EqPolynomial::evals_from_points()` - size 14+ (0.66ms+)
   - `gaussian_elimination()` - O(n³) matrix operations

2. **Medium priority** (moderate size):
   - `MultilinearPolynomial::bind_poly_var_top()` - size 18+ (1.94ms+)
   - `UniPoly::eval_at_one()` - parallel sum operations

3. **Low priority** (too small, FFI overhead dominates):
   - `EqPolynomial::evaluate()` - all sizes (0.0ms, too fast)
   - `UniPoly::evaluate()` - small degrees (< 1000)

### FFI Interface Design

**Option A: Direct Function Calls** (simpler, higher overhead)
```rust
// Rust calls Fortran for each operation
let result = fortran_evaluate_multilinear(z_ptr, r_ptr, len);
```

**Option B: Batch Processing** (complex, lower overhead) ⭐ **RECOMMENDED**
```rust
// Rust batches multiple operations
let results = fortran_batch_evaluate(operations_batch);
```

**Option C: Shared Memory** (most complex, lowest overhead)
```rust
// Rust and Fortran share memory, minimal copying
// Requires careful memory management
```

**Recommendation**: Start with **Option A** for proof-of-concept, migrate to **Option B** for production.

### Implementation Plan

1. **Phase 1: Proof of Concept**
   - Implement single operation: `EqPolynomial::evals_from_points()` (size 20, 30ms)
   - Measure FFI overhead baseline
   - Compare Rust vs Fortran performance

2. **Phase 2: Batch Interface**
   - Design batch processing API
   - Implement for multilinear evaluations
   - Optimize data marshalling

3. **Phase 3: Matrix Operations**
   - Port `gaussian_elimination()` to Fortran
   - Use Fortran's optimized BLAS/LAPACK if beneficial

4. **Phase 4: Integration**
   - Replace Rust implementations with Fortran calls
   - Maintain Rust API compatibility
   - Comprehensive benchmarking

## Next Steps
1. ✅ Run baseline benchmarks (completed)
3. **Design FFI interface** - Choose batch vs direct approach - right here we are bro.
4. **Implement proof-of-concept** - Single Fortran operation
5. **Measure FFI overhead** - Establish baseline for optimization decisions
6. **Iterate on architecture** - Based on overhead measurements


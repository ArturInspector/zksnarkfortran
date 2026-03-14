# zkSNARK × Fortran: HPC meets Zero-Knowledge

> *What happens when you take the oldest HPC language and throw it into the newest cryptographic frontier?*
> *Probably nothing. But probably nothing is how most things start.*

This is a **research experiment** — a fork of [Microsoft/Nova](https://github.com/microsoft/Nova) exploring whether Fortran's HPC legacy has anything to offer zkSNARK provers.

---

## The Hypothesis

zkSNARK provers are essentially scientific computing problems:
- Massive polynomial evaluations over prime fields
- Embarrassingly parallel inner loops (butterfly patterns)
- Memory-bound workloads that benefit from cache-aware access

Fortran has 60 years of compiler optimizations for exactly this shape of computation. The HPC world uses it on supercomputers. The Web3 world has never touched it.

**Is there a secret here, or is this just nostalgia?**

---

## What We're Doing

Accelerating `evals_from_points` — the EqPolynomial evaluation used in Nova's Sumcheck protocol.

**Algorithm:** butterfly recursion over field elements (structurally identical to NTT)

```
for each r_i (n iterations, sequential):
  for each j in 0..size-1:        ← EMBARRASSINGLY PARALLEL
    evals[size+j] = evals[j] * r_i
    evals[j]      = evals[j] - evals[size+j]
  size *= 2
```

**Our two optimizations:**

### 1. Pre-converted Montgomery form (`field_mul_mont_b`)

Normal `field_mul(a, b, c)` does:
```
to_montgomery(a) → to_montgomery(b) → schoolbook_mul → mont_reduce → from_montgomery
                   ^^^^^^^^^^^^^^^^^^^
                   paid EVERY iteration for r_i, which never changes
```

With `r_mont = to_montgomery(r)` once upfront:
```
to_montgomery(a) → schoolbook_mul → mont_reduce → from_montgomery
```

**Savings:** `2^n - 1` Montgomery multiplications eliminated (one per butterfly call).

### 2. `DO CONCURRENT` in inner loop

```fortran
do concurrent (j = 1:size)
  call field_mul_mont_b(evals(j), r_mont(i), temp_arr(j))
  call field_copy(evals(size + j), temp_arr(j))
  call field_sub(evals(j), temp_arr(j), evals(j))
end do
```

With `-fopenmp`, gfortran maps `DO CONCURRENT` to OpenMP threads.
Safety proof: indices `j` and `size+j` never alias across iterations when `j ∈ [1, size]`.

---

## Expected Benchmark Results

> *Honest predictions before measuring. Science requires falsifiable hypotheses.*

| Scenario | Expected | Why |
|----------|----------|-----|
| Fortran sequential vs Rust sequential | **Rust faster** (~2-5×) | Rust/ark-ff uses `u128` / `mulx` instruction; Fortran's `mul64` does 4 muls instead of 1 |
| Fortran `DO CONCURRENT` (4 threads) vs Rust single-thread | **Competitive or faster** | Outer butterfly steps expose enough parallelism at `n ≥ 16` |
| Fortran `DO CONCURRENT` vs Rust `rayon` | **Unknown** | This is the actual experiment |
| Montgomery pre-conversion alone | **~25% speedup** | Saves `1/3` of Montgomery ops in butterfly |

**Where Fortran genuinely wins nothing:**
- `mul64`: Fortran can't access `mulx`/`adcx` without inline asm. Structural loss.
- Single-threaded field arithmetic: ark-ff with `asm` feature is 2-5× faster.

**Where Fortran might surprise:**
- `DO CONCURRENT` with `-fopenmp -march=native` on multi-core without Rust threading boilerplate
- Cache behavior on large `n` (≥20): column-major Fortran arrays + sequential butterfly = friendly prefetch patterns

---

## Build & Run

### Prerequisites

```bash
# Ubuntu/Debian
sudo apt install gfortran

# Check version (need ≥ 9.0 for Fortran 2018 DO CONCURRENT)
gfortran --version
```

### Build Fortran library

```bash
cd fortran/build
make
# → builds libpolynomial_ops.so with -march=native -fopenmp
```

### Run Rust tests (with Fortran FFI)

```bash
cargo test --release --features fortran
```

### Run integration correctness check

```bash
cargo test --release --features fortran -- fortran --nocapture
```

---

## Architecture

```
nova-snark (Rust)
    │
    └── src/fortran/mod.rs          ← FFI bridge + byte conversion
            │
            └── ffi::evals_from_points_fortran()
                        │
                        ↓ (via libpolynomial_ops.so)
            fortran/src/ffi_interface.f90   ← butterfly + DO CONCURRENT
            fortran/src/field_ops.f90       ← BN256 field arithmetic
```

---

## Known Limitations (Honest)

1. **`mul64` is slow.** Pure Fortran 64×64→128-bit multiply uses 4 32-bit muls. Rust with `u128` or C with `__uint128_t` is faster at the atomic level.

2. **Signed 64-bit comparison.** `c_int64_t` comparisons for unsigned field elements work for BN256 (all limbs < 2^63) but are semantically wrong for other fields. A bug waiting to happen.

3. **No SIMD for `int64`.** Fortran auto-vectorization shines for `real`/`double`. For integer field arithmetic, SIMD gains are limited (no AVX2 unsigned 64×64 multiply).

4. **No tests, no benchmarks yet.** This is Phase 0 research. Trust nothing.

---

## Why This Might Matter Anyway

HPC supercomputing centers (Frontier, Summit, Perlmutter) run Fortran code for physics simulations. If verifiable computation (`zk-IVC`) ever needs to run on these machines, the natural integration path is Fortran FFI — not rewriting a million lines of simulation code in Rust.

This experiment explores whether that path is viable at all.

---

## References

- [Nova: Recursive Zero-Knowledge Arguments from Folding Schemes](https://eprint.iacr.org/2021/370) — Kothapalli, Setty, Tzialla. CRYPTO 2022
- [Spartan: Efficient and general-purpose zkSNARKs](https://eprint.iacr.org/2019/550.pdf) — Setty. CRYPTO 2020
- [Montgomery Reduction](https://en.wikipedia.org/wiki/Montgomery_modular_multiplication)
- [DO CONCURRENT — Fortran 2018 standard](https://fortranwiki.org/fortran/show/do+concurrent)

---

*This repo is a fork of [Microsoft/Nova](https://github.com/microsoft/Nova). Original README preserved below.*

---

# zkSNARK × Fortran: HPC meets Zero-Knowledge

> *What happens when you take the oldest HPC language and throw it into the newest cryptographic frontier?*
> *Probably nothing. But probably nothing is how most things start.*

This is a **research experiment** — a fork of [Microsoft/Nova](https://github.com/microsoft/Nova) exploring whether Fortran's HPC legacy has anything to offer zkSNARK provers.

---

## The Hypothesis

zkSNARK provers are essentially scientific computing problems:
Massive polynomial evaluations over prime fields
Embarrassingly parallel inner loops (butterfly patterns)
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

## Benchmark Results (Measured)

> *Real numbers. n = number of variables, output size = 2^n field elements.*

| Implementation | n=16 | n=20 | vs Rust |
|---|---|---|---|
| **Rust** (ark-ff, single thread) | ~0.4 ms | **40 ms** | baseline |
| **Fortran sequential** | 30 ms | 505 ms | ~12× slower |
| **Fortran DO CONCURRENT** (4 threads) | 32 ms | 466 ms | ~11× slower |
| **Fortran via FFI** (from Rust) | — | 800 ms | ~20× slower |

### What the numbers say

**1. `mul64` is the root cause (~12× gap).**
Rust's `ark-ff` uses a single `mulx` x86 instruction for 64×64→128-bit multiply.
Fortran's `mul64` splits into four 32-bit multiplications. This is a structural loss —
no compiler flag fixes it without inline assembly.

**2. `DO CONCURRENT` didn't help.**
At n=20, gain is ~40ms (10%). The inner loop body (`field_mul_mont_b`) completes in
nanoseconds — too fine-grained for thread scheduling overhead to be worth it.
Would matter for n≥24 or coarser-grained parallel work.

**3. FFI byte serialization adds 58% overhead.**
2^20 elements × 32 bytes = 32 MB serialized and deserialized per call.
The FFI boundary as designed (byte buffers) cannot be a viable acceleration path.

### What a viable path looks like

For Fortran to matter in a zk context, data must **live in Fortran memory from the start**
— not passed as byte buffers across FFI. This means:
- Fortran-owned proof state, called from a thin Rust orchestration layer
- Or: Fortran for distributed NTT on HPC clusters where Rust isn't the host language

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

# Fortran Acceleration for Nova SNARK

This directory contains Fortran implementations of polynomial operations for Nova SNARK acceleration.

## Structure

```
fortran/
├── src/                    # Fortran source files
│   ├── montgomery.f90      # Montgomery reduction for 256-bit prime fields
│   ├── field_ops.f90       # Basic field arithmetic operations
│   ├── field_ops_mont.f90  # Field operations in Montgomery form
│   ├── eq_polynomial.f90   # Equality polynomial operations
│   └── ffi_interface.f90   # C-compatible FFI interface for Rust
├── build/                  # Build artifacts
│   └── Makefile            # Build configuration
└── tests/                  # Unit tests (to be added)
```

## Building

```bash
cd build
make
```

This will create `libpolynomial_ops.so` shared library.





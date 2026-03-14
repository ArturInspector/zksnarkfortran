# Makefile for building Fortran library for Nova SNARK

# Compiler settings
FC = gfortran
# -std=f2018: required for DO CONCURRENT with local variables
# -march=native: enables AVX2/AVX-512 where available (critical for SIMD on int loops)
# -fopenmp: enables DO CONCURRENT parallel execution (gfortran maps it to OpenMP runtime)
# -ftree-vectorize: aggressive auto-vectorization of inner loops
FFLAGS = -O3 -fPIC -std=f2018 -march=native -fopenmp -ftree-vectorize -Wall
LDFLAGS = -shared -fopenmp

# Directories
SRC_DIR = ../src
BUILD_DIR = .
LIB_NAME = libpolynomial_ops.so

SOURCES = $(SRC_DIR)/field_ops.f90 \
          $(SRC_DIR)/eq_polynomial.f90 \
          $(SRC_DIR)/ffi_interface.f90

# Object files
OBJECTS = field_ops.o \
          eq_polynomial.o \
          ffi_interface.o

# Default target
all: $(LIB_NAME)

# Build shared library
$(LIB_NAME): $(OBJECTS)
	$(FC) $(LDFLAGS) -o $(LIB_NAME) $(OBJECTS)

# Compile source files
field_ops.o: $(SRC_DIR)/field_ops.f90
	$(FC) $(FFLAGS) -c -o $@ $<

eq_polynomial.o: $(SRC_DIR)/eq_polynomial.f90 field_ops.o
	$(FC) $(FFLAGS) -c -o $@ $<

ffi_interface.o: $(SRC_DIR)/ffi_interface.f90 field_ops.o
	$(FC) $(FFLAGS) -c -o $@ $<

# Clean build artifacts
clean:
	rm -f $(OBJECTS) $(LIB_NAME)

# Quick benchmark: compare sequential vs DO CONCURRENT
# Usage: make bench N=20  (N = number of variables, output size = 2^N)
bench: $(LIB_NAME)
	@echo "=== Fortran evals_from_points benchmark (n=$(or $(N),20)) ==="
	@echo "Running with DO CONCURRENT (gfortran maps to OpenMP threads)"
	@OMP_NUM_THREADS=1 time -f "1 thread:  %e sec" ./bench_runner $(or $(N),20) 2>&1 || true
	@OMP_NUM_THREADS=4 time -f "4 threads: %e sec" ./bench_runner $(or $(N),20) 2>&1 || true

.PHONY: all clean bench

# Makefile for building Fortran library for Nova SNARK

# Compiler settings
FC = gfortran
FFLAGS = -O3 -fPIC -std=f2008 -Wall
LDFLAGS = -shared

# Directories
SRC_DIR = ../src
BUILD_DIR = .
LIB_NAME = libpolynomial_ops.so

SOURCES = $(SRC_DIR)/montgomery.f90 \
          $(SRC_DIR)/field_ops.f90 \
          $(SRC_DIR)/field_ops_mont.f90 \
          $(SRC_DIR)/eq_polynomial.f90 \
          $(SRC_DIR)/ffi_interface.f90

# Object files (order matters for dependencies)
OBJECTS = montgomery.o \
          field_ops.o \
          field_ops_mont.o \
          eq_polynomial.o \
          ffi_interface.o

# Default target
all: $(LIB_NAME)

# Build shared library
$(LIB_NAME): $(OBJECTS)
	$(FC) $(LDFLAGS) -o $(LIB_NAME) $(OBJECTS)

# Compile source files (order matters for module dependencies)
montgomery.o: $(SRC_DIR)/montgomery.f90
	$(FC) $(FFLAGS) -c -o $@ $<

field_ops.o: $(SRC_DIR)/field_ops.f90 montgomery.o
	$(FC) $(FFLAGS) -c -o $@ $<

field_ops_mont.o: $(SRC_DIR)/field_ops_mont.f90 montgomery.o
	$(FC) $(FFLAGS) -c -o $@ $<

eq_polynomial.o: $(SRC_DIR)/eq_polynomial.f90 field_ops.o
	$(FC) $(FFLAGS) -c -o $@ $<

ffi_interface.o: $(SRC_DIR)/ffi_interface.f90 field_ops.o field_ops_mont.o montgomery.o
	$(FC) $(FFLAGS) -c -o $@ $<

# Clean build artifacts
clean:
	rm -f $(OBJECTS) $(LIB_NAME)

.PHONY: all clean

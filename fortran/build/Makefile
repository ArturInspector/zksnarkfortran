# Makefile for building Fortran library for Nova SNARK

# Compiler settings
FC = gfortran
FFLAGS = -O3 -fPIC -std=f2003 -Wall
LDFLAGS = -shared

# Directories
SRC_DIR = ../src
BUILD_DIR = .
LIB_NAME = libpolynomial_ops.so

# Source files
SOURCES = $(SRC_DIR)/eq_polynomial.f90 \
          $(SRC_DIR)/ffi_interface.f90

# Object files
OBJECTS = eq_polynomial.o \
          ffi_interface.o

# Default target
all: $(LIB_NAME)

# Build shared library
$(LIB_NAME): $(OBJECTS)
	$(FC) $(LDFLAGS) -o $(LIB_NAME) $(OBJECTS)

# Compile source files
%.o: $(SRC_DIR)/%.f90
	$(FC) $(FFLAGS) -c -o $@ $<

# Clean build artifacts
clean:
	rm -f $(OBJECTS) $(LIB_NAME)

.PHONY: all clean

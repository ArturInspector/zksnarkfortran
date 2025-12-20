//! Fortran FFI bindings for polynomial operations acceleration
//! 
//! This module provides Rust interfaces to Fortran-accelerated polynomial
//! operations. Currently in development (Phase 1: Proof of Concept).
//!
//! # Safety
//! This module uses unsafe code for FFI calls. All unsafe blocks are
//! carefully documented and validated.

#![allow(unsafe_code)]  // Required for FFI

use ff::PrimeField;

/// Scalar size in bytes (32 bytes for 256-bit fields like Bn256)
pub const SCALAR_BYTES: usize = 32;

/// Error type for Fortran operations
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FortranError {
    /// Success
    Success = 0,
    /// Size mismatch between input and expected output
    SizeMismatch = 1,
    /// Fortran function returned error
    FortranError = -1,
    /// Library not loaded
    NotLoaded = -2,
}

impl std::fmt::Display for FortranError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FortranError::Success => write!(f, "Success"),
            FortranError::SizeMismatch => write!(f, "Size mismatch"),
            FortranError::FortranError => write!(f, "Fortran function error"),
            FortranError::NotLoaded => write!(f, "Fortran library not loaded"),
        }
    }
}

impl std::error::Error for FortranError {}

/// Convert Scalar to byte array
pub fn scalar_to_bytes<F: PrimeField>(scalar: &F) -> [u8; SCALAR_BYTES] {
    let repr = scalar.to_repr();
    let bytes: &[u8] = repr.as_ref();
    let mut result = [0u8; SCALAR_BYTES];
    let copy_len = bytes.len().min(SCALAR_BYTES);
    result[..copy_len].copy_from_slice(&bytes[..copy_len]);
    result
}

/// Convert byte array to Scalar
pub fn bytes_to_scalar<F: PrimeField>(bytes: &[u8; SCALAR_BYTES]) -> Result<F, FortranError> {
    F::from_repr(bytes.into())
        .into_option()
        .ok_or(FortranError::FortranError)
}

/// Convert Vec<Scalar> to Vec<u8> (flat byte array)
pub fn scalars_to_bytes<F: PrimeField>(scalars: &[F]) -> Vec<u8> {
    scalars
        .iter()
        .flat_map(|s| scalar_to_bytes(s).iter().copied())
        .collect()
}

/// Convert Vec<u8> (flat byte array) to Vec<Scalar>
pub fn bytes_to_scalars<F: PrimeField>(bytes: &[u8]) -> Result<Vec<F>, FortranError> {
    if bytes.len() % SCALAR_BYTES != 0 {
        return Err(FortranError::SizeMismatch);
    }
    
    let count = bytes.len() / SCALAR_BYTES;
    let mut result = Vec::with_capacity(count);
    
    for i in 0..count {
        let start = i * SCALAR_BYTES;
        let end = start + SCALAR_BYTES;
        let scalar_bytes: [u8; SCALAR_BYTES] = bytes[start..end].try_into().unwrap();
        result.push(bytes_to_scalar(&scalar_bytes)?);
    }
    
    Ok(result)
}

/// FFI bindings to Fortran library
#[cfg(feature = "fortran")]
mod ffi {
    use super::*;

    #[link(name = "polynomial_ops")]
    extern "C" {
        /// Fortran function: evals_from_points
        /// 
        /// # Safety
        /// - r_ptr must point to valid memory with r_len * SCALAR_BYTES bytes
        /// - evals_ptr must point to valid writable memory with evals_len * SCALAR_BYTES bytes
        /// - evals_len must equal 2^r_len
        pub fn evals_from_points_fortran(
            r_ptr: *const u8,
            r_len: i32,
            evals_ptr: *mut u8,
            evals_len: i32,
        ) -> i32;
    }
}

/// Fortran-accelerated evals_from_points
/// 
/// This is a placeholder that will call Fortran implementation once it's ready.
/// For now, falls back to Rust implementation.
#[cfg(feature = "fortran")]
pub fn evals_from_points_fortran<F: PrimeField>(
    r: &[F],
) -> Result<Vec<F>, FortranError> {
    use super::ffi;
    
    let r_len = r.len();
    let evals_len = 1usize << r_len; // 2^r_len
    
    // Convert input to bytes
    let r_bytes = scalars_to_bytes(r);
    
    // Allocate output buffer
    let mut evals_bytes = vec![0u8; evals_len * SCALAR_BYTES];
    
    // Call Fortran function
    let status = unsafe {
        ffi::evals_from_points_fortran(
            r_bytes.as_ptr(),
            r_len as i32,
            evals_bytes.as_mut_ptr(),
            evals_len as i32,
        )
    };
    
    if status != 0 {
        return Err(match status {
            1 => FortranError::SizeMismatch,
            _ => FortranError::FortranError,
        });
    }
    
    // Convert output back to Scalars
    bytes_to_scalars(&evals_bytes)
}

/// returns that fortran isn't available
pub fn evals_from_points_fortran_fallback<F: PrimeField>(
    _r: &[F],
) -> Result<Vec<F>, FortranError> {
    Err(FortranError::NotLoaded)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::provider::bn256_grumpkin::bn256;

    #[test]
    fn test_scalar_conversion() {
        type F = bn256::Scalar;
        
        let scalar = F::ONE;
        let bytes = scalar_to_bytes(&scalar);
        let restored = bytes_to_scalar(&bytes).unwrap();
        assert_eq!(scalar, restored);
    }

    #[test]
    fn test_scalars_conversion() {
        type F = bn256::Scalar;
        
        let scalars = vec![F::ONE, F::ZERO, F::from(42u64)];
        let bytes = scalars_to_bytes(&scalars);
        let restored = bytes_to_scalars(&bytes).unwrap();
        assert_eq!(scalars, restored);
    }
}

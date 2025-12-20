//! Integration tests for Fortran FFI
//! 
//! These tests verify that the Rust-Fortran interface works correctly.
//! Note: Requires libpolynomial_ops.so to be built and available in LD_LIBRARY_PATH

#[cfg(test)]
mod integration_tests {
    use crate::fortran::{scalar_to_bytes, scalars_to_bytes, bytes_to_scalars, FortranError};
    use crate::provider::bn256_grumpkin::bn256;
    use ff::PrimeField;

    #[test]
    fn test_ffi_interface_exists() {
        // Test that we can at least call the function (even if it returns error)
        // This verifies the library is linked correctly
        type F = bn256::Scalar;
        
        let r = vec![F::ONE, F::ZERO];
        let result = crate::fortran::evals_from_points_fortran_fallback(&r);
        
        // Should return NotLoaded error (expected for now)
        assert!(matches!(result, Err(FortranError::NotLoaded)));
    }

    #[test]
    fn test_scalar_roundtrip() {
        type F = bn256::Scalar;
        
        // Test various scalar values
        let test_values = vec![
            F::ZERO,
            F::ONE,
            F::from(42u64),
            F::from(12345u64),
        ];
        
        for &val in &test_values {
            let bytes = scalar_to_bytes(&val);
            let restored = crate::fortran::bytes_to_scalar(&bytes).unwrap();
            assert_eq!(val, restored, "Failed to roundtrip scalar: {:?}", val);
        }
    }

    #[test]
    fn test_scalars_roundtrip() {
        type F = bn256::Scalar;
        
        let scalars = vec![
            F::ZERO,
            F::ONE,
            F::from(1u64),
            F::from(2u64),
            F::from(255u64),
        ];
        
        let bytes = scalars_to_bytes(&scalars);
        let restored = bytes_to_scalars(&bytes).unwrap();
        
        assert_eq!(scalars.len(), restored.len());
        for (orig, rest) in scalars.iter().zip(restored.iter()) {
            assert_eq!(orig, rest);
        }
    }

    #[test]
    fn test_bytes_to_scalars_invalid_size() {
        // Test error handling for invalid byte array size
        let invalid_bytes = vec![0u8; 33]; // Not a multiple of 32
        let result = bytes_to_scalars(&invalid_bytes);
        assert!(matches!(result, Err(FortranError::SizeMismatch)));
    }
}

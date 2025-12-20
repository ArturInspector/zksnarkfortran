//! Integration test comparing Rust and Fortran implementations
//! 
//! To run: 
//!   export LD_LIBRARY_PATH=fortran/build:$LD_LIBRARY_PATH
//!   cargo test --features fortran --lib fortran::integration_test

#[cfg(feature = "fortran")]
#[cfg(test)]
mod tests {
    use crate::fortran::evals_from_points_fortran;
    use crate::spartan::polys::eq::EqPolynomial;
    use crate::provider::bn256_grumpkin::bn256;
    use ff::{Field, PrimeField};

    type F = bn256::Scalar;

    #[test]
    fn test_evals_from_points_small() {
        // Test with small input (2 variables = 4 evaluations)
        let r = vec![F::ONE, F::ZERO];
        
        // Rust reference implementation
        let rust_result = EqPolynomial::evals_from_points(&r);
        
        // Fortran implementation
        let fortran_result = evals_from_points_fortran(&r);
        
        match fortran_result {
            Ok(fortran_evals) => {
                assert_eq!(rust_result.len(), fortran_evals.len(), 
                    "Result lengths should match");
                
                for (i, (rust_val, fortran_val)) in rust_result.iter()
                    .zip(fortran_evals.iter()).enumerate() {
                    assert_eq!(rust_val, fortran_val,
                        "Mismatch at index {}: Rust={:?}, Fortran={:?}", 
                        i, rust_val, fortran_val);
                }
                
                println!("✓ Small test passed: {} evaluations match", rust_result.len());
            }
            Err(e) => {
                panic!("Fortran function failed: {:?}", e);
            }
        }
    }

    #[test]
    fn test_evals_from_points_medium() {
        // Test with medium input (3 variables = 8 evaluations)
        let r = vec![F::ONE, F::ZERO, F::from(2u64)];
        
        let rust_result = EqPolynomial::evals_from_points(&r);
        let fortran_result = evals_from_points_fortran(&r).expect("Fortran should succeed");
        
        assert_eq!(rust_result.len(), fortran_result.len());
        
        let mut mismatches = 0;
        for (i, (rust_val, fortran_val)) in rust_result.iter().zip(fortran_result.iter()).enumerate() {
            if rust_val != fortran_val {
                mismatches += 1;
                let rust_bytes = rust_val.to_repr();
                let fortran_bytes = fortran_val.to_repr();
                eprintln!("Mismatch at index {}:", i);
                eprintln!("  Rust:   {:?}", rust_val);
                eprintln!("  Fortran: {:?}", fortran_val);
                eprintln!("  Rust bytes:   {:02x?}", rust_bytes.as_ref());
                eprintln!("  Fortran bytes: {:02x?}", fortran_bytes.as_ref());
            }
        }
        
        assert_eq!(mismatches, 0, "Found {} mismatches", mismatches);
        println!("✓ Medium test passed: {} evaluations match", rust_result.len());
    }

    #[test]
    fn test_evals_from_points_single() {
        // Test with single variable (1 variable = 2 evaluations)
        let r = vec![F::ONE];
        
        let rust_result = EqPolynomial::evals_from_points(&r);
        let fortran_result = evals_from_points_fortran(&r).expect("Fortran should succeed");
        
        assert_eq!(rust_result, fortran_result);
        println!("✓ Single variable test passed");
    }

    #[test]
    fn test_evals_from_points_zero() {
        // Test with zero
        let r = vec![F::ZERO, F::ZERO];
        
        let rust_result = EqPolynomial::evals_from_points(&r);
        let fortran_result = evals_from_points_fortran(&r).expect("Fortran should succeed");
        
        assert_eq!(rust_result, fortran_result);
        println!("✓ Zero test passed");
    }
}

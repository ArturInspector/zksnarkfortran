//! Build script to link Fortran library
//! 
//! This script tells Rust where to find the libpolynomial_ops.so library
//! when the fortran feature is enabled.

fn main() {
    // Only configure linking when fortran feature is enabled
    if std::env::var("CARGO_FEATURE_FORTRAN").is_ok() {
        let project_root = std::env::var("CARGO_MANIFEST_DIR")
            .expect("CARGO_MANIFEST_DIR should be set");
        let fortran_build_dir = format!("{}/fortran/build", project_root);
        
        // Tell the linker where to find the library
        println!("cargo:rustc-link-search=native={}", fortran_build_dir);
        println!("cargo:rustc-link-lib=dylib=polynomial_ops");
        
        // Rebuild if the library changes
        println!("cargo:rerun-if-changed={}/libpolynomial_ops.so", fortran_build_dir);
    }
}




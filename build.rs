fn main() {
    // Only link Fortran library when the feature is enabled
    if std::env::var("CARGO_FEATURE_FORTRAN").is_ok() {
        // Path to the built Fortran shared library
        let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
        let lib_path = format!("{}/fortran/build", manifest_dir);

        println!("cargo:rustc-link-search=native={}", lib_path);
        println!("cargo:rustc-link-lib=dylib=polynomial_ops");

        // Re-run build script if library changes
        println!("cargo:rerun-if-changed=fortran/build/libpolynomial_ops.so");
        println!("cargo:rerun-if-changed=fortran/src/field_ops.f90");
        println!("cargo:rerun-if-changed=fortran/src/ffi_interface.f90");
    }
}

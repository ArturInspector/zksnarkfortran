//! This library implements Nova, a high-speed recursive SNARK.
#![deny(
  warnings,
  unused,
  future_incompatible,
  nonstandard_style,
  rust_2018_idioms,
  missing_docs
)]
#![allow(non_snake_case)]
// Changed from forbid to deny: allows #[allow(unsafe_code)] in fortran FFI module only
#![deny(unsafe_code)]

// main APIs exposed by this library
pub mod nova;

#[cfg(feature = "experimental")]
pub mod neutron;

// public modules
pub mod errors;
pub mod frontend;
pub mod gadgets;
pub mod provider;
pub mod spartan;
pub mod traits;

// Fortran FFI acceleration (research experiment).
// unsafe needed for FFI calls to Fortran shared library.
#[cfg(feature = "fortran")]
#[allow(unsafe_code)]
pub mod fortran;

// private modules
mod constants;
mod digest;
mod r1cs;

use traits::{commitment::CommitmentEngineTrait, Engine};

// some type aliases
type CommitmentKey<E> = <<E as Engine>::CE as CommitmentEngineTrait<E>>::CommitmentKey;
type DerandKey<E> = <<E as Engine>::CE as CommitmentEngineTrait<E>>::DerandKey;
type Commitment<E> = <<E as Engine>::CE as CommitmentEngineTrait<E>>::Commitment;
type CE<E> = <E as Engine>::CE;

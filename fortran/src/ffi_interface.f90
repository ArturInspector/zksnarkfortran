! FFI interface - C-compatible functions for Rust
! Optimized version using Montgomery form for all internal operations
module ffi_interface 
  use iso_c_binding
  use field_ops          ! For bytes conversion
  use field_ops_mont     ! For Montgomery operations
  use montgomery         ! For conversion functions
  implicit none

contains

  ! C-compatible wrapper for evals_from_points
  ! Called from Rust via FFI
  !
  ! Algorithm: compute eq(x, r) for all x in {0,1}^n
  ! Result: 2^n field elements
  ! 
  ! Optimization: work entirely in Montgomery form
  ! - Convert inputs to Montgomery once
  ! - All operations in Montgomery form (no conversions)
  ! - Convert back to normal form only at the end
  function evals_from_points_fortran(r_ptr, r_len, evals_ptr, evals_len) &
    bind(c, name='evals_from_points_fortran') result(status)
    type(c_ptr), value, intent(in) :: r_ptr
    integer(c_int), value, intent(in) :: r_len
    type(c_ptr), value, intent(in) :: evals_ptr
    integer(c_int), value, intent(in) :: evals_len
    integer(c_int) :: status

    ! Fortran arrays from C pointers
    integer(c_int8_t), pointer :: r_bytes(:)
    integer(c_int8_t), pointer :: evals_bytes(:)
    
    ! Local variables
    type(field_element), allocatable :: r_normal(:)      ! Normal form (from bytes)
    type(field_element), allocatable :: r_mont(:)        ! Montgomery form
    type(field_element), allocatable :: evals_mont(:)     ! Montgomery form
    type(field_element), allocatable :: evals_normal(:)   ! Normal form (for output)
    type(field_element) :: temp_mont
    integer :: i, j, ell, size
    
    ! Validate input
    if (r_len <= 0 .or. evals_len /= 2**r_len) then
      status = 1
      return
    end if

    ! Convert C pointers to Fortran arrays
    call c_f_pointer(r_ptr, r_bytes, [r_len * SCALAR_BYTES])
    call c_f_pointer(evals_ptr, evals_bytes, [evals_len * SCALAR_BYTES])

    ! Allocate field element arrays
    ell = r_len
    allocate(r_normal(ell))
    allocate(r_mont(ell))
    allocate(evals_mont(evals_len))
    allocate(evals_normal(evals_len))
    
    ! Convert input bytes to field elements (normal form)
    do i = 1, ell
      call bytes_to_field(r_bytes((i-1)*SCALAR_BYTES + 1 : i*SCALAR_BYTES), r_normal(i))
    end do

    ! Convert inputs to Montgomery form (once, at the start)
    do i = 1, ell
      call to_montgomery(r_normal(i), r_mont(i))
    end do

    ! Initialize: evals[1] = ONE in Montgomery, rest = ZERO
    call field_mont_one(evals_mont(1))
    do i = 2, evals_len
      call field_mont_zero(evals_mont(i))
    end do

    ! Main algorithm: recursive doubling (all in Montgomery form)
    ! For each r_i (in reverse order):
    !   For each j in 0..size-1:
    !     evals[size + j] = evals[j] * r_i
    !     evals[j] = evals[j] - evals[size + j]
    !   size = size * 2
    
    size = 1
    do i = ell, 1, -1
      do j = 1, size
        ! temp = evals[j] * r[i] (Montgomery multiply - no conversions!)
        call field_mont_mul(evals_mont(j), r_mont(i), temp_mont)
        ! evals[size + j] = temp
        call field_mont_copy(evals_mont(size + j), temp_mont)
        ! evals[j] = evals[j] - temp (Montgomery subtract)
        call field_mont_sub(evals_mont(j), temp_mont, evals_mont(j))
      end do
      size = size * 2
    end do

    ! Convert results back to normal form (once, at the end)
    do i = 1, evals_len
      call from_montgomery(evals_mont(i), evals_normal(i))
    end do

    ! Convert result back to bytes
    do i = 1, evals_len
      call field_to_bytes(evals_normal(i), evals_bytes((i-1)*SCALAR_BYTES + 1 : i*SCALAR_BYTES))
    end do

    ! Cleanup
    deallocate(r_normal)
    deallocate(r_mont)
    deallocate(evals_mont)
    deallocate(evals_normal)

    status = 0  ! Success!
  end function evals_from_points_fortran

end module ffi_interface

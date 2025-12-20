! FFI interface - C-compatible functions for Rust
module ffi_interface 
  use iso_c_binding
  use field_ops
  implicit none

contains

  ! C-compatible wrapper for evals_from_points
  ! Called from Rust via FFI
  !
  ! Algorithm: compute eq(x, r) for all x in {0,1}^n
  ! Result: 2^n field elements
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
    type(field_element), allocatable :: r(:)
    type(field_element), allocatable :: evals(:)
    type(field_element) :: temp
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
    allocate(r(ell))
    allocate(evals(evals_len))
    
    ! Convert input bytes to field elements
    do i = 1, ell
      call bytes_to_field(r_bytes((i-1)*SCALAR_BYTES + 1 : i*SCALAR_BYTES), r(i))
    end do

    ! Initialize: evals[1] = ONE, rest = ZERO
    call field_one(evals(1))
    do i = 2, evals_len
      call field_zero(evals(i))
    end do

    ! Main algorithm: recursive doubling
    ! For each r_i (in reverse order):
    !   For each j in 0..size-1:
    !     evals[size + j] = evals[j] * r_i
    !     evals[j] = evals[j] - evals[size + j]
    !   size = size * 2
    
    size = 1
    do i = ell, 1, -1
      do j = 1, size
        ! temp = evals[j] * r[i]
        call field_mul(evals(j), r(i), temp)
        ! evals[size + j] = temp
        call field_copy(evals(size + j), temp)
        ! evals[j] = evals[j] - temp
        call field_sub(evals(j), temp, evals(j))
      end do
      size = size * 2
    end do

    ! Convert result back to bytes
    do i = 1, evals_len
      call field_to_bytes(evals(i), evals_bytes((i-1)*SCALAR_BYTES + 1 : i*SCALAR_BYTES))
    end do

    ! Cleanup
    deallocate(r)
    deallocate(evals)

    status = 0  ! Success!
  end function evals_from_points_fortran

end module ffi_interface

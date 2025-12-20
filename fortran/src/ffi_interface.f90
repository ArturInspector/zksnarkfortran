module ffi_interface 
  use iso_c_binding
  implicit none

  integer, parameter :: SCALAR_BYTES = 32

contains
  ! wrapper C-compatible for eval_from_points
  ! called from Rust with Fortran Foreign Interface (lol)

  function evals_from_points_fortran(r_ptr, r_len, evals_ptr, evals_len) &
    bind(c, name='evals_from_points_fortran') result(status)
  type(c_ptr), value, intent(in) :: r_ptr
  integer(c_int), value, intent(in) :: r_len
  type(c_ptr), value, intent(in) :: evals_ptr
  integer(c_int), value, intent(in) :: evals_len
  integer(c_int) :: status

  ! C pointers to arrays
  integer(c_int), pointer :: r_bytes(:)
  integer(c_int), pointer :: evals_bytes(:) ! deffered shape, 1d array
  
  ! input validate
  if (r_len <= 0 .or. evals_len /= 2**r_len) then
    status = 1
    return
  end if


  
  ! c pointers to fortan arrays
  call c_f_pointer(r_ptr, r_bytes, [r_len * SCALAR_BYTES])
  call c_f_pointer(evals_ptr, evals_bytes, [evals_len * SCALAR_BYTES])

  ! todo: full algorithm with field arithmetic
  ! return error mock for now, for tests
  status = -1

  evals_bytes = 0
  end function evals_from_points_fortran

end module ffi_interface
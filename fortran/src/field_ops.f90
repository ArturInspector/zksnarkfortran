!Field arithmetic for 256-bit prime fields (Bn256)
!Basic operations and conversions (Montgomery operations are in field_ops_mont)
!Scalar is 256 bits = 32 bytes equal to 4 x 64-bit limbs

module field_ops
  use iso_c_binding
  use montgomery  ! For field_element type and modulus
  implicit none

  integer, parameter :: SCALAR_BYTES = 32

contains

  ! init field element to zero
  subroutine field_zero(a)
    type(field_element), intent(out) :: a
    a%limbs = 0_c_int64_t
  end subroutine field_zero

  subroutine field_one(a)
    type(field_element), intent(out) :: a
    a%limbs = 0_c_int64_t
    a%limbs(1) = 1_c_int64_t
  end subroutine field_one

    ! Copy field element
  subroutine field_copy(dst, src)
    type(field_element), intent(out) :: dst
    type(field_element), intent(in) :: src
    dst%limbs = src%limbs
  end subroutine field_copy

  ! Convert bytes (32) to field element
  subroutine bytes_to_field(bytes, a)
    integer(c_int8_t), intent(in) :: bytes(SCALAR_BYTES)
    type(field_element), intent(out) :: a
    integer :: i, j, offset
    integer(c_int64_t) :: tmp

    a%limbs = 0_c_int64_t
    do i = 1, NLIMBS
      offset = (i - 1) * 8
      tmp = 0_c_int64_t
      do j = 1, 8
        ! Little-endian: first byte is least significant
        tmp = ior(tmp, ishft(int(iand(int(bytes(offset + j), c_int64_t), &
              int(Z'FF', c_int64_t)), c_int64_t), (j - 1) * 8))
      end do
      a%limbs(i) = tmp
    end do
  end subroutine bytes_to_field

  ! Convert field element to bytes (32)
  subroutine field_to_bytes(a, bytes)
    type(field_element), intent(in) :: a
    integer(c_int8_t), intent(out) :: bytes(SCALAR_BYTES)
    integer :: i, j, offset
    integer(c_int64_t) :: tmp

    do i = 1, NLIMBS
      offset = (i - 1) * 8
      tmp = a%limbs(i)
      do j = 1, 8
        bytes(offset + j) = int(iand(tmp, int(Z'FF', c_int64_t)), c_int8_t)
        tmp = ishft(tmp, -8)
      end do
    end do
  end subroutine field_to_bytes

  ! Compare: returns -1 if a < b, 0 if a == b, 1 if a > b
  function field_compare(a, b) result(cmp)
    type(field_element), intent(in) :: a, b
    integer :: cmp
    integer :: i

    cmp = 0
    do i = NLIMBS, 1, -1
      if (a%limbs(i) < b%limbs(i)) then
        cmp = -1
        return
      else if (a%limbs(i) > b%limbs(i)) then
        cmp = 1
        return
      end if
    end do
  end function field_compare

  ! Compare with modulus (wrapper for montgomery module function)
  function field_gte_modulus_wrapper(a) result(gte)
    type(field_element), intent(in) :: a
    logical :: gte
    gte = field_gte_modulus(a)  ! Use from montgomery module
  end function field_gte_modulus_wrapper

  ! Add without reduction (may overflow)
  subroutine field_add_no_reduce(a, b, c)
    type(field_element), intent(in) :: a, b
    type(field_element), intent(out) :: c
    integer :: i
    integer(c_int64_t) :: carry, sum_low
    
    carry = 0_c_int64_t
    do i = 1, NLIMBS
      ! Add with carry
      sum_low = a%limbs(i) + b%limbs(i) + carry
      ! Check for overflow (unsigned comparison trick)
      if (sum_low < a%limbs(i) .or. (carry > 0 .and. sum_low <= a%limbs(i))) then
        carry = 1_c_int64_t
      else
        carry = 0_c_int64_t
      end if
      c%limbs(i) = sum_low
    end do
  end subroutine field_add_no_reduce

  ! Subtract: c = a - b (assumes a >= b)
  subroutine field_sub_no_borrow(a, b, c)
    type(field_element), intent(in) :: a, b
    type(field_element), intent(out) :: c
    integer :: i
    integer(c_int64_t) :: borrow, diff
    
    borrow = 0_c_int64_t
    do i = 1, NLIMBS
      diff = a%limbs(i) - b%limbs(i) - borrow
      if (a%limbs(i) < b%limbs(i) + borrow) then
        borrow = 1_c_int64_t
      else
        borrow = 0_c_int64_t
      end if
      c%limbs(i) = diff
    end do
  end subroutine field_sub_no_borrow

  ! Add mod p: c = (a + b) mod p
  subroutine field_add(a, b, c)
    type(field_element), intent(in) :: a, b
    type(field_element), intent(out) :: c
    type(field_element) :: mod_elem, tmp

    mod_elem%limbs = BN256_MODULUS
    call field_add_no_reduce(a, b, c)
    
    ! If result >= modulus, subtract modulus
    if (field_gte_modulus_wrapper(c)) then
      call field_sub_no_borrow(c, mod_elem, tmp)
      c = tmp
    end if
  end subroutine field_add

  ! Subtract mod p: c = (a - b) mod p
  subroutine field_sub(a, b, c)
    type(field_element), intent(in) :: a, b
    type(field_element), intent(out) :: c
    type(field_element) :: mod_elem, tmp

    mod_elem%limbs = BN256_MODULUS
    
    if (field_compare(a, b) >= 0) then
      call field_sub_no_borrow(a, b, c)
    else
      ! a < b: result = p - (b - a)
      call field_sub_no_borrow(b, a, tmp)
      call field_sub_no_borrow(mod_elem, tmp, c)
    end if
  end subroutine field_sub

end module field_ops
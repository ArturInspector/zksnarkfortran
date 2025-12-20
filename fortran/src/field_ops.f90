!Field arithmetic for 256-bit prime fields (Bn256)
!Scalar is 256 bits = 32 bytes equal to 4 x 64-bit limbs
!Operations: add sub mul (all mod p)

!p = 21888242871839275222246405745257275088548364400416034343698204186575808495617

module field_ops
  use iso_c_binding
  implicit none

  ! number of 64-bit limbs for 256-bit field element
  integer, parameter :: NLIMBS = 4
  integer, parameter :: SCALAR_BYTES = 32

  ! bn256 scalar field modules
  ! libms cutting for 4 pieces
  integer(c_int64_t), parameter :: BN256_MODULUS(NLIMBS) = [ &
    int(Z'43e1f593f0000001', c_int64_t), &
    int(Z'2833e84879b97091', c_int64_t), &
    int(Z'b85045b68181585d', c_int64_t), &
    int(Z'30644e72e131a029', c_int64_t)  &
  ]

  ! Field element type 4 x 64 bit limbs (higher)
  type :: field_element
    integer(c_int64_t) :: limbs(NLIMBS)
  end type

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

  ! Compare with modulus
  function field_gte_modulus(a) result(gte)
    type(field_element), intent(in) :: a
    logical :: gte
    type(field_element) :: mod_elem

    mod_elem%limbs = BN256_MODULUS
    gte = field_compare(a, mod_elem) >= 0
  end function field_gte_modulus

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
    if (field_gte_modulus(c)) then
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

  ! Multiply mod p: c = (a * b) mod p
  ! This is a simplified Montgomery-style multiplication
  ! For now, use schoolbook multiplication with reduction
  subroutine field_mul(a, b, c)
    type(field_element), intent(in) :: a, b
    type(field_element), intent(out) :: c
    integer(c_int64_t) :: product(2 * NLIMBS)
    integer(c_int64_t) :: carry, lo, hi
    integer :: i, j, k
    type(field_element) :: mod_elem, tmp

    ! Initialize product to zero
    product = 0_c_int64_t
    
    ! Schoolbook multiplication
    do i = 1, NLIMBS
      carry = 0_c_int64_t
      do j = 1, NLIMBS
        k = i + j - 1
        ! Multiply limbs and add to product
        call mul64(a%limbs(i), b%limbs(j), lo, hi)
        
        ! Add to product with carry
        product(k) = product(k) + lo + carry
        if (product(k) < lo .or. (carry > 0 .and. product(k) <= lo)) then
          carry = hi + 1_c_int64_t
        else
          carry = hi
        end if
      end do
      if (k + 1 <= 2 * NLIMBS) then
        product(k + 1) = product(k + 1) + carry
      end if
    end do
    
    ! Reduce modulo p (simplified: just take lower limbs for now)
    ! TODO: proper Barrett or Montgomery reduction
    c%limbs = product(1:NLIMBS)
    
    ! Simple reduction by subtraction
    mod_elem%limbs = BN256_MODULUS
    do while (field_gte_modulus(c))
      tmp%limbs = c%limbs
      call field_sub_no_borrow(tmp, mod_elem, c)
    end do
  end subroutine field_mul

  ! Helper: multiply two 64-bit integers, return 128-bit result as (lo, hi)
  subroutine mul64(a, b, lo, hi)
    integer(c_int64_t), intent(in) :: a, b
    integer(c_int64_t), intent(out) :: lo, hi
    integer(c_int64_t) :: a_lo, a_hi, b_lo, b_hi
    integer(c_int64_t) :: p0, p1, p2, p3, carry
    
    ! Split into 32-bit halves
    a_lo = iand(a, int(Z'FFFFFFFF', c_int64_t))
    a_hi = ishft(a, -32)
    b_lo = iand(b, int(Z'FFFFFFFF', c_int64_t))
    b_hi = ishft(b, -32)
    
    ! Multiply parts
    p0 = a_lo * b_lo
    p1 = a_lo * b_hi
    p2 = a_hi * b_lo
    p3 = a_hi * b_hi
    
    ! Combine
    carry = ishft(p0, -32) + iand(p1, int(Z'FFFFFFFF', c_int64_t)) + &
            iand(p2, int(Z'FFFFFFFF', c_int64_t))
    lo = iand(p0, int(Z'FFFFFFFF', c_int64_t)) + ishft(iand(carry, int(Z'FFFFFFFF', c_int64_t)), 32)
    hi = p3 + ishft(p1, -32) + ishft(p2, -32) + ishft(carry, -32)
  end subroutine mul64

end module field_ops
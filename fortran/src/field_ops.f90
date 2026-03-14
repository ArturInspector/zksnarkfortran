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
  ! libms cutting for 4 pieces (little-endian, least significant first)
  integer(c_int64_t), parameter :: BN256_MODULUS(NLIMBS) = [ &
    int(Z'43e1f593f0000001', c_int64_t), &
    int(Z'2833e84879b97091', c_int64_t), &
    int(Z'b85045b68181585d', c_int64_t), &
    int(Z'30644e72e131a029', c_int64_t)  &
  ]
  
  ! Montgomery reduction constants
  ! p_prime = -p^-1 mod 2^64 (for Montgomery reduction)
  integer(c_int64_t), parameter :: BN256_P_PRIME = int(Z'c2e1f593efffffff', c_int64_t)
  
  ! R^2 mod p (for converting to Montgomery form)
  ! R = 2^256, R^2 mod p precomputed
  integer(c_int64_t), parameter :: BN256_R_SQUARED_MOD_P(NLIMBS) = [ &
    int(Z'1bb8e645ae216da7', c_int64_t), &
    int(Z'53fe3ab1e35c59e3', c_int64_t), &
    int(Z'8c49833d53bb8085', c_int64_t), &
    int(Z'0216d0b17f4e44a5', c_int64_t)  &
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
  pure subroutine field_copy(dst, src)
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
  pure function field_compare(a, b) result(cmp)
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
  pure function field_gte_modulus(a) result(gte)
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
  pure subroutine field_sub_no_borrow(a, b, c)
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
  pure subroutine field_sub(a, b, c)
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

  ! Montgomery reduction: reduces 512-bit product to 256-bit result
  ! Input: product (8 limbs, 512 bits)
  ! Output: result = product * R^-1 mod p (4 limbs, 256 bits)
  ! Algorithm: classic Montgomery reduction with R = 2^256
  pure subroutine montgomery_reduce(product, result)
    integer(c_int64_t), intent(in) :: product(2 * NLIMBS)
    type(field_element), intent(out) :: result
    integer(c_int64_t) :: t(2 * NLIMBS)
    integer(c_int64_t) :: u, carry, lo, hi, sum_val
    integer :: i, j
    
    ! Copy product to working variable
    t = product
    
    ! Montgomery reduction loop: for each limb i = 0 to NLIMBS-1
    do i = 1, NLIMBS
      ! u = t[i] * p_prime mod 2^64
      u = t(i) * BN256_P_PRIME
      
      ! Add u * p to t, starting at position i
      carry = 0_c_int64_t
      do j = 1, NLIMBS
        call mul64(u, BN256_MODULUS(j), lo, hi)
        
        ! Add to t[i+j-1] with carry
        sum_val = t(i + j - 1) + lo + carry
        if (sum_val < t(i + j - 1) .or. (carry > 0 .and. sum_val <= t(i + j - 1))) then
          carry = hi + 1_c_int64_t
        else
          carry = hi
        end if
        t(i + j - 1) = sum_val
      end do
      
      ! Propagate carry to next limb
      if (i + NLIMBS <= 2 * NLIMBS) then
        t(i + NLIMBS) = t(i + NLIMBS) + carry
      end if
    end do
    
    ! Result is in upper NLIMBS limbs, copy to result
    result%limbs = t(NLIMBS + 1 : 2 * NLIMBS)
    
    ! Final reduction: if result >= p, subtract p
    if (field_gte_modulus(result)) then
      block
        type(field_element) :: mod_elem, tmp_result
        mod_elem%limbs = BN256_MODULUS
        tmp_result%limbs = result%limbs
        call field_sub_no_borrow(tmp_result, mod_elem, result)
      end block
    end if
  end subroutine montgomery_reduce
  
  ! Convert normal form to Montgomery form: a_mont = a * R mod p
  ! Uses precomputed R^2 mod p: a * R = (a * R^2) / R mod p
  pure subroutine to_montgomery(a_normal, a_mont)
    type(field_element), intent(in) :: a_normal
    type(field_element), intent(out) :: a_mont
    integer(c_int64_t) :: product(2 * NLIMBS)
    integer(c_int64_t) :: carry, lo, hi
    integer :: i, j, k
    
    ! Multiply a_normal * R^2 to get 512-bit product
    product = 0_c_int64_t
    
    do i = 1, NLIMBS
      carry = 0_c_int64_t
      do j = 1, NLIMBS
        k = i + j - 1
        call mul64(a_normal%limbs(i), BN256_R_SQUARED_MOD_P(j), lo, hi)
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
    
    ! Montgomery reduce to get a * R mod p
    call montgomery_reduce(product, a_mont)
  end subroutine to_montgomery
  
  ! Convert Montgomery form to normal form: a_normal = a_mont * R^-1 mod p
  ! Represent a_mont as 512-bit number (a_mont, 0) = a_mont * R
  ! Montgomery reduction gives (a_mont * R) * R^-1 = a_mont mod p (normal form)
  pure subroutine from_montgomery(a_mont, a_normal)
    type(field_element), intent(in) :: a_mont
    type(field_element), intent(out) :: a_normal
    integer(c_int64_t) :: product(2 * NLIMBS)
    
    ! Represent a_mont as upper half of 512-bit number
    ! This represents a_mont * R (since R = 2^256)
    product(1:NLIMBS) = 0_c_int64_t
    product(NLIMBS + 1:2 * NLIMBS) = a_mont%limbs
    
    ! Montgomery reduce: result = (a_mont * R) * R^-1 = a_mont mod p (normal form)
    call montgomery_reduce(product, a_normal)
  end subroutine from_montgomery

  ! Multiply mod p when b is already in Montgomery form
  ! Saves one to_montgomery call — use when b is pre-converted (e.g. loop invariants)
  ! c = (a * b_mont) mod p
  pure subroutine field_mul_mont_b(a, b_mont, c)
    type(field_element), intent(in) :: a, b_mont
    type(field_element), intent(out) :: c
    type(field_element) :: a_mont, c_mont
    integer(c_int64_t) :: product(2 * NLIMBS)
    integer(c_int64_t) :: carry, lo, hi
    integer :: i, j, k

    call to_montgomery(a, a_mont)

    product = 0_c_int64_t
    do i = 1, NLIMBS
      carry = 0_c_int64_t
      do j = 1, NLIMBS
        k = i + j - 1
        call mul64(a_mont%limbs(i), b_mont%limbs(j), lo, hi)
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

    call montgomery_reduce(product, c_mont)
    call from_montgomery(c_mont, c)
  end subroutine field_mul_mont_b

  ! Multiply mod p: c = (a * b) mod p using Montgomery reduction
  ! Strategy: convert inputs to Montgomery form, multiply, convert result back
  subroutine field_mul(a, b, c)
    type(field_element), intent(in) :: a, b
    type(field_element), intent(out) :: c
    type(field_element) :: a_mont, b_mont, c_mont
    integer(c_int64_t) :: product(2 * NLIMBS)
    integer(c_int64_t) :: carry, lo, hi
    integer :: i, j, k

    ! Convert inputs to Montgomery form
    call to_montgomery(a, a_mont)
    call to_montgomery(b, b_mont)
    
    product = 0_c_int64_t
    
    ! Schoolbook multiplication
    do i = 1, NLIMBS
      carry = 0_c_int64_t
      do j = 1, NLIMBS
        k = i + j - 1
        call mul64(a_mont%limbs(i), b_mont%limbs(j), lo, hi)
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
    
    ! Montgomery reduce: c_mont = (a_mont * b_mont) * R^-1 mod p
    call montgomery_reduce(product, c_mont)
    
    call from_montgomery(c_mont, c)
  end subroutine field_mul

  ! Helper: multiply two 64-bit integers, return 128-bit result as (lo, hi)
  pure subroutine mul64(a, b, lo, hi)
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
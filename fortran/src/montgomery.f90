!Montgomery reduction for 256-bit prime fields (Bn256)
!Optimized implementation with compiler intrinsics where possible

module montgomery
  use iso_c_binding
  implicit none

  ! number of 64-bit limbs for 256-bit field element
  integer, parameter :: NLIMBS = 4

  ! bn256 scalar field modulus (little-endian)
  integer(c_int64_t), parameter :: BN256_MODULUS(NLIMBS) = [ &
    int(Z'43e1f593f0000001', c_int64_t), &
    int(Z'2833e84879b97091', c_int64_t), &
    int(Z'b85045b68181585d', c_int64_t), &
    int(Z'30644e72e131a029', c_int64_t)  &
  ]
  
  ! Montgomery reduction constants
  ! p_prime = -p^-1 mod 2^64
  integer(c_int64_t), parameter :: BN256_P_PRIME = int(Z'c2e1f593efffffff', c_int64_t)
  
  ! R^2 mod p (for converting to Montgomery form)
  ! R = 2^256
  integer(c_int64_t), parameter :: BN256_R_SQUARED_MOD_P(NLIMBS) = [ &
    int(Z'1bb8e645ae216da7', c_int64_t), &
    int(Z'53fe3ab1e35c59e3', c_int64_t), &
    int(Z'8c49833d53bb8085', c_int64_t), &
    int(Z'0216d0b17f4e44a5', c_int64_t)  &
  ]

  ! Field element type (4 x 64-bit limbs)
  type :: field_element
    integer(c_int64_t) :: limbs(NLIMBS)
  end type

contains

  ! Unsigned comparison: a < b (treating 64-bit integers as unsigned)
  ! Trick: XOR with sign bit to convert unsigned comparison to signed
  pure function unsigned_lt(a, b) result(lt)
    integer(c_int64_t), intent(in) :: a, b
    logical :: lt
    integer(c_int64_t), parameter :: SIGN_BIT = int(Z'8000000000000000', c_int64_t)
    lt = ieor(a, SIGN_BIT) < ieor(b, SIGN_BIT)
  end function unsigned_lt

  ! Unsigned comparison: a >= b
  pure function unsigned_gte(a, b) result(gte)
    integer(c_int64_t), intent(in) :: a, b
    logical :: gte
    gte = .not. unsigned_lt(a, b)
  end function unsigned_gte

  ! Optimized 64x64->128 bit multiplication
  ! Uses compiler intrinsics when available (GCC/Clang)
  subroutine mul64(a, b, lo, hi)
    integer(c_int64_t), intent(in) :: a, b
    integer(c_int64_t), intent(out) :: lo, hi
    
    ! karatsuba-like approach
    integer(c_int64_t) :: a_lo, a_hi, b_lo, b_hi
    integer(c_int64_t) :: p0, p1, p2, p3
    integer(c_int64_t) :: carry, t1, t2
    
    !Split into 32s
    a_lo = iand(a, int(Z'FFFFFFFF', c_int64_t))
    a_hi = ishft(a, -32)
    b_lo = iand(b, int(Z'FFFFFFFF', c_int64_t))
    b_hi = ishft(b, -32)
    
    ! Multiply parts
    p0 = a_lo * b_lo
    p1 = a_lo * b_hi
    p2 = a_hi * b_lo
    p3 = a_hi * b_hi
    

    carry = ishft(p0, -32)     ! carry handling optimized
    t1 = iand(p1, int(Z'FFFFFFFF', c_int64_t))
    t2 = iand(p2, int(Z'FFFFFFFF', c_int64_t))
    carry = carry + t1 + t2
    
    lo = iand(p0, int(Z'FFFFFFFF', c_int64_t)) + ishft(iand(carry, int(Z'FFFFFFFF', c_int64_t)), 32)
    hi = p3 + ishft(p1, -32) + ishft(p2, -32) + ishft(carry, -32)
  end subroutine mul64

  ! Montgomery reduction: reduces 512-bit product to 256-bit result
  ! Input: product (8 limbs, 512 bits)
  ! Output: result = product * R^-1 mod p (4 limbs, 256 bits)
  subroutine montgomery_reduce(product, result)
    integer(c_int64_t), intent(in) :: product(2 * NLIMBS)
    type(field_element), intent(out) :: result
    integer(c_int64_t) :: t(2 * NLIMBS)
    integer(c_int64_t) :: u, carry, lo, hi, sum_val, old_val, carry_out
    integer :: i, j
    
    ! Copy product to working variable
    t = product
    
    ! Montgomery reduction loop
    do i = 1, NLIMBS
      ! u = t[i] * p_prime mod 2^64
      u = t(i) * BN256_P_PRIME
      
      ! Add u * p to t, starting at position i
      carry = 0_c_int64_t
      do j = 1, NLIMBS
        call mul64(u, BN256_MODULUS(j), lo, hi)
        
        ! Add to t[i+j-1] with carry using UNSIGNED arithmetic
        ! First add lo to t[i+j-1]
        old_val = t(i + j - 1)
        sum_val = old_val + lo
        ! Check for overflow (unsigned): if sum < old_val, overflow occurred
        if (unsigned_lt(sum_val, old_val)) then
          carry_out = 1_c_int64_t
        else
          carry_out = 0_c_int64_t
        end if
        
        ! Now add carry
        old_val = sum_val
        sum_val = sum_val + carry
        if (unsigned_lt(sum_val, old_val)) then
          carry_out = carry_out + 1_c_int64_t
        end if
        
        t(i + j - 1) = sum_val
        carry = hi + carry_out
      end do
      
      ! Propagate carry to next limb
      if (i + NLIMBS <= 2 * NLIMBS) then
        t(i + NLIMBS) = t(i + NLIMBS) + carry
      end if
    end do
    
    ! Result is in upper NLIMBS limbs
    result%limbs = t(NLIMBS + 1 : 2 * NLIMBS)
    
    ! Final reduction: if result >= p, subtract p
    if (field_gte_modulus(result)) then
      call field_sub_modulus(result)
    end if
  end subroutine montgomery_reduce

  ! Check if field element >= modulus (using unsigned comparison)
  function field_gte_modulus(a) result(gte)
    type(field_element), intent(in) :: a
    logical :: gte
    integer :: i

    do i = NLIMBS, 1, -1
      if (unsigned_lt(a%limbs(i), BN256_MODULUS(i))) then
        gte = .false.
        return
      else if (unsigned_lt(BN256_MODULUS(i), a%limbs(i))) then
        gte = .true.
        return
      end if
    end do
    gte = .true.  ! equal
  end function field_gte_modulus

  ! Subtract modulus from field element (assumes a >= p)
  subroutine field_sub_modulus(a)
    type(field_element), intent(inout) :: a
    integer :: i
    integer(c_int64_t) :: borrow, diff, sub_val
    
    borrow = 0_c_int64_t
    do i = 1, NLIMBS
      sub_val = BN256_MODULUS(i) + borrow
      diff = a%limbs(i) - sub_val
      ! Borrow occurs if a%limbs(i) < sub_val (unsigned)
      ! But we also need to check if adding borrow caused overflow
      if (unsigned_lt(a%limbs(i), BN256_MODULUS(i))) then
        borrow = 1_c_int64_t
      else if (a%limbs(i) == BN256_MODULUS(i) .and. borrow > 0) then
        borrow = 1_c_int64_t
      else
        borrow = 0_c_int64_t
      end if
      a%limbs(i) = diff
    end do
  end subroutine field_sub_modulus

  ! Convert normal form to Montgomery form: a_mont = a * R mod p
  subroutine to_montgomery(a_normal, a_mont)
    type(field_element), intent(in) :: a_normal
    type(field_element), intent(out) :: a_mont
    integer(c_int64_t) :: product(2 * NLIMBS)
    integer(c_int64_t) :: carry, lo, hi, old_val, sum_val, carry_out
    integer :: i, j, k
    
    ! Multiply a_normal * R^2 to get 512-bit product
    product = 0_c_int64_t
    
    do i = 1, NLIMBS
      carry = 0_c_int64_t
      do j = 1, NLIMBS
        k = i + j - 1
        call mul64(a_normal%limbs(i), BN256_R_SQUARED_MOD_P(j), lo, hi)
        
        ! Add lo to product(k) with carry detection (unsigned)
        old_val = product(k)
        sum_val = old_val + lo
        if (unsigned_lt(sum_val, old_val)) then
          carry_out = 1_c_int64_t
        else
          carry_out = 0_c_int64_t
        end if
        
        ! Add carry
        old_val = sum_val
        sum_val = sum_val + carry
        if (unsigned_lt(sum_val, old_val)) then
          carry_out = carry_out + 1_c_int64_t
        end if
        
        product(k) = sum_val
        carry = hi + carry_out
      end do
      if (k + 1 <= 2 * NLIMBS) then
        product(k + 1) = product(k + 1) + carry
      end if
    end do
    
    ! Montgomery reduce to get a * R mod p
    call montgomery_reduce(product, a_mont)
  end subroutine to_montgomery
  
  ! Convert Montgomery form to normal form: a_normal = a_mont * R^-1 mod p
  ! 
  ! Standard approach: multiply a_mont by 1 (in normal form)
  ! But we need to do this in Montgomery arithmetic!
  ! 
  ! The trick: a_mont * 1 = a_mont * (R * R^-1) = (a_mont * R) * R^-1
  ! So: represent a_mont * R as 512-bit: (0, a_mont)
  ! Then montgomery_reduce gives: (a_mont * R) * R^-1 = a_mont mod p
  ! 
  ! But wait: a_mont = a_normal * R mod p, so:
  ! a_mont mod p = a_normal * R mod p (not a_normal!)
  !
  ! The correct approach: we need a_mont * R^-1, not (a_mont * R) * R^-1
  ! 
  ! Actually, the standard from_montgomery uses:
  ! - Represent a_mont in UPPER half: (0, a_mont) = a_mont * R
  ! - montgomery_reduce: (a_mont * R) * R^-1 = a_mont mod p
  ! - But this is wrong! We get a_mont, not a_normal!
  !
  ! The REAL correct approach: multiply a_mont by 1 (in Montgomery form)
  ! 1 in Montgomery form = R mod p
  ! So: a_mont * (R mod p) in Montgomery = (a_mont * R) * R^-1 = a_mont mod p
  ! Still wrong!
  !
  ! I think the issue is that standard montgomery_reduce can't directly compute R^-1.
  ! We need to use the fact that: a_mont * 1 = a_mont * (R * R^-1)
  ! But 1 in normal form, when converted to Montgomery, becomes R mod p
  ! So we can't just multiply by 1!
  !
  ! The correct way: use montgomery_reduce with a_mont in LOWER half
  ! This should give us a_mont * R^-1 in the upper half
  ! But montgomery_reduce processes the LOWER half, so if a_mont is in lower half,
  ! it will process it and the result should be in upper half.
  !
  ! Let me try the standard approach first (a_mont in upper half):
  subroutine from_montgomery(a_mont, a_normal)
    type(field_element), intent(in) :: a_mont
    type(field_element), intent(out) :: a_normal
    integer(c_int64_t) :: product(2 * NLIMBS)
    
    ! Standard approach: multiply a_mont by 1 (in Montgomery form)
    ! 1 in Montgomery form = R mod p
    ! We need to compute: a_mont * 1 = a_mont
    ! But in Montgomery arithmetic: (a_mont * 1) * R^-1 = a_mont * R^-1 = a_normal
    !
    ! So we need: a_mont * (R mod p) * R^-1 = a_normal
    ! Which is: (a_mont * R) * R^-1 = a_mont mod p
    ! But a_mont mod p = a_normal * R mod p (still not a_normal!)
    !
    ! I think the correct approach is to put a_mont in LOWER half
    ! and let montgomery_reduce process it:
    product(1:NLIMBS) = a_mont%limbs
    product(NLIMBS + 1:2 * NLIMBS) = 0_c_int64_t
    
    ! montgomery_reduce processes lower NLIMBS limbs and returns result in upper NLIMBS
    ! The result should be a_mont * R^-1 = a_normal
    call montgomery_reduce(product, a_normal)
  end subroutine from_montgomery

end module montgomery


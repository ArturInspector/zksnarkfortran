!Field arithmetic operations in Montgomery form
!All operations work directly with Montgomery representation (no conversions)
!This is much faster for sequences of operations

module field_ops_mont
  use iso_c_binding
  use montgomery  ! NLIMBS, field_element, unsigned_lt, etc. are defined here
  implicit none

contains

  ! Initialize field element in Montgomery form to zero
  subroutine field_mont_zero(a)
    type(field_element), intent(out) :: a
    a%limbs = 0_c_int64_t
  end subroutine field_mont_zero

  ! Initialize field element in Montgomery form to one (1 * R mod p)
  subroutine field_mont_one(a)
    type(field_element), intent(out) :: a
    ! One in Montgomery form = R mod p
    ! We'll compute this by converting 1 to Montgomery
    type(field_element) :: one_normal
    one_normal%limbs = 0_c_int64_t
    one_normal%limbs(1) = 1_c_int64_t
    call to_montgomery(one_normal, a)
  end subroutine field_mont_one

  ! Copy field element in Montgomery form
  subroutine field_mont_copy(dst, src)
    type(field_element), intent(out) :: dst
    type(field_element), intent(in) :: src
    dst%limbs = src%limbs
  end subroutine field_mont_copy

  ! Add in Montgomery form: c_mont = (a_mont + b_mont) mod p
  ! Note: addition is the same in both forms
  subroutine field_mont_add(a_mont, b_mont, c_mont)
    type(field_element), intent(in) :: a_mont, b_mont
    type(field_element), intent(out) :: c_mont
    integer :: i
    integer(c_int64_t) :: carry, sum_low, old_val
    
    carry = 0_c_int64_t
    do i = 1, NLIMBS
      ! Add with carry using unsigned arithmetic
      old_val = a_mont%limbs(i)
      sum_low = old_val + b_mont%limbs(i)
      ! Check for overflow (unsigned)
      if (unsigned_lt(sum_low, old_val)) then
        carry = carry + 1_c_int64_t
      end if
      old_val = sum_low
      sum_low = sum_low + carry
      if (unsigned_lt(sum_low, old_val)) then
        carry = 1_c_int64_t
      else
        carry = 0_c_int64_t
      end if
      c_mont%limbs(i) = sum_low
    end do
    
    ! If result >= modulus, subtract modulus
    if (field_gte_modulus(c_mont)) then
      call field_sub_modulus(c_mont)
    end if
  end subroutine field_mont_add

  ! Subtract in Montgomery form: c_mont = (a_mont - b_mont) mod p
  ! When a < b, we add p (the modulus itself, NOT p in Montgomery form)
  subroutine field_mont_sub(a_mont, b_mont, c_mont)
    type(field_element), intent(in) :: a_mont, b_mont
    type(field_element), intent(out) :: c_mont
    integer :: i
    integer(c_int64_t) :: borrow, a_val, b_val, diff
    
    ! Compute a_mont - b_mont with borrow
    ! Using standard subtraction with borrow algorithm:
    ! diff = a - b - borrow
    ! new_borrow = 1 if a < b + borrow (considering overflow)
    borrow = 0_c_int64_t
    do i = 1, NLIMBS
      a_val = a_mont%limbs(i)
      b_val = b_mont%limbs(i)
      
      ! Compute diff = a - b - borrow
      diff = a_val - b_val - borrow
      
      ! Determine new borrow:
      ! Borrow occurs if a < b, OR if a == b and borrow > 0
      if (unsigned_lt(a_val, b_val)) then
        borrow = 1_c_int64_t
      else if (a_val == b_val .and. borrow > 0) then
        borrow = 1_c_int64_t
      else
        borrow = 0_c_int64_t
      end if
      
      c_mont%limbs(i) = diff
    end do
    
    ! If borrow occurred (a < b), add modulus p (NOT p in Montgomery form!)
    if (borrow > 0) then
      call add_modulus(c_mont)
    end if
  end subroutine field_mont_sub

  ! Add modulus to field element (for wrapping in subtraction)
  subroutine add_modulus(a)
    type(field_element), intent(inout) :: a
    integer :: i
    integer(c_int64_t) :: carry, sum_val, old_val, carry_out
    
    carry = 0_c_int64_t
    do i = 1, NLIMBS
      carry_out = 0_c_int64_t
      
      ! First add modulus limb
      old_val = a%limbs(i)
      sum_val = old_val + BN256_MODULUS(i)
      if (unsigned_lt(sum_val, old_val)) then
        carry_out = 1_c_int64_t
      end if
      
      ! Then add carry from previous limb
      old_val = sum_val
      sum_val = sum_val + carry
      if (unsigned_lt(sum_val, old_val)) then
        carry_out = carry_out + 1_c_int64_t
      end if
      
      a%limbs(i) = sum_val
      carry = carry_out
    end do
  end subroutine add_modulus

  ! Compare two field elements in Montgomery form (unsigned)
  ! Returns -1 if a < b, 0 if a == b, 1 if a > b
  function field_compare_mont(a, b) result(cmp)
    type(field_element), intent(in) :: a, b
    integer :: cmp
    integer :: i

    cmp = 0
    do i = NLIMBS, 1, -1
      if (unsigned_lt(a%limbs(i), b%limbs(i))) then
        cmp = -1
        return
      else if (unsigned_lt(b%limbs(i), a%limbs(i))) then
        cmp = 1
        return
      end if
    end do
  end function field_compare_mont

  ! Multiply in Montgomery form: c_mont = (a_mont * b_mont) * R^-1 mod p
  ! This is the key optimization - no conversions needed!
  subroutine field_mont_mul(a_mont, b_mont, c_mont)
    type(field_element), intent(in) :: a_mont, b_mont
    type(field_element), intent(out) :: c_mont
    integer(c_int64_t) :: product(2 * NLIMBS)
    integer(c_int64_t) :: carry, lo, hi, old_val, sum_val, carry_out
    integer :: i, j, k

    product = 0_c_int64_t
    
    ! Schoolbook multiplication of Montgomery-form numbers
    do i = 1, NLIMBS
      carry = 0_c_int64_t
      do j = 1, NLIMBS
        k = i + j - 1
        call mul64(a_mont%limbs(i), b_mont%limbs(j), lo, hi)
        
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
    
    ! Montgomery reduce: c_mont = (a_mont * b_mont) * R^-1 mod p
    call montgomery_reduce(product, c_mont)
  end subroutine field_mont_mul

end module field_ops_mont


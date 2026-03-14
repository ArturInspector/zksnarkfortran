! Pure Fortran benchmark: butterfly EqPolynomial vs Rust baseline
!
! Build:
!   gfortran -O3 -march=native -fopenmp -std=f2018 \
!     ../src/field_ops.f90 bench_butterfly.f90 -o bench_butterfly
!
! Run (1 thread):  OMP_NUM_THREADS=1 ./bench_butterfly 20
! Run (4 threads): OMP_NUM_THREADS=4 ./bench_butterfly 20
!
! This eliminates FFI byte-serialization overhead — measures ONLY
! field arithmetic + DO CONCURRENT parallelism on BN256.

program bench_butterfly
  use iso_c_binding
  use field_ops
  implicit none

  integer :: n, evals_len, i, j, size_curr, argc
  character(len=8) :: arg
  type(field_element), allocatable :: r(:), r_mont(:), evals(:), temp_arr(:)
  real(8) :: t_start, t_end, elapsed

  ! Read n from command line (default 20)
  argc = command_argument_count()
  if (argc >= 1) then
    call get_command_argument(1, arg)
    read(arg, *) n
  else
    n = 20
  end if

  evals_len = 2 ** n
  write(*,'(A,I0,A,I0,A)') "n=", n, "  evals=", evals_len, "  (BN256 field elements)"

  allocate(r(n))
  allocate(r_mont(n))
  allocate(evals(evals_len))
  allocate(temp_arr(evals_len))

  ! Fill r with simple non-trivial values (deterministic, not random)
  ! r(i) = i mod p — just needs to be non-zero
  do i = 1, n
    call field_zero(r(i))
    r(i)%limbs(1) = int(i * 7 + 3, c_int64_t)
    call to_montgomery(r(i), r_mont(i))
  end do

  ! ---- Benchmark 1: sequential (OMP_NUM_THREADS=1 or plain loop) ----
  ! Initialize evals
  call field_one(evals(1))
  do i = 2, evals_len
    call field_zero(evals(i))
  end do

  call cpu_time(t_start)

  size_curr = 1
  do i = n, 1, -1
    do j = 1, size_curr
      call field_mul_mont_b(evals(j), r_mont(i), temp_arr(j))
      call field_copy(evals(size_curr + j), temp_arr(j))
      call field_sub(evals(j), temp_arr(j), evals(j))
    end do
    size_curr = size_curr * 2
  end do

  call cpu_time(t_end)
  elapsed = t_end - t_start
  write(*,'(A,F8.3,A)') "Sequential (do loop):    ", elapsed * 1000.0d0, " ms"

  ! ---- Benchmark 2: DO CONCURRENT ----
  call field_one(evals(1))
  do i = 2, evals_len
    call field_zero(evals(i))
  end do

  call cpu_time(t_start)

  size_curr = 1
  do i = n, 1, -1
    do concurrent (j = 1:size_curr)
      call field_mul_mont_b(evals(j), r_mont(i), temp_arr(j))
      call field_copy(evals(size_curr + j), temp_arr(j))
      call field_sub(evals(j), temp_arr(j), evals(j))
    end do
    size_curr = size_curr * 2
  end do

  call cpu_time(t_end)
  elapsed = t_end - t_start
  write(*,'(A,F8.3,A)') "DO CONCURRENT:           ", elapsed * 1000.0d0, " ms"

  ! Print one value so the compiler doesn't optimize everything away
  write(*,'(A,4Z17)') "evals(1).limbs: ", evals(1)%limbs

  deallocate(r, r_mont, evals, temp_arr)
end program bench_butterfly

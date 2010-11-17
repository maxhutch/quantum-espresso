!
! Copyright (C) 2009- Brian Kolb, Timo Thonhauser - Wake Forest University
! Copyright (C) 2010- Quantum ESPRESSO group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!----------------------------------------------------------------------------
MODULE kernel_table
  
  !!  This module is used to read in the kernel table file
  !!  "vdW_kernel_table" and store some of the important parameters.  The
  !!  top of the vdW_kernel_table file holds the number of q points, the
  !!  number of radial points (r) used in the kernel generation, the maximum
  !!  value of r used (r is the parameter in the kernel function d=q*r where
  !!  q is defined in DION equation 11), and the values of the q points
  !!  used.  These parameters are stored as public parameters for use in
  !!  various routines.  This routine also reads the tabulated values of the
  !!  Fourier transformed kernel function for each pair of q values (see
  !!  SOLER equations 3 and 11).  Since these kernel functions need to be
  !!  interpolated using splines, the second derivatives of the Fourier
  !!  transformed kernel functions (phi_alpha_beta) are also tabulated in
  !!  the vdW_kernel_table and are read in here.

  !!  This is done in a module because there are quite a few subroutines in
  !!  xc_vdW_DF.f90 that require knowledge of the number (identity) of q
  !!  points, the maximum value of the radius, and, of course, the tabulated
  !!  kernel function and its second derivatives (for spline interpolation).
  !!  Putting this routine in a module meas that those routines can just use
  !!  kernel_table rather than passing variables around all over the place.
  
  USE kinds,                  ONLY : dp
  USE io_files,               ONLY : find_free_unit, pseudo_dir
  USE constants,              ONLY : pi

  implicit none

  private
  save
  
  !! Variables to be used by various routines in xc_vdW_DF.f90, declared
  !! public so they can be seen from outside
  ! --------------------------------------------------------------------------
  
  public :: Nqs, Nr_points, r_max, q_mesh, q_cut, q_min, dk
  public :: kernel, d2phi_dk2
  public :: initialize_kernel_table
  public :: vdw_table_name

  integer, save :: Nqs, Nr_points                      !! The number of q points and radial points
  !                                                    !! used in generating the kernel phi(q1*r, q2*r)
  !                                                    !! (see DION 14-16 and SOLER 3)

  real(dp), save :: r_max, q_cut, q_min, dk            !! The maximum value of r, the maximum and minimum
  !                                                    !! values of q and the k-space spacing of grid points.
  !                                                    !! Note that, during a vdW run, values of q0 found
  !                                                    !! larger than q_cut will be saturated (SOLER 6-7) to
  !                                                    !! q_cut

  real(dp), allocatable, save :: q_mesh(:)             !! The values of all the q points used

  real(dp), allocatable, save :: kernel(:,:,:)         !! A matrix holding the Fourier transformed kernel function
  !                                                    !! for each pair of q values.  The ordering is
  !                                                    !! kernel(k_point, q1_value, q2_value)

  real(dp), allocatable, save ::  d2phi_dk2(:,:,:)     !! A matrix holding the second derivatives of the above
  !                                                    !! kernel matrix at each of the q points.  Stored as  
  !                                                    !! d2phi_dk2(k_point, q1_value, q2_value)
  !
  character(len=256) :: vdw_table_name                 !! If present from input use this name
  !
  ! --------------------------------------------------------------------------

CONTAINS


  !! ###################################################################################
  !!                          |                           |
  !!                          |  INITIALIZE_KERNEL_TABLE  |
  !!                          |___________________________|

  !!  Subroutine that actually reads the kernel file and stores the parameters.  This routine
  !!  is called only once, at the start of a vdW run.  

  subroutine initialize_kernel_table()
    
    USE io_files,         ONLY : find_free_unit

    integer :: q1_i, q2_i                           !! Indexing variables

    integer :: kernel_file                          !! The unit number for the kernel file

    logical :: file_exists                          !! A variable to say whether
    !                                               !! needed file exists

    character(len=1000) :: kernel_file_name         !! The path to the kernel file.
    !                                               !! Although this name must be
    !                                               !! "vdW_kernel_table", this variable
    !                                               !! is used to hold the entire path
    !                                               !! since we check 3 places for it.
    
    
    !!write(*,*) "Reading kernel table ... "

    
    !! Get the unit number for the kernel file
    kernel_file = find_free_unit()
   

    !!
    !!

    if (TRIM(vdw_table_name)=='') then
       
        vdw_table_name='vdW_kernel_table'
    
    endif
 
    !! First we check the current directory for the vdW_kernel_table file
    !! If it is not found there it is looked for in the pseudopotential 
    !! directory.  If it's not there the default kernel file installed
    !! in the PW directory of the PWSCF source is tried.  If none of those
    !! exist the code crashes.

    inquire(file=vdw_table_name, exist=file_exists)

    !! If the file is found in the current directory we use that one
    !! ------------------------------------------------------------------------------------------

    if (file_exists) then

       open(unit=kernel_file, file=vdw_table_name, status='old', form='unformatted', action='read')

    !! ------------------------------------------------------------------------------------------
    
    else
       
       !! No "vdW_kernel_table" file in the current directory.  Try the pseudopotential directory
       !! -----------------------------------------------------------------------------------------

       kernel_file_name = trim(pseudo_dir)//'/'//vdw_table_name
       inquire(file=kernel_file_name, exist=file_exists)

       if (file_exists) then

          open(unit=kernel_file, file=kernel_file_name, status='old', form='unformatted', action='read')
       ! -----------------------------------------------------------------------------------------
      
       else
        
          !! Finally, try the default pw_dir/PW/vdW_kernel_table file
          !! --------------------------------------------------------------------------------------
  
          kernel_file_name = 'DEFAULT_KERNEL_TABLE_FILE'
          inquire(file=kernel_file_name, exist=file_exists)
          
          if (file_exists) then

             open(unit=kernel_file, file=kernel_file_name, status='old', form='unformatted', action='read')

          !! --------------------------------------------------------------------------------------

          else

             !! No "vdW_kernel_table" file could be found.  Time to die.
             call errore('read_kernel_table', 'No \"vdW_kernel_table\" file could be found',1)

          end if

       end if

    end if

    !! Read in the number of q points used for this kernel file, the
    !! number of r points, and the maximum value of the r point
    read(kernel_file) Nqs, Nr_points, r_max

    allocate( q_mesh(Nqs) )
    allocate( kernel(0:Nr_points,Nqs,Nqs), d2phi_dk2(0:Nr_points,Nqs,Nqs) )
    
    !! Read in the values of the q points used to generate this kernel
    read(kernel_file) q_mesh


    !! For each pair of q values, read in the function phi_q1_q2(k).
    !! That is, the fourier transformed kernel function assuming q1 and q2
    !! for all the values of r used.
    !! ----------------------------------------------------------------------------------------------
    
    do q1_i = 1, Nqs
       do q2_i = 1, q1_i

          read(kernel_file) kernel(0:Nr_points, q1_i, q2_i)
          kernel(0:Nr_points, q2_i, q1_i) = kernel(0:Nr_points, q1_i, q2_i)

       end do
    end do

    !! ----------------------------------------------------------------------------------------------



    !! Again, for each pair of q values (q1 and q2), read in the value
    !! of the second derivative of the above mentiond Fourier transformed
    !! kernel function phi_alpha_beta(k).  These are used for spline
    !! interpolation of the Fourier transformed kernel.
    !! -----------------------------------------------------------------------------------------------

    do q1_i = 1, Nqs
       do q2_i = 1, q1_i

          read(kernel_file) d2phi_dk2(0:Nr_points, q1_i, q2_i)
          d2phi_dk2(0:Nr_points, q2_i, q1_i) = d2phi_dk2(0:Nr_points, q1_i, q2_i)

       end do
    end do

    !! -----------------------------------------------------------------------------------------------

    close(kernel_file)

    !! Define a few more vaiables useful to some of the subroutines in xc_vdW_DF.f90
    !! ------------------------------------------------------------------------------------------------

    q_cut = q_mesh(Nqs)
    q_min = q_mesh(1)
    dk = 2.0D0*pi/r_max

    !! ------------------------------------------------------------------------------------------------

  end subroutine initialize_kernel_table

  !! #################################################################################################



end MODULE kernel_table
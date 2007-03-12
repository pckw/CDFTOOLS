PROGRAM cdfmoy_sp
  !!-----------------------------------------------------------------------
  !!                 ***  PROGRAM cdfmoy_sp  ***
  !!
  !!  **  Purpose: Compute mean values for all the variables in a bunch
  !!                of cdf files given as argument
  !!                Store the results on a 'similar' cdf file.
  !!                TAKE CARE of the special values
  !!  
  !!  **  Method: Try to avoid 3 d arrays 
  !!
  !! history :
  !!     Original code :   J.M. Molines (Nov 2004 ) for ORCA025
  !!                       J.M. Molines (Apr 2005 ) put all NCF stuff in module
  !!                              now valid for grid T U V W icemod
  !!-----------------------------------------------------------------------
  !!  $Rev$
  !!  $Date$
  !!  $Id$
  !!--------------------------------------------------------------
  !! * Modules used
  USE cdfio 

  !! * Local variables
  IMPLICIT NONE
  INTEGER   :: jk,jt,jvar, jv                               !: dummy loop index
  INTEGER   :: ierr                                         !: working integer
  INTEGER   :: narg, iargc                                  !: 
  INTEGER   :: npiglo,npjglo, npk                           !: size of the domain
  INTEGER   ::  nvars                                       !: Number of variables in a file
  INTEGER , DIMENSION(:), ALLOCATABLE :: id_var , &         !: arrays of var id's
       &                             ipk    , &         !: arrays of vertical level for each var
       &                             id_varout,& 
       &                             id_varout2
  REAL(KIND=8) , DIMENSION (:,:), ALLOCATABLE :: tab, tab2  !: Arrays for cumulated values
  REAL(KIND=8)                                :: total_time
  REAL(KIND=4) , DIMENSION (:,:), ALLOCATABLE :: v2d ,&       !: Array to read a layer of data
       &                                   rmean, rmean2
  REAL(KIND=4),  DIMENSION (:), ALLOCATABLE   :: spval        !: special value (land point)
  REAL(KIND=4),DIMENSION(1)                   :: timean, tim

  CHARACTER(LEN=80) :: cfile ,cfileout, cfileout2           !: file name
  CHARACTER(LEN=80) ,DIMENSION(:), ALLOCATABLE:: cvarname   !: array of var name
  CHARACTER(LEN=80) ,DIMENSION(:), ALLOCATABLE:: cvarname2   !: array of var22 name for output

  TYPE (variable), DIMENSION(:), ALLOCATABLE :: typvar, typvar2

  INTEGER    :: ncout, ncout2
  INTEGER    :: istatus

  !!  Read command line
  narg= iargc()
  IF ( narg == 0 ) THEN
     PRINT *,' Usage : cdfmoy_sp ''list_of_ioipsl_model_output_files'' '
     PRINT *,'  In this version of cdfmoy, spval are taken into account'
     PRINT *,'    (in the standard version they are assumed to be 0 )'
     STOP
  ENDIF
  !!
  !! Initialisation from 1st file (all file are assume to have the same geometry)
  CALL getarg (1, cfile)

  npiglo= getdim (cfile,'x')
  npjglo= getdim (cfile,'y')
  npk   = getdim (cfile,'depth',kstatus=istatus)
  IF (istatus /= 0 ) THEN
     npk   = getdim (cfile,'z',kstatus=istatus)
     IF (istatus /= 0 ) STOP 'depth dimension name not suported'
  ENDIF


  PRINT *, 'npiglo=', npiglo
  PRINT *, 'npjglo=', npjglo
  PRINT *, 'npk   =', npk

  ALLOCATE( tab(npiglo,npjglo), tab2(npiglo,npjglo), v2d(npiglo,npjglo) )
  ALLOCATE( rmean(npiglo,npjglo), rmean2(npiglo,npjglo) )

  nvars = getnvar(cfile)
  PRINT *,' nvars =', nvars

  ALLOCATE (cvarname(nvars),  cvarname2(nvars) ,spval(nvars) )
  ALLOCATE (typvar(nvars), typvar2(nvars) )
  ALLOCATE (id_var(nvars),ipk(nvars),id_varout(nvars), id_varout2(nvars)  )

  cvarname(:)=getvarname(cfile,nvars,typvar)

  DO jvar = 1, nvars
     ! variables that will not be computed or stored are named 'none'
     IF (cvarname(jvar)  /= 'vozocrtx' .AND. &
          cvarname(jvar) /= 'vomecrty' .AND. &
          cvarname(jvar) /= 'vovecrtz' .AND. &
          cvarname(jvar) /= 'sossheig' ) THEN
          cvarname2(jvar) ='none'
     ELSE
        cvarname2(jvar)=TRIM(cvarname(jvar))//'_sqd'
        typvar2(jvar)%name =  TRIM(typvar(jvar)%name)//'_sqd'           ! name
        typvar2(jvar)%units = '('//TRIM(typvar(jvar)%units)//')^2'      ! unit
        typvar2(jvar)%missing_value = typvar(jvar)%missing_value        ! missing_value
        typvar2(jvar)%valid_min = 0.                                    ! valid_min = zero
        typvar2(jvar)%valid_max =  typvar(jvar)%valid_max**2            ! valid_max *valid_max
        typvar2(jvar)%long_name =TRIM(typvar(jvar)%long_name)//'_Squared'   !
        typvar2(jvar)%short_name = TRIM(typvar(jvar)%short_name)//'_sqd'     !
        typvar2(jvar)%online_operation = TRIM(typvar(jvar)%online_operation)
        typvar2(jvar)%axis = TRIM(typvar(jvar)%axis)

     END IF
  END DO

  id_var(:)  = (/(jv, jv=1,nvars)/)
  ! ipk gives the number of level or 0 if not a T[Z]YX  variable
  ipk(:)     = getipk (cfile,nvars)
  WHERE( ipk == 0 ) cvarname='none'
  typvar(:)%name=cvarname
  typvar2(:)%name=cvarname2
  ! get missing_value attribute
  spval(:) = 0.
  DO jvar=1,nvars
    spval(jvar) = getatt( cfile,cvarname(jvar),'missing_value')
  ENDDO

  ! create output fileset
  cfileout='cdfmoy.nc'
  cfileout2='cdfmoy2.nc'
  ! create output file taking the sizes in cfile

  ncout =create(cfileout, cfile,npiglo,npjglo,npk)
  ncout2=create(cfileout2,cfile,npiglo,npjglo,npk)

  ierr= createvar(ncout , typvar,  nvars, ipk, id_varout )
  ierr= createvar(ncout2, typvar2, nvars, ipk, id_varout2)

  ierr= putheadervar(ncout , cfile, npiglo, npjglo, npk)
  ierr= putheadervar(ncout2, cfile, npiglo, npjglo, npk)

  DO jvar = 1,nvars
     IF (cvarname(jvar) == 'nav_lon' .OR. &
          cvarname(jvar) == 'nav_lat' .OR. &
          cvarname(jvar) == 'none'  ) THEN
        ! skip these variable
     ELSE
        PRINT *,' Working with ', TRIM(cvarname(jvar)), ipk(jvar)
        DO jk = 1, ipk(jvar)
           PRINT *,'level ',jk
           tab(:,:) = 0.d0 ; tab2(:,:) = 0.d0 ; total_time = 0.
           DO jt = 1, narg
              IF (jk == 1 .AND. jvar == nvars )  THEN
                 tim=getvar1d(cfile,'time_counter',1)
                 total_time = total_time + tim(1)
              END IF
              CALL getarg (jt, cfile)
              v2d(:,:)= getvar(cfile, cvarname(jvar), jk ,npiglo, npjglo )
              WHERE(v2d /= spval(jvar) )
                 tab(:,:)  = tab(:,:) + v2d(:,:)
              ELSEWHERE
                 tab(:,:) = spval(jvar)
              END WHERE
              IF (cvarname2(jvar) /= 'none' ) THEN
                 WHERE( v2d /= spval(jvar) )
                    tab2(:,:) = tab2(:,:) + v2d(:,:)*v2d(:,:)
                 ELSEWHERE
                    tab2(:,:) = spval(jvar)
                 ENDWHERE
              END IF
           END DO
           ! finish with level jk ; compute mean 
           WHERE( tab /= spval(jvar) )
              rmean(:,:) = tab(:,:)/narg
           ELSEWHERE
              rmean(:,:) = spval(jvar)
           END WHERE
           IF (cvarname2(jvar) /= 'none' ) THEN
              WHERE (tab2 /= spval(jvar) )
                 rmean2(:,:) = tab2(:,:)/narg
              ELSEWHERE
                 rmean2(:,:) = spval(jvar)
              END WHERE
           END IF

           ! store variable on outputfile
           ierr = putvar(ncout, id_varout(jvar) ,rmean, jk, npiglo, npjglo)
           IF (cvarname2(jvar) /= 'none' ) ierr = putvar(ncout2,id_varout2(jvar),rmean2, jk,npiglo, npjglo)
           IF (jk == 1 .AND. jvar == nvars )  THEN
              timean(1)= total_time/narg
              ierr=putvar1d(ncout,timean,1,'T')
              ierr=putvar1d(ncout2,timean,1,'T')
           END IF
        END DO  ! loop to next level
     END IF
  END DO ! loop to next var in file

  istatus = closeout(ncout)
  istatus = closeout(ncout2)


END PROGRAM cdfmoy_sp

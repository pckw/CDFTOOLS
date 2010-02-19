PROGRAM cdfclip
  !!-----------------------------------------------------------------------
  !!                 ***  PROGRAM cdfclip  ***
  !!
  !!  **  Purpose: same functionality than ncks but without changing the order of the dim/variables
  !!  
  !!  **  Method: read zoomed area on the command line ( imin imax jmin jmax)
  !!              read the sub zome
  !!              write the subzone
  !!
  !! history :
  !!     Original code :   J.M. Molines (Feb 2007)
  !!-----------------------------------------------------------------------
  !!  $Rev$
  !!  $Date$
  !!  $Id$
  !!--------------------------------------------------------------
  !!
  USE cdfio 

  IMPLICIT NONE
  INTEGER   :: jk,jt,jvar, jv                               !: dummy loop index
  INTEGER   :: k1, k2, ik
  INTEGER   :: ierr                                         !: working integer
  INTEGER   :: imin, imax, jmin, jmax, kmin=-9999, kmax=-9999
  INTEGER   :: narg, iargc , jarg                           !: 
  INTEGER   :: npiglo,npjglo, npk, npkk,nt                  !: size of the domain
  INTEGER   ::  nvars                                       !: Number of variables in a file
  INTEGER , DIMENSION(:), ALLOCATABLE :: id_var , &         !: arrays of var id's
       &                             ipk ,ipkk  , &         !: arrays of vertical level for each var
       &                             id_varout , ndim
  REAL(KIND=8), DIMENSION (:,:), ALLOCATABLE :: tab  !: Arrays for cumulated values
  REAL(KIND=8)                               :: total_time
  REAL(KIND=4), DIMENSION (:,:), ALLOCATABLE :: v2d ,rlon, rlat, v2dxz, v2dyz, zxz, zyz
  REAL(KIND=4), DIMENSION(:), ALLOCATABLE    :: depg, dep
  REAL(KIND=4), DIMENSION(:), ALLOCATABLE    :: timean, tim

  CHARACTER(LEN=256) :: cfile ,cfileout                         !: file name
  CHARACTER(LEN=256) ::  cdep, cdum
  CHARACTER(LEN=256) ,DIMENSION(:), ALLOCATABLE:: cvarname   !: array of var name
  CHARACTER(LEN=255) :: cglobal !: global attribute to write on output file
  
  TYPE (variable), DIMENSION(:), ALLOCATABLE :: typvar

  INTEGER    :: ncout
  INTEGER    :: istatus
  LOGICAL :: lzonal=.false. , lmeridian=.false.
   
  !!

  !!  Read command line
  narg= iargc()
  IF ( narg == 0 ) THEN
     PRINT *,' Usage : cdfclip -f file -zoom imin imax jmin jmax [kmin kmax] '
     PRINT *,'    if imin==imax then assume a meridional section'
     PRINT *,'    if jmin==jmax then assume a zonal section'
     PRINT *,'    if [kmin kmax] (optional) are not specified the whole water colums is specified '
     STOP
  ENDIF
  !!
  jarg=1 
  DO WHILE (jarg < narg )
    CALL getarg (jarg, cdum)
    SELECT CASE ( cdum)
    CASE ('-f' )
       jarg=jarg+1 ; CALL getarg(jarg,cdum) ; cfile=cdum
    CASE ('-zoom')
       jarg=jarg+1 ; CALL getarg(jarg,cdum) ; READ(cdum,*) imin
       jarg=jarg+1 ; CALL getarg(jarg,cdum) ; READ(cdum,*) imax
       jarg=jarg+1 ; CALL getarg(jarg,cdum) ; READ(cdum,*) jmin
       jarg=jarg+1 ; CALL getarg(jarg,cdum) ; READ(cdum,*) jmax
       IF ( narg == 9 ) THEN  ! there are kmin kmax optional arguments
         jarg=jarg+1 ; CALL getarg(jarg,cdum) ; READ(cdum,*) kmin
         jarg=jarg+1 ; CALL getarg(jarg,cdum) ; READ(cdum,*) kmax
       ENDIF
    CASE DEFAULT
       PRINT *,' Unknown option :', TRIM(cdum) ; STOP
    END SELECT
    jarg=jarg+1
  ENDDO
  IF ( kmin > 0 ) THEN
   WRITE(cglobal,'(a,a,a,6i5)') 'cdfclip -f ',TRIM(cfile),' -zoom ',imin,imax,jmin,jmax, kmin, kmax
  ELSE
   WRITE(cglobal,'(a,a,a,4i5)') 'cdfclip -f ',TRIM(cfile),' -zoom ',imin,imax,jmin,jmax
  ENDIF

  IF ( imin == imax ) THEN ; lmeridian=.true.; print *,' Meridional section ' ; ENDIF
  IF ( jmin == jmax ) THEN ; lzonal=.true. ; print *,' Zonal section ' ; ENDIF

  IF (imax < imin ) THEN ! we assume that this is the case when we cross the periodic line in orca (Indian ocean)
    npiglo= getdim (cfile,'x')
    npiglo=imax+(npiglo-imin) -1
  ELSE
    npiglo= imax-imin+1
  ENDIF

  npjglo= jmax-jmin+1

  ! look for possible name for vertical dim                       :
  npk   = getdim (cfile,'depth',cdtrue=cdep, kstatus=istatus)     ! depthxxx
  print *,'ist',istatus,'depth'
  IF (istatus /= 0 ) THEN
     npk   = getdim (cfile,'z',cdtrue=cdep,kstatus=istatus)       ! zxxx
     print *,'ist',istatus,'z'
     IF (istatus /= 0 ) THEN
       npk   = getdim (cfile,'sigma',cdtrue=cdep,kstatus=istatus) ! sigmaxxx
      print *,'ist',istatus,'sigma'
      IF (istatus /= 0 ) THEN
         PRINT *,' assume file with no depth'
         IF ( kmin > 0 ) THEN
           PRINT *,' You cannot specify limits on k level !' ; STOP
         ENDIF
         npk=0  ! means no dim level in file (implicitly 1 level)
      ENDIF
     ENDIF
  ENDIF

  ! replace flag value (-9999) by standard value (no kmin kmax specified = whole column)
  IF ( kmin < 0 ) kmin = 1
  IF ( kmax < 0 ) kmax = npk
  npkk = kmax - kmin +1   ! number of extracted levels. If no level in file, it is 0: 0 -1 + 1 !
  IF (npk == 0 ) kmax = 1
  nt     = getdim(cfile,'time_counter')
  PRINT *, 'npiglo=', npiglo
  PRINT *, 'npjglo=', npjglo
  PRINT *, 'npk   =', npk ,' npkk  =', npkk
  PRINT *, 'nt    =', nt

  IF (npkk > npk ) THEN
   PRINT *,' It seems that you want levels that are not represented '
   PRINT *,' in any of the variables that are in the file ',TRIM(cfile)
   STOP
  ENDIF

  ALLOCATE( v2d(npiglo,npjglo),rlon(npiglo,npjglo), rlat(npiglo,npjglo), depg(npk) , dep(npkk))
  ALLOCATE( zxz(npiglo,1), zyz(1,npjglo) )
  ALLOCATE( timean(nt), tim(nt) )

  nvars = getnvar(cfile)
  PRINT *,' nvars =', nvars

  ALLOCATE (cvarname(nvars),ndim(nvars) )
  ALLOCATE (typvar(nvars))
  ALLOCATE (id_var(nvars),ipk(nvars),id_varout(nvars),ipkk(nvars))

  rlon=getvar(cfile,'nav_lon',1,npiglo,npjglo,kimin=imin,kjmin=jmin)
  rlat=getvar(cfile,'nav_lat',1,npiglo,npjglo,kimin=imin,kjmin=jmin)

  IF ( npk /= 0 ) THEN
    depg=getvar1d(cfile,cdep,npk)
    dep(:)=depg(kmin:kmax)  
  ENDIF

  ! get list of variable names and collect attributes in typvar (optional)
  cvarname(:)=getvarname(cfile,nvars,typvar)

  ! save variable dimension in ndim
  !  1 = either time or depth : noclip
  !  2 = nav_lon, nav_lat
  !  3 = X,Y,T  or X,Y,Z   <-- need to fix the ambiguity ...
  !  4 = X,Y,Z,T
  DO jvar=1,nvars
      ndim(jvar) = getvdim(cfile,cvarname(jvar)) + 1   !  we add 1 because vdim is dim - 1 ...
  END DO

  id_var(:)  = (/(jv, jv=1,nvars)/)
  ! ipk gives the number of level or 0 if not a T[Z]YX  variable
    
    ipk(:)     = getipk (cfile,nvars,cdep=cdep)
    ipk(:) = MIN ( ipk , kmax )            ! reduce max depth to the required maximum
    ipkk(:)= MAX( 0 , ipk(:) - kmin + 1 )  ! for output variable. For 2D input var, 
                                           ! ipkk is set to 0 if kmin > 1 ... OK ? 
    WHERE( ipkk == 0 ) cvarname='none'
  typvar(:)%name=cvarname

  ! create output fileset
  cfileout='cdfclip.nc'
  ! create output file taking the sizes in cfile

  ncout =create(cfileout, cfile,npiglo,npjglo,npkk,cdep=cdep)
  ierr= createvar(ncout , typvar,  nvars, ipkk, id_varout,cdglobal=cglobal)
  ierr= putheadervar(ncout , cfile, npiglo, npjglo, npkk,pnavlon=rlon, pnavlat=rlat,pdep=dep,cdep=cdep)

  DO jvar = 1,nvars
      ! skip dimension variables (already done when creating the output file)
      k1=MAX(1,kmin) ; k2=ipk(jvar)
     SELECT CASE (cvarname(jvar) )
      CASE ('none' )
          ! skip
      CASE DEFAULT
            IF ( lzonal ) THEN
              ALLOCATE( v2dxz(npiglo,ipk(jvar)) )
              print *, TRIM(cvarname(jvar)), jmin,npiglo, ipk(jvar), imin
              DO jt=1,nt
              v2dxz=getvarxz(cfile,cvarname(jvar),jmin,npiglo,ipk(jvar), kimin=imin,kkmin=1,ktime=jt)
              DO jk=k1,k2
               ik = jk - k1 + 1 
               zxz(:,1)=v2dxz(:,jk)
               ierr=putvar(ncout,id_varout(jvar),zxz,ik,npiglo,1,ktime=jt)
              ENDDO
              ENDDO
              DEALLOCATE ( v2dxz )
            ELSEIF (lmeridian) THEN
              ALLOCATE(  v2dyz(npjglo,ipk(jvar)) )
              print *, TRIM(cvarname(jvar)), imin,npjglo, ipk(jvar), jmin
              DO jt=1,nt
              v2dyz=getvaryz(cfile,cvarname(jvar),imin,npjglo,ipk(jvar),kjmin=jmin,kkmin=1,ktime=jt)
              DO jk=k1, k2
               ik = jk - k1 + 1 
               zyz(1,:)=v2dyz(:,jk)
               ierr=putvar(ncout,id_varout(jvar),zyz,ik,1,npjglo,ktime=jt)
              ENDDO
              ENDDO
              DEALLOCATE ( v2dyz )
            ELSE
             DO jt = 1, nt
             DO jk=k1,k2
              ik = jk - k1 + 1
              v2d=getvar(cfile,cvarname(jvar),jk,npiglo,npjglo,kimin=imin,kjmin=jmin,ktime=jt)
              ierr=putvar(ncout,id_varout(jvar),v2d,ik,npiglo,npjglo,ktime=jt)
             ENDDO
             ENDDO
            ENDIF
      END SELECT
  END DO ! loop to next var in file
  timean=getvar1d(cfile,'time_counter',nt)
  ierr=putvar1d(ncout,timean,nt,'T')

  istatus = closeout(ncout)


END PROGRAM cdfclip
 MODULE cdfio
  !!======================================================================
  !!                     ***  MODULE  cdfio  ***
  !! Implement all I/O related to netcdf in CDFTOOLS
  !!=====================================================================
  !! History : 2.1 : 2005  : J.M. Molines   : Original code
  !!               : 2009  : R. Dussin      : add putvar_0d function
  !!           3.0 : 12/2010 : J.M. Molines : Doctor + Licence     
  !! Modified: 3.0 : 08/2011 : P.   Mathiot : Add chkvar function           
  !!----------------------------------------------------------------------

  !!----------------------------------------------------------------------
  !!   routines      : description
  !! .............................
  !!   ERR_HDL       : Error Handler routine to catch netcdf errors
  !!   gettimeseries : print a 2 column array (time, variable) for a given
  !!                   file, variable and depth
  !!
  !!   functions     : description
  !! .............................
  !!   chkfile       : check the existence of a file
  !!   chkvar        : check the existence of a variable in a file
  !!   closeout      : close output file
  !!   copyatt       : copy attributes from a file taken as model
  !!   create        : create a netcdf data set
  !!   createvar     : create netcdf variables in a new data set
  !!   cvaratt       : change some var attributes
  !!   edatt_char    : edit attributes of char type
  !!   edatt_r4      : edit attributes of float type
  !!   getatt        : get attributes of a variable
  !!   getdim        : return the value of the dimension passed as argument
  !!   getipk        : get the vertical dimension of the variable
  !!   getnvar       : get the number of variable in a file
  !!   getspval      : get spval of a given variable
  !!   getvar1d      : read 1D variable (eg depth, time_counter) from a file
  !!   getvaratt     : read variable attributes
  !!   getvar        : read the variable
  !!   getvare3      : read e3 type variable
  !!   getvarid      : get the varid of a variable in a file
  !!   getvarname    : get the name of a variable, according to its varid
  !!   getvarxz      : get a x-z slice of 3D data
  !!   getvaryz      : get a y-z slice of 3D data
  !!   getvdim       : get the number of dim of a variable
  !!   ncopen        : open a netcdf file and return its ncid
  !!   putatt        : write variable attribute
  !!   putheadervar  : write header variables such as nav_lon, nav_lat etc ... from a file taken
  !!                 : as template
  !!   putvar0d      : write a 0d variable (constant)
  !!   putvar1d4     : write a 1d variable
  !!   putvari2      : write a 2d Integer*2 variable
  !!   putvarr4      : write a 2d Real*4 variable
  !!   putvarr8      : write a 2d Real*8 variable
  !!   putvarzo      : write a zonally integrated/mean field
  !!   reputvarr4    : re-write a real*4 variable
  !!   reputvar1d4   : re-write a real*4 1d variable 
  !!------------------------------------------------------------------------------------------------------
  USE netcdf        
  USE modcdfnames

  IMPLICIT NONE

  PRIVATE 

  INTEGER(KIND=4) :: nid_x, nid_y, nid_z, nid_t, nid_lat, nid_lon, nid_dep, nid_tim
  LOGICAL         :: l_mbathy=.false.
  INTEGER(KIND=4), DIMENSION(:,:), ALLOCATABLE :: mbathy         !: for reading e3._ps in nemo3.x
  REAL(KIND=4),    DIMENSION(:,:), ALLOCATABLE :: e3t_ps, e3w_ps !: for reading e3._ps in nemo3.x
  REAL(KIND=4),    DIMENSION(:),   ALLOCATABLE :: e3t_0, e3w_0   !: for readinf e3._ps in nemo3.x

  TYPE, PUBLIC ::   variable 
     CHARACTER(LEN=256) :: cname             !# variable name
     CHARACTER(LEN=256) :: cunits            !# variable unit
     REAL(KIND=4)       :: rmissing_value    !# variable missing value or spval
     REAL(KIND=4)       :: valid_min         !# valid minimum
     REAL(KIND=4)       :: valid_max         !# valid maximum
     REAL(KIND=4)       :: scale_factor=1.   !# scale factor
     REAL(KIND=4)       :: add_offset=0.     !# add offset
     REAL(KIND=4)       :: savelog10=0.      !# flag for log10 transform
     INTEGER(KIND=4)    :: iwght=1           !# weight of the variable for cdfmoy_weighted
     CHARACTER(LEN=256) :: clong_name        !# Long Name of the variable
     CHARACTER(LEN=256) :: cshort_name       !# short name of the variable
     CHARACTER(LEN=256) :: conline_operation !# ???
     CHARACTER(LEN=256) :: caxis             !# string defining the dim of the variable
     CHARACTER(LEN=256) :: cprecision='r4'   !# possible values are i2, r4, r8
  END TYPE variable

  INTERFACE putvar
     MODULE PROCEDURE putvarr8, putvarr4, putvari2, putvarzo, reputvarr4
  END INTERFACE

  INTERFACE putvar1d   
     MODULE PROCEDURE putvar1d4, reputvar1d4
  END INTERFACE

  INTERFACE putvar0d   
     MODULE PROCEDURE putvar0dt, putvar0ds
  END INTERFACE

  INTERFACE atted
     MODULE PROCEDURE atted_char, atted_r4
  END INTERFACE

  PUBLIC :: chkfile, chkvar
  PUBLIC :: copyatt, create, createvar, getvaratt, cvaratt
  PUBLIC :: putatt, putheadervar, putvar, putvar1d, putvar0d, atted
  PUBLIC :: getatt, getdim, getvdim, getipk, getnvar, getvarname, getvarid, getspval
  PUBLIC :: getvar, getvarxz, getvaryz, getvar1d, getvare3
  PUBLIC :: gettimeseries
  PUBLIC :: closeout, ncopen
  PUBLIC :: ERR_HDL

  !!----------------------------------------------------------------------
  !! CDFTOOLS_3.0 , MEOM 2011
  !! $Id$
  !! Copyright (c) 2010, J.-M. Molines
  !! Software governed by the CeCILL licence (Licence/CDFTOOLSCeCILL.txt)
  !!----------------------------------------------------------------------

CONTAINS

  INTEGER(KIND=4) FUNCTION copyatt (cdvar, kidvar, kcin, kcout)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION copyatt  ***
    !!
    !! ** Purpose :   Copy attributes for variable cdvar, which have id 
    !!                kidvar in kcout, from file id kcin
    !!
    !! ** Method  :   Use NF90_COPY_ATT
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*), INTENT(in) :: cdvar
    INTEGER(KIND=4),  INTENT(in) :: kidvar, kcin, kcout

    INTEGER(KIND=4)    :: ja
    INTEGER(KIND=4)    :: istatus, idvar, iatt
    CHARACTER(LEN=256) :: clatt
    !!----------------------------------------------------------------------
    IF ( kcin /= -9999) THEN    ! there is a reference file open
       istatus = NF90_INQ_VARID(kcin, cdvar, idvar)
       istatus = NF90_INQUIRE_VARIABLE(kcin, idvar, natts=iatt)
       DO ja = 1, iatt
          istatus = NF90_INQ_ATTNAME(kcin,idvar,ja,clatt)
          istatus = NF90_COPY_ATT(kcin,idvar,clatt,kcout,kidvar)
       END DO
    ELSE                        ! no reference file
       SELECT CASE (TRIM(cdvar) )
       CASE ('nav_lon' )
          istatus=NF90_PUT_ATT(kcout, kidvar, 'units', 'degrees_east')
          istatus=NF90_PUT_ATT(kcout, kidvar, 'valid_min', -180.)
          istatus=NF90_PUT_ATT(kcout, kidvar, 'valid_max', 180.)
          istatus=NF90_PUT_ATT(kcout, kidvar, 'long_name', 'Longitude')
          istatus=NF90_PUT_ATT(kcout, kidvar, 'nav_model', 'Default grid')
       CASE ('nav_lat' )
          istatus=NF90_PUT_ATT(kcout, kidvar, 'units', 'degrees_north')
          istatus=NF90_PUT_ATT(kcout, kidvar, 'valid_min', -90.)
          istatus=NF90_PUT_ATT(kcout, kidvar, 'valid_max', 90.)
          istatus=NF90_PUT_ATT(kcout, kidvar, 'long_name', 'Latitude')
          istatus=NF90_PUT_ATT(kcout, kidvar, 'nav_model', 'Default grid')
       CASE ('time_counter' )
          istatus=NF90_PUT_ATT(kcout, kidvar, 'calendar', 'gregorian')
          istatus=NF90_PUT_ATT(kcout, kidvar, 'units', 'seconds since 0006-01-01 00:00:00')
          istatus=NF90_PUT_ATT(kcout, kidvar, 'time_origin', '0001-JAN-01 00:00:00')
          istatus=NF90_PUT_ATT(kcout, kidvar, 'title', 'Time')
          istatus=NF90_PUT_ATT(kcout, kidvar, 'long_name', 'Time axis')
       CASE ('deptht', 'depthu' ,'depthv' , 'depthw', 'dep')
          istatus=NF90_PUT_ATT(kcout, kidvar, 'units', 'm')
          istatus=NF90_PUT_ATT(kcout, kidvar, 'positive', 'unknown')
          istatus=NF90_PUT_ATT(kcout, kidvar, 'valid_min', 0.)
          istatus=NF90_PUT_ATT(kcout, kidvar, 'valid_max', 5875.)
          istatus=NF90_PUT_ATT(kcout, kidvar, 'title', TRIM(cdvar))
          istatus=NF90_PUT_ATT(kcout, kidvar, 'long_name', 'Vertical Levels')
       CASE ('sigma')
          istatus=NF90_PUT_ATT(kcout, kidvar, 'units', 'kg/m3')
          istatus=NF90_PUT_ATT(kcout, kidvar, 'positive', 'unknown')
          istatus=NF90_PUT_ATT(kcout, kidvar, 'valid_min', 0.)
          istatus=NF90_PUT_ATT(kcout, kidvar, 'valid_max', 40.)
          istatus=NF90_PUT_ATT(kcout, kidvar, 'title', TRIM(cdvar))
          istatus=NF90_PUT_ATT(kcout, kidvar, 'long_name', 'Sigma bin limits')
       END SELECT
    ENDIF

    copyatt = istatus
  END FUNCTION copyatt


  INTEGER(KIND=4) FUNCTION create( cdfile, cdfilref ,kx,ky,kz ,cdep, cdepvar)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION create  ***
    !!
    !! ** Purpose : Create the file, and creates dimensions, and copy attributes 
    !!              from a cdilref reference file (for the nav_lon, nav_lat etc ...)
    !!              If optional cdep given : take as depth variable name instead of 
    !!              cdfilref. Return the ncid of the created file, and leave it open
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*),           INTENT(in) :: cdfile, cdfilref ! input file and reference file
    INTEGER(KIND=4),            INTENT(in) :: kx, ky, kz       ! dimension of the variable
    CHARACTER(LEN=*), OPTIONAL, INTENT(in) :: cdep    ! name of vertical dim name if not standard
    CHARACTER(LEN=*), OPTIONAL, INTENT(in) :: cdepvar ! name of vertical var name if it differs
                                                      ! from vertical dimension name
  
    INTEGER(KIND=4)               :: istatus, icout, incid, idum
    INTEGER(KIND=4) ,DIMENSION(4) :: invdim
    CHARACTER(LEN=256)            :: cldep, cldepref, cldepvar
    !!----------------------------------------------------------------------
    istatus = NF90_CREATE(cdfile,cmode=or(NF90_CLOBBER,NF90_64BIT_OFFSET), ncid=icout)
    istatus = NF90_DEF_DIM(icout, cn_x, kx, nid_x)
    istatus = NF90_DEF_DIM(icout, cn_y, ky, nid_y)

    IF ( kz /= 0 ) THEN
       ! try to find out the name I will use for depth dimension in the new file ...
       IF (PRESENT (cdep) ) THEN
          cldep = cdep
          idum=getdim(cdfilref,cldep,cldepref)   ! look for depth dimension name in ref file
         IF (cldepref =='unknown' ) cldepref=cdep
       ELSE 
          idum=getdim(cdfilref,cn_z,cldep   )   ! look for depth dimension name in ref file
          cldepref=cldep
       ENDIF
       cldepvar=cldep
       istatus = NF90_DEF_DIM(icout,TRIM(cldep),kz, nid_z)
       IF (PRESENT (cdepvar) ) THEN
         cldepvar=cdepvar
       ENDIF
    ENDIF


    istatus = NF90_DEF_DIM(icout,cn_t,NF90_UNLIMITED, nid_t)

    invdim(1) = nid_x ; invdim(2) = nid_y ; invdim(3) = nid_z ; invdim(4) = nid_t

    ! Open reference file if any,  otherwise set ncid to flag value (for copy att)
    IF ( TRIM(cdfilref) /= 'none' ) THEN
       istatus = NF90_OPEN(cdfilref,NF90_NOWRITE,incid)
    ELSE
       incid = -9999
    ENDIF

    ! define variables and copy attributes
    istatus = NF90_DEF_VAR(icout,cn_vlon2d,NF90_FLOAT,(/nid_x, nid_y/), nid_lon)
    istatus = copyatt(cn_vlon2d, nid_lon,incid,icout)
    istatus = NF90_DEF_VAR(icout,cn_vlat2d,NF90_FLOAT,(/nid_x, nid_y/), nid_lat)
    istatus = copyatt(cn_vlat2d, nid_lat,incid,icout)
    IF ( kz /= 0 ) THEN
       istatus = NF90_DEF_VAR(icout,TRIM(cldepvar),NF90_FLOAT,(/nid_z/), nid_dep)
       ! JMM bug fix : if cdep present, then chose attribute from cldepref
       istatus = copyatt(TRIM(cldepvar), nid_dep,incid,icout)
    ENDIF

    istatus = NF90_DEF_VAR(icout,cn_vtimec,NF90_FLOAT,(/nid_t/), nid_tim)
    istatus = copyatt(cn_vtimec, nid_tim,incid,icout)

    istatus = NF90_CLOSE(incid)

    create=icout
  END FUNCTION create


  INTEGER(KIND=4) FUNCTION createvar(kout, sdtyvar, kvar, kpk, kidvo, cdglobal)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION createvar  ***
    !!
    !! ** Purpose :  Create kvar  variables cdvar(:), in file id kout,
    !!
    !! ** Method  : INPUT:
    !!                 kout  = ncid of output file
    !!                 cdvar = array of name of variables
    !!                 kvar  = number of variables to create
    !!                 kpk   = number of vertical dimensions foreach variable
    !!             OUTPUT:
    !!                 kidvo = arrays with the varid of the variables just created.
    !!----------------------------------------------------------------------
    INTEGER(KIND=4),                  INTENT(in) :: kout    ! ncid of output file
    TYPE (variable), DIMENSION(kvar) ,INTENT(in) :: sdtyvar ! variable structure
    INTEGER(KIND=4),                  INTENT(in) :: kvar    ! number of variable
    INTEGER(KIND=4), DIMENSION(kvar), INTENT(in) :: kpk     ! number of level/var
    INTEGER(KIND=4), DIMENSION(kvar), INTENT(out):: kidvo   ! varid's of output var
    CHARACTER(LEN=*), OPTIONAL,       INTENT(in) :: cdglobal! Global Attribute

    INTEGER(KIND=4)               :: jv             ! dummy loop index
    INTEGER(KIND=4)               :: idims, istatus 
    INTEGER(KIND=4), DIMENSION(4) :: iidims
    INTEGER(KIND=4)               :: iprecision
    !!----------------------------------------------------------------------
    DO jv = 1, kvar
       ! Create variables whose name is not 'none'
       IF ( sdtyvar(jv)%cname /= 'none' ) THEN
          IF (kpk(jv) == 1 ) THEN
             idims=3
             iidims(1) = nid_x ; iidims(2) = nid_y ; iidims(3) = nid_t
          ELSE IF (kpk(jv) > 1 ) THEN
             idims=4
             iidims(1) = nid_x ; iidims(2) = nid_y ; iidims(3) = nid_z ; iidims(4) = nid_t
          ELSE
             PRINT *,' ERROR: ipk = ',kpk(jv), jv , sdtyvar(jv)%cname
             STOP
          ENDIF
    
          SELECT CASE ( sdtyvar(jv)%cprecision ) ! check the precision of the variable to create
          !
          CASE ( 'r8' ) ; iprecision = NF90_DOUBLE
          !
          CASE ( 'i2' ) ; iprecision = NF90_SHORT
          !
          CASE ( 'by' ) ; iprecision = NF90_BYTE
          !
          CASE DEFAULT  ! r4
                          iprecision = NF90_FLOAT
             IF ( sdtyvar(jv)%scale_factor /= 1. .OR. sdtyvar(jv)%add_offset /= 0. ) THEN
                          iprecision = NF90_SHORT
             ENDIF
          END SELECT

          istatus = NF90_DEF_VAR(kout, sdtyvar(jv)%cname, iprecision, iidims(1:idims) ,kidvo(jv) )

          ! add attributes
          istatus = putatt(sdtyvar(jv), kout, kidvo(jv), cdglobal=cdglobal)
          createvar=istatus
       ENDIF
    END DO
    istatus = NF90_ENDDEF(kout)

  END FUNCTION createvar


  FUNCTION getvarid( cdfile, knvars )
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION getvarid  ***
    !!
    !! ** Purpose :  return a real array with the nvar variable id 
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*),       INTENT(in) :: cdfile
    INTEGER(KIND=4),        INTENT(in) :: knvars    ! Number of variables in cdfile
    INTEGER(KIND=4), DIMENSION(knvars) :: getvarid  ! return function

    INTEGER(KIND=4)                       :: jv     ! dummy loop index
    CHARACTER(LEN=256), DIMENSION(knvars) :: cdvar
    INTEGER(KIND=4)                       :: incid
    INTEGER(KIND=4)                       :: istatus
    !!----------------------------------------------------------------------
    istatus = NF90_OPEN(cdfile, NF90_NOWRITE, incid)
    DO jv = 1, knvars
       istatus = NF90_INQUIRE_VARIABLE(incid, jv, cdvar(jv) )
       istatus = NF90_INQ_VARID(incid, cdvar(jv), getvarid(jv))
    ENDDO
    istatus=NF90_CLOSE(incid)

  END FUNCTION getvarid


  INTEGER(KIND=4) FUNCTION getvaratt (cdfile, cdvar, cdunits, pmissing_value, cdlong_name, cdshort_name)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION getvaratt  ***
    !!
    !! ** Purpose : Get specific attributes for a variable (units, missing_value, 
    !!              long_name, short_name
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=256), INTENT(in)  :: cdfile, cdvar
    REAL(KIND=4), INTENT(out)       :: pmissing_value
    CHARACTER(LEN=256), INTENT(out) :: cdunits, cdlong_name, cdshort_name

    INTEGER(KIND=4) :: istatus
    INTEGER(KIND=4) :: incid, ivarid
    !!----------------------------------------------------------------------
    istatus = NF90_OPEN(cdfile, NF90_NOWRITE, incid)
    istatus = NF90_INQ_VARID(incid, cdvar, ivarid)

    istatus = NF90_GET_ATT(incid, ivarid, 'units',         cdunits        )
    istatus = NF90_GET_ATT(incid, ivarid, 'missing_value', pmissing_value )
    istatus = NF90_GET_ATT(incid, ivarid, 'long_name',     cdlong_name    )
    istatus = NF90_GET_ATT(incid, ivarid, 'short_name',    cdshort_name   )

    getvaratt = istatus
    istatus   = NF90_CLOSE(incid)

  END FUNCTION getvaratt


  INTEGER(KIND=4) FUNCTION cvaratt (cdfile, cdvar, cdunits, pmissing_value, cdlong_name, cdshort_name)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION cvaratt  ***
    !!
    !! ** Purpose : Change variable attributs in an existing variable
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=256), INTENT(in) :: cdfile, cdvar
    CHARACTER(LEN=256), INTENT(in) :: cdunits, cdlong_name, cdshort_name
    REAL(KIND=4),       INTENT(in) :: pmissing_value

    INTEGER(KIND=4) :: istatus
    INTEGER(KIND=4) :: incid, ivarid
    !!----------------------------------------------------------------------
    istatus = NF90_OPEN (cdfile, NF90_WRITE, incid)
    istatus = NF90_REDEF(incid)
    istatus = NF90_INQ_VARID(incid, cdvar, ivarid)

    istatus=NF90_RENAME_ATT(incid, ivarid, 'units',         cdunits        )
    istatus=NF90_PUT_ATT   (incid, ivarid, 'missing_value', pmissing_value )
    istatus=NF90_RENAME_ATT(incid, ivarid, 'long_name',     cdlong_name    )
    istatus=NF90_RENAME_ATT(incid, ivarid, 'short_name',    cdshort_name   )

    istatus=NF90_ENDDEF(incid)
    cvaratt=istatus
    istatus=NF90_CLOSE(incid)

  END FUNCTION cvaratt


  INTEGER(KIND=4) FUNCTION putatt (sdtyvar, kout, kid, cdglobal)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION putatt  ***
    !!
    !! ** Purpose : Put attribute for variable defined in the data structure 
    !!
    !!----------------------------------------------------------------------
    TYPE (variable),            INTENT(in) :: sdtyvar
    INTEGER(KIND=4),            INTENT(in) :: kout, kid
    CHARACTER(LEN=*), OPTIONAL, INTENT(in) :: cdglobal   !: global attribute
    !!----------------------------------------------------------------------
    putatt=NF90_PUT_ATT(kout,kid,'units',sdtyvar%cunits) 
    IF (putatt /= 0 ) THEN ;PRINT *, NF90_STRERROR(putatt)  ; STOP 'putatt units'; ENDIF
    putatt=NF90_PUT_ATT(kout,kid,'missing_value',sdtyvar%rmissing_value)  
    IF (putatt /= 0 ) THEN ;PRINT *, NF90_STRERROR(putatt)  ; STOP 'putatt missing value'; ENDIF
    putatt=NF90_PUT_ATT(kout,kid,'valid_min',sdtyvar%valid_min) 
    IF (putatt /= 0 ) THEN ;PRINT *, NF90_STRERROR(putatt)  ; STOP 'putatt valid_min'; ENDIF
    putatt=NF90_PUT_ATT(kout,kid,'valid_max',sdtyvar%valid_max)
    IF (putatt /= 0 ) THEN ;PRINT *, NF90_STRERROR(putatt)  ; STOP 'putatt valid_max'; ENDIF
    putatt=NF90_PUT_ATT(kout,kid,'long_name',sdtyvar%clong_name)
    IF (putatt /= 0 ) THEN ;PRINT *, NF90_STRERROR(putatt)  ; STOP 'putatt longname'; ENDIF
    putatt=NF90_PUT_ATT(kout,kid,'short_name',sdtyvar%cshort_name) 
    IF (putatt /= 0 ) THEN ;PRINT *, NF90_STRERROR(putatt)  ; STOP 'putatt short name'; ENDIF
    putatt=NF90_PUT_ATT(kout,kid,'iweight',sdtyvar%iwght) 
    IF (putatt /= 0 ) THEN ;PRINT *, NF90_STRERROR(putatt)  ; STOP 'putatt iweight'; ENDIF
    putatt=NF90_PUT_ATT(kout,kid,'online_operation',sdtyvar%conline_operation) 
    IF (putatt /= 0 ) THEN ;PRINT *, NF90_STRERROR(putatt)  ; STOP 'putatt online oper'; ENDIF
    putatt=NF90_PUT_ATT(kout,kid,'axis',sdtyvar%caxis) 
    IF (putatt /= 0 ) THEN ;PRINT *, NF90_STRERROR(putatt)  ; STOP 'putatt axis'; ENDIF

    ! Optional attributes (scale_factor, add_offset )
    putatt=NF90_PUT_ATT(kout,kid,'scale_factor',sdtyvar%scale_factor) 
    IF (putatt /= 0 ) THEN ;PRINT *, NF90_STRERROR(putatt)  ; STOP 'putatt scale fact'; ENDIF
    putatt=NF90_PUT_ATT(kout,kid,'add_offset',sdtyvar%add_offset) 
    IF (putatt /= 0 ) THEN ;PRINT *, NF90_STRERROR(putatt)  ; STOP 'putatt add offset'; ENDIF
    putatt=NF90_PUT_ATT(kout,kid,'savelog10',sdtyvar%savelog10) 
    IF (putatt /= 0 ) THEN ;PRINT *, NF90_STRERROR(putatt)  ; STOP 'putatt savelog0'; ENDIF

    ! Global attribute
    IF ( PRESENT(cdglobal) ) THEN
      putatt=NF90_PUT_ATT(kout,NF90_GLOBAL,'history',cdglobal)
      IF (putatt /= 0 ) THEN ;PRINT *, NF90_STRERROR(putatt)  ; STOP 'putatt global'; ENDIF
    ENDIF

  END FUNCTION putatt


  REAL(KIND=4) FUNCTION getatt (cdfile, cdvar, cdatt)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION getatt  ***
    !!
    !! ** Purpose : return a REAL value with the values of the
    !!              attribute cdatt for all the variable cdvar in cdfile  
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*), INTENT(in) :: cdfile  ! file name
    CHARACTER(LEN=*), INTENT(in) :: cdvar   ! var name
    CHARACTER(LEN=*), INTENT(in) :: cdatt   ! attribute name to look for

    INTEGER(KIND=4) :: istatus, jv, incid, idum
    !!----------------------------------------------------------------------
    istatus = NF90_OPEN  (cdfile, NF90_NOWRITE, incid)
    istatus = NF90_INQ_VARID(incid, cdvar, idum)

    IF ( istatus /= NF90_NOERR) PRINT *, TRIM(NF90_STRERROR(istatus)),' when looking for ',TRIM(cdvar),' in getatt.'

    istatus = NF90_GET_ATT(incid, idum, cdatt, getatt)
    IF ( istatus /= NF90_NOERR ) THEN
       PRINT *,' getatt problem :',NF90_STRERROR(istatus)
       PRINT *,' attribute :', TRIM(cdatt)
       PRINT *,' return default 0 '
       getatt=0.
    ENDIF

    istatus=NF90_CLOSE(incid)

  END FUNCTION getatt


  INTEGER(KIND=4) FUNCTION atted_char ( cdfile, cdvar, cdatt, cdvalue )
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION atted_char  ***
    !!
    !! ** Purpose : attribute editor : modify existing attribute or create
    !!              new attribute for variable cdvar in cdfile 
    !!
    !! ** Method  : just put_att after some check.
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*),  INTENT(in) :: cdfile  ! input file
    CHARACTER(LEN=*),  INTENT(in) :: cdvar   ! variable name
    CHARACTER(LEN=*),  INTENT(in) :: cdatt   ! attribute  name
    CHARACTER(LEN=*),  INTENT(in) :: cdvalue ! attribute value

    INTEGER(KIND=4)               :: incid,  istatus, idvar, ityp
    !!-------------------------------------------------------------------------
    istatus = NF90_OPEN(cdfile, NF90_WRITE, incid)
    istatus = NF90_INQ_VARID(incid, cdvar, idvar)
    IF ( istatus /= NF90_NOERR ) THEN
       PRINT *, NF90_STRERROR(istatus),' in atted ( inq_varid)'
       STOP
    ENDIF
    istatus = NF90_INQUIRE_ATTRIBUTE(incid, idvar, cdatt, xtype=ityp )
    IF ( istatus /= NF90_NOERR ) THEN
       PRINT *, ' Attribute does not exist. Create it'
       istatus = NF90_REDEF(incid)
       istatus = NF90_PUT_ATT(incid, idvar, cdatt, cdvalue)
       atted_char = istatus
    ELSE
       IF ( ityp == NF90_CHAR ) THEN
         istatus = NF90_REDEF(incid)
         istatus = NF90_PUT_ATT(incid, idvar, cdatt, cdvalue)
         atted_char = istatus
       ELSE
         PRINT *, ' Mismatch in attribute type in atted_char'
         STOP
       ENDIF
    ENDIF
    istatus=NF90_CLOSE(incid)

  END FUNCTION atted_char


  INTEGER(KIND=4) FUNCTION atted_r4 ( cdfile, cdvar, cdatt, pvalue )
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION atted_r4  ***
    !!
    !! ** Purpose : attribute editor : modify existing attribute or create
    !!              new attribute for variable cdvar in cdfile
    !!
    !! ** Method  : just put_att after some check.
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*),  INTENT(in) :: cdfile  ! input file
    CHARACTER(LEN=*),  INTENT(in) :: cdvar   ! variable name
    CHARACTER(LEN=*),  INTENT(in) :: cdatt   ! attribute  name
    REAL(KIND=4),      INTENT(in) :: pvalue  ! attribute value

    INTEGER(KIND=4)               :: incid,  istatus, idvar, ityp
    !!-------------------------------------------------------------------------
    istatus = NF90_OPEN(cdfile, NF90_WRITE, incid)
    istatus = NF90_INQ_VARID(incid, cdvar, idvar)
    IF ( istatus /= NF90_NOERR ) THEN
       PRINT *, NF90_STRERROR(istatus),' in atted ( inq_varid)'
       STOP
    ENDIF
    istatus = NF90_INQUIRE_ATTRIBUTE(incid, idvar, cdatt, xtype=ityp )
    IF ( istatus /= NF90_NOERR ) THEN
       PRINT *, ' Attribute does not exist. Create it'
       istatus = NF90_REDEF(incid)
       istatus = NF90_PUT_ATT(incid, idvar, cdatt, pvalue)
       atted_r4 = istatus
    ELSE
       IF ( ityp == NF90_FLOAT ) THEN
         istatus = NF90_REDEF(incid)
         istatus = NF90_PUT_ATT(incid, idvar, cdatt, pvalue)
         atted_r4 = istatus
       ELSE
         PRINT *, ' Mismatch in attribute type in atted_r4'
         STOP
       ENDIF
    ENDIF
    istatus=NF90_CLOSE(incid)

  END FUNCTION atted_r4


  INTEGER(KIND=4)  FUNCTION  getdim (cdfile, cdim_name, cdtrue, kstatus, ldexact)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION getdim  ***
    !!
    !! ** Purpose : Return the INTEGER value of the dimension
    !!              identified with cdim_name in cdfile 
    !!
    !! ** Method  : This function look for a dimension name that contains 
    !!              cdim_name, in cdfile. In option it returns the error 
    !!              status which can be used to make another intent, changing 
    !!              the dim name. Finally, with the last optional argument 
    !!              ldexact, exact match to cdim_name can be required.
    !!              
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*),             INTENT(in ) :: cdfile     ! File name to look at
    CHARACTER(LEN=*),             INTENT(in ) :: cdim_name  ! File name to look at
    CHARACTER(LEN=256), OPTIONAL, INTENT(out) :: cdtrue     ! full name of the read dimension
    INTEGER(KIND=4),    OPTIONAL, INTENT(out) :: kstatus    ! status of the nf inquire
    LOGICAL,            OPTIONAL, INTENT(in ) :: ldexact    ! when true look for exact cdim_name

    INTEGER(KIND=4)    :: jdim
    INTEGER(KIND=4)    :: incid, id_dim
    INTEGER(KIND=4)    :: istatus
    INTEGER(KIND=4)    :: idims
    CHARACTER(LEN=256) :: clnam
    LOGICAL            :: lexact = .false.
    !!-----------------------------------------------------------
    clnam = '-------------'

    IF ( PRESENT(kstatus) ) kstatus=0
    IF ( PRESENT(ldexact) ) lexact=ldexact
    istatus=NF90_OPEN(cdfile, NF90_NOWRITE, incid)
    IF ( istatus == NF90_NOERR ) THEN
       istatus=NF90_INQUIRE(incid, ndimensions=idims)

       IF ( lexact ) THEN
          istatus=NF90_INQ_DIMID(incid, cdim_name, id_dim)
          IF (istatus /= NF90_NOERR ) THEN
            PRINT *,NF90_STRERROR(istatus)
            PRINT *,' Exact dimension name ', TRIM(cdim_name),' not found in ',TRIM(cdfile) ; STOP
          ENDIF
          istatus=NF90_INQUIRE_DIMENSION(incid, id_dim, len=getdim)
          IF ( PRESENT(cdtrue) ) cdtrue=cdim_name
          jdim = 0
       ELSE  ! scann all dims to look for a partial match
         DO jdim = 1, idims
            istatus=NF90_INQUIRE_DIMENSION(incid, jdim, name=clnam, len=getdim)
            IF ( INDEX(clnam, TRIM(cdim_name)) /= 0 ) THEN
               IF ( PRESENT(cdtrue) ) cdtrue=clnam
               EXIT
            ENDIF
         ENDDO
       ENDIF

       IF ( jdim > idims ) THEN   ! dimension not found
          IF ( PRESENT(kstatus) ) kstatus=1    ! error send optionally to the calling program
          getdim=0
          IF ( PRESENT(cdtrue) ) cdtrue='unknown'
       ENDIF
       istatus=NF90_CLOSE(incid)
    ELSE              ! problem with the file
       IF ( PRESENT(cdtrue) ) cdtrue='unknown'
       IF ( PRESENT(kstatus) ) kstatus=1 
    ENDIF
    ! reset lexact to false for next call 
    lexact=.false.

  END FUNCTION getdim


  REAL(KIND=4) FUNCTION  getspval (cdfile, cdvar)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION getspval  ***
    !!
    !! ** Purpose : return the SPVAL value of the variable cdvar in cdfile
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*), INTENT(in) :: cdfile      ! File name to look at
    CHARACTER(LEN=*), INTENT(in) :: cdvar       ! variable name

    INTEGER(KIND=4) :: incid, id_var
    INTEGER(KIND=4) :: istatus
    !!----------------------------------------------------------------------

    istatus=NF90_OPEN      (cdfile, NF90_NOWRITE, incid )
    istatus=NF90_INQ_VARID (incid, cdvar, id_var )
    istatus=NF90_GET_ATT   (incid, id_var, "missing_value", getspval)
    istatus=NF90_CLOSE     (incid )

  END FUNCTION getspval


  INTEGER(KIND=4) FUNCTION getvdim (cdfile, cdvar)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION getvdim  ***
    !!
    !! ** Purpose : Return the number of dimensions for variable cdvar in cdfile 
    !!
    !! ** Method  : Inquire for variable cdvar in cdfile. If found,
    !!              determines the number of dimensions , assuming that variables
    !!              are either (x,y,dep,time) or (x,y,time)
    !!              If cdvar is not found, give an interactive choice for an existing
    !!              variable, cdvar is then updated to this correct name.  
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*), INTENT(in)    :: cdfile   ! File name to look at
    CHARACTER(LEN=*), INTENT(inout) :: cdvar    ! variable name to look at.

    INTEGER(KIND=4)    :: jvar
    INTEGER(KIND=4)    :: istatus, incid, id_var, ivar, idi, istatus0
    CHARACTER(LEN=256) :: clongname='long_name', clongn
    !!----------------------------------------------------------------------
    CALL ERR_HDL(NF90_OPEN(cdfile,NF90_NOWRITE,incid))

    istatus0 = NF90_INQ_VARID ( incid,cdvar,id_var)
    DO WHILE  ( istatus0 == NF90_ENOTVAR ) 
       ivar=getnvar(cdfile)
       PRINT *, 'Give the number corresponding to the variable you want to work with '
       DO jvar = 1, ivar
          clongn=''
          istatus=NF90_INQUIRE_VARIABLE (incid, jvar, cdvar, ndims=idi)
          istatus=NF90_GET_ATT (incid, jvar, clongname, clongn)
          IF (istatus /= NF90_NOERR ) clongn='unknown'
          PRINT *, jvar, ' ',TRIM(cdvar),' ',TRIM(clongn)
       ENDDO
       READ *,id_var
       istatus0=NF90_INQUIRE_VARIABLE (incid, id_var, cdvar, ndims=idi)
    ENDDO
    ! 
    CALL ERR_HDL(NF90_INQUIRE_VARIABLE (incid, id_var, cdvar, ndims=idi))
    getvdim = idi - 1
    CALL ERR_HDL (NF90_CLOSE(incid))

  END FUNCTION getvdim


  INTEGER(KIND=4) FUNCTION  getnvar (cdfile)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION getnvar  ***
    !!
    !! ** Purpose :  return the number of variables in cdfile 
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*), INTENT(in) ::  cdfile   ! file to look at

    INTEGER(KIND=4) :: incid
    INTEGER(KIND=4) :: istatus
    !!----------------------------------------------------------------------
    istatus = NF90_OPEN    (cdfile, NF90_NOWRITE, incid )
    istatus = NF90_INQUIRE (incid, nvariables = getnvar )
    istatus = NF90_CLOSE   (incid )

  END FUNCTION getnvar


  FUNCTION  getipk (cdfile,knvars,cdep)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION getipk  ***
    !!
    !! ** Purpose : Return the number of levels for all the variables
    !!              in cdfile. Return 0 if the variable in 1d.
    !!
    !! ** Method  : returns npk when 4D variables ( x,y,z,t )
    !!              returns  1  when 3D variables ( x,y,  t )
    !!              returns  0  when other ( vectors )
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*),           INTENT(in) :: cdfile   ! File to look at
    INTEGER(KIND=4),            INTENT(in) ::  knvars  ! Number of variables in cdfile
    CHARACTER(LEN=*), OPTIONAL, INTENT(in) :: cdep     ! optional depth dim name
    INTEGER(KIND=4), DIMENSION(knvars)     :: getipk   ! array (variables ) of levels

    INTEGER(KIND=4)    :: incid, ipk, jv, iipk
    INTEGER(KIND=4)    :: istatus
    CHARACTER(LEN=256) :: cldep='dep'
    !!----------------------------------------------------------------------
    istatus=NF90_OPEN(cdfile,NF90_NOWRITE,incid)

    IF (  PRESENT (cdep) ) cldep = cdep

    ! Note the very important TRIM below : if not, getdim crashes as it never find the correct dim !
    iipk = getdim(cdfile, TRIM(cldep), kstatus=istatus)

    IF ( istatus /= 0 ) THEN
       PRINT *,' getipk : vertical dim not found ...assume 1'
       iipk=1
    ENDIF

    DO jv = 1, knvars
       istatus=NF90_INQUIRE_VARIABLE(incid, jv, ndims=ipk)
       IF (ipk == 4 ) THEN
          getipk(jv) = iipk
       ELSE IF (ipk == 3 ) THEN
          getipk(jv) = 1
       ELSE
          getipk(jv) = 0
       ENDIF
    END DO

    istatus=NF90_CLOSE(incid)

  END FUNCTION getipk


  FUNCTION  getvarname (cdfile, knvars, sdtypvar)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION getvarname  ***
    !!
    !! ** Purpose : return a character array with the knvars variable
    !!              name corresponding to cdfile 
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*),          INTENT(in) :: cdfile
    INTEGER(KIND=4),           INTENT(in) :: knvars                  ! Number of variables in cdfile
    TYPE (variable),   DIMENSION (knvars) :: sdtypvar  ! Retrieve variables attribute
    CHARACTER(LEN=256), DIMENSION(knvars) :: getvarname

    INTEGER(KIND=4)    :: incid,  jv, ilen
    INTEGER(KIND=4)    :: istatus
    INTEGER(KIND=4)    :: iatt
    REAL(KIND=4)       :: zatt
    CHARACTER(LEN=256) :: cldum=''
    !!----------------------------------------------------------------------
    istatus=NF90_OPEN(cdfile,NF90_NOWRITE,incid)

    DO jv = 1, knvars
       istatus=NF90_INQUIRE_VARIABLE(incid, jv, name=getvarname(jv) )
       sdtypvar(jv)%cname=getvarname(jv)
       ! look for standard attibutes
       IF ( NF90_INQUIRE_ATTRIBUTE(incid, jv, 'units', len=ilen) == NF90_NOERR ) THEN
          istatus=NF90_GET_ATT(incid, jv, 'units', cldum(1:ilen))
          sdtypvar(jv)%cunits = TRIM(cldum)
          cldum = ''
       ELSE 
          sdtypvar(jv)%cunits = 'N/A'
       ENDIF

       IF ( NF90_INQUIRE_ATTRIBUTE(incid, jv, 'missing_value') == NF90_NOERR ) THEN
          istatus=NF90_GET_ATT(incid, jv, 'missing_value', zatt)
          sdtypvar(jv)%rmissing_value = zatt
       ELSE 
          sdtypvar(jv)%rmissing_value = 0.
       ENDIF

       IF ( NF90_INQUIRE_ATTRIBUTE(incid, jv, 'valid_min') == NF90_NOERR ) THEN
          istatus=NF90_GET_ATT(incid, jv, 'valid_min', zatt)
          sdtypvar(jv)%valid_min = zatt
       ELSE
          sdtypvar(jv)%valid_min = 0.
       ENDIF

       IF ( NF90_INQUIRE_ATTRIBUTE(incid, jv, 'valid_max') == NF90_NOERR ) THEN
          istatus=NF90_GET_ATT(incid, jv, 'valid_max', zatt)
          sdtypvar(jv)%valid_max = zatt
       ELSE
          sdtypvar(jv)%valid_max = 0.
       ENDIF

       IF ( NF90_INQUIRE_ATTRIBUTE(incid, jv, 'iweight') == NF90_NOERR ) THEN
          istatus=NF90_GET_ATT(incid, jv, 'iweight', iatt)
          sdtypvar(jv)%iwght = iatt
       ELSE
          sdtypvar(jv)%iwght = 1
       ENDIF

       IF ( NF90_INQUIRE_ATTRIBUTE(incid, jv, 'long_name', len=ilen) == NF90_NOERR ) THEN
          istatus=NF90_GET_ATT(incid, jv, 'long_name', cldum(1:ilen))
          sdtypvar(jv)%clong_name = TRIM(cldum)
          cldum = ''
       ELSE
          sdtypvar(jv)%clong_name = 'N/A'
       ENDIF

       IF ( NF90_INQUIRE_ATTRIBUTE(incid, jv, 'short_name', len=ilen) == NF90_NOERR ) THEN
          istatus=NF90_GET_ATT(incid, jv, 'short_name', cldum(1:ilen))
          sdtypvar(jv)%cshort_name = TRIM(cldum)
          cldum = ''
       ELSE
          sdtypvar(jv)%cshort_name = 'N/A'
       ENDIF

       IF ( NF90_INQUIRE_ATTRIBUTE(incid, jv, 'online_operation', len=ilen) == NF90_NOERR ) THEN
          istatus=NF90_GET_ATT(incid, jv, 'online_operation', cldum(1:ilen))
          sdtypvar(jv)%conline_operation = TRIM(cldum)
          cldum = ''
       ELSE
          sdtypvar(jv)%conline_operation = 'N/A'
       ENDIF

       IF ( NF90_INQUIRE_ATTRIBUTE(incid, jv, 'axis', len=ilen) == NF90_NOERR ) THEN
          istatus=NF90_GET_ATT(incid, jv, 'axis', cldum(1:ilen))
          sdtypvar(jv)%caxis = TRIM(cldum)
          cldum = ''
       ELSE
          sdtypvar(jv)%caxis = 'N/A'
       ENDIF

    END DO
    istatus=NF90_CLOSE(incid)

  END FUNCTION getvarname


  FUNCTION  getvar (cdfile,cdvar,klev,kpi,kpj,kimin,kjmin, ktime, ldiom)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION  getvar  ***
    !!
    !! ** Purpose : Return the 2D REAL variable cvar, from cdfile at level klev.
    !!              kpi,kpj are the horizontal size of the 2D variable
    !!
    !! ** Method  : Initially a quite straigth forward function. But with the
    !!              NEMO variation about the e3t in partial steps, I try to adapt
    !!              the code to all existing mesh_zgr format, which reduces the
    !!              readibility of the code. One my think of specific routine for
    !!              getvar (e3._ps ...)
    !!
    !!---------------------------------------------------------------------
    CHARACTER(LEN=*),          INTENT(in) :: cdfile       ! file name to work with
    CHARACTER(LEN=*),          INTENT(in) :: cdvar        ! variable name to work with
    INTEGER(KIND=4), OPTIONAL, INTENT(in) :: klev         ! Optional variable. If missing 1 is assumed
    INTEGER(KIND=4),           INTENT(in) :: kpi, kpj     ! horizontal size of the 2D variable
    INTEGER(KIND=4), OPTIONAL, INTENT(in) :: kimin, kjmin ! Optional variable. If missing 1 is assumed
    INTEGER(KIND=4), OPTIONAL, INTENT(in) :: ktime        ! Optional variable. If missing 1 is assumed
    LOGICAL,         OPTIONAL, INTENT(in) :: ldiom        ! Optional variable. If missing false is assumed
    REAL(KIND=4), DIMENSION(kpi,kpj) :: getvar            ! 2D REAL 4 holding variable field at klev

    INTEGER(KIND=4), DIMENSION(4)               :: istart, icount, inldim
    INTEGER(KIND=4)                             :: incid, id_var, id_dimunlim, inbdim
    INTEGER(KIND=4)                             :: istatus, ilev, imin, jmin
    INTEGER(KIND=4)                             :: itime, ilog, ipiglo, imax
    INTEGER(KIND=4), SAVE                       :: ii, ij, ik0, ji, jj, ik1, ik
    REAL(KIND=4)                                :: sf=1., ao=0.        !: Scale factor and add_offset
    REAL(KIND=4)                                :: spval  !: missing value
    REAL(KIND=4) , DIMENSION (:,:), ALLOCATABLE :: zend, zstart
    CHARACTER(LEN=256)                          :: clvar
    LOGICAL                                     :: lliom=.false., llperio=.false.
    LOGICAL                                     :: llog=.FALSE. , lsf=.FALSE. , lao=.FALSE.
    !!---------------------------------------------------------------------
    llperio=.false.
    IF (PRESENT(klev) ) THEN
       ilev=klev
    ELSE
       ilev=1
    ENDIF

    IF (PRESENT(kimin) ) THEN
       imin=kimin

       ipiglo=getdim(cdfile, cn_x, ldexact=.true.)
       IF (imin+kpi-1 > ipiglo ) THEN 
         llperio=.true.
         imax=kpi+1 +imin -ipiglo
       ENDIF
    ELSE
       imin=1
    ENDIF

    IF (PRESENT(kjmin) ) THEN
       jmin=kjmin
    ELSE
       jmin=1
    ENDIF

    IF (PRESENT(ktime) ) THEN
       itime=ktime
    ELSE
       itime=1
    ENDIF

    IF (PRESENT(ldiom) ) THEN
       lliom=ldiom
    ELSE
       lliom=.false.
    ENDIF

    clvar=cdvar

    ! Must reset the flags to false for every call to getvar
    llog = .FALSE.
    lsf  = .FALSE.
    lao  = .FALSE.

    CALL ERR_HDL(NF90_OPEN(cdfile,NF90_NOWRITE,incid) )

    IF ( lliom) THEN  ! try to detect if input file is a zgr IOM file, looking for e3t_0
      istatus=NF90_INQ_VARID( incid,'e3t_0', id_var)
      IF ( istatus == NF90_NOERR ) THEN
        ! iom file , change names
        ! now try to detect if it is v2 or v3, in v3, e3t_ps exist and is a 2d variable
         istatus=NF90_INQ_VARID( incid,'e3t_ps', id_var)
         IF ( istatus == NF90_NOERR ) THEN  
           ! case of NEMO_v3 zfr files
           ! look for mbathy and out it in memory, once for all
           IF ( .NOT. l_mbathy ) THEN
             PRINT *,'MESH_ZGR V3 detected'
             l_mbathy=.true.
             istatus=NF90_INQ_DIMID(incid,'x',id_var) ; istatus=NF90_INQUIRE_DIMENSION(incid,id_var, len=ii )
             istatus=NF90_INQ_DIMID(incid,'y',id_var) ; istatus=NF90_INQUIRE_DIMENSION(incid,id_var, len=ij )
             istatus=NF90_INQ_DIMID(incid,'z',id_var) ; istatus=NF90_INQUIRE_DIMENSION(incid,id_var, len=ik0)

             ALLOCATE( mbathy(ii,ij))               ! mbathy is allocated on the whole domain
             ALLOCATE( e3t_ps(ii,ij),e3w_ps(ii,ij)) ! e3._ps  are  allocated on the whole domain
             ALLOCATE( e3t_0(ik0), e3w_0(ik0) )     ! whole depth

             istatus=NF90_INQ_VARID (incid,'mbathy', id_var)
             IF ( istatus /=  NF90_NOERR ) THEN
               PRINT *, 'Problem reading mesh_zgr.nc v3 : no mbathy found !' ; STOP
             ENDIF
             istatus=NF90_GET_VAR(incid,id_var, mbathy, start=(/1,1,1/), count=(/ii,ij,1/) )
             !
             istatus=NF90_INQ_VARID (incid,'e3t_ps', id_var)
             IF ( istatus /=  NF90_NOERR ) THEN
               PRINT *, 'Problem reading mesh_zgr.nc v3 : no e3t_ps found !' ; STOP
             ENDIF
             istatus=NF90_GET_VAR(incid,id_var,e3t_ps, start=(/1,1,1/), count=(/ii,ij,1/) )
             !
             istatus=NF90_INQ_VARID (incid,'e3w_ps', id_var)
             IF ( istatus /=  NF90_NOERR ) THEN
               PRINT *, 'Problem reading mesh_zgr.nc v3 : no e3w_ps found !' ; STOP
             ENDIF
             istatus=NF90_GET_VAR(incid,id_var,e3w_ps, start=(/1,1,1/), count=(/ii,ij,1/) )
             !
             istatus=NF90_INQ_VARID (incid,'e3t_0', id_var)
             IF ( istatus /=  NF90_NOERR ) THEN
               PRINT *, 'Problem reading mesh_zgr.nc v3 : no e3t_0 found !' ; STOP
             ENDIF
             istatus=NF90_GET_VAR(incid,id_var,e3t_0, start=(/1,1/), count=(/ik0,1/) )
             !
             istatus=NF90_INQ_VARID (incid,'e3w_0', id_var)
             IF ( istatus /=  NF90_NOERR ) THEN
               PRINT *, 'Problem reading mesh_zgr.nc v3 : no e3w_0 found !' ; STOP
             ENDIF
             istatus=NF90_GET_VAR(incid,id_var,e3w_0, start=(/1,1/), count=(/ik0,1/) )
             DO ji=1,ii
                DO jj=1,ij
                   IF ( e3t_ps (ji,jj) == 0 ) e3t_ps(ji,jj)=e3t_0(mbathy(ji,jj))
                END DO
             END DO
           ENDIF
          ! zgr v3
          SELECT CASE ( clvar )
           CASE ('e3u_ps')  ; clvar='e3t_ps'
           CASE ('e3v_ps')  ; clvar='e3t_ps'
           CASE ('e3w_ps')  ; clvar='e3w_ps'
          END SELECT
         ELSE
          ! zgr v2
          SELECT CASE ( clvar )
           CASE ('e3t_ps')  ; clvar='e3t'
           CASE ('e3u_ps')  ; clvar='e3u'
           CASE ('e3v_ps')  ; clvar='e3v'
           CASE ('e3w_ps')  ; clvar='e3w'
          END SELECT
         ENDIF
      ENDIF
    ENDIF

    istatus=NF90_INQUIRE(incid, unlimitedDimId=id_dimunlim)
    CALL ERR_HDL(NF90_INQ_VARID ( incid,clvar,id_var))
    ! look for time dim in variable
    inldim=0
    istatus=NF90_INQUIRE_VARIABLE(incid, id_var, ndims=inbdim,dimids=inldim(:) )

    istart(1) = imin
    istart(2) = jmin
    ! JMM ! it workd for X Y Z T file,   not for X Y T .... try to found a fix !
    IF ( inldim(3) == id_dimunlim ) THEN
    istart(3) = itime
    istart(4) = 1
    ELSE
    istart(3) = ilev
    istart(4) = itime
    ENDIF

    icount(1)=kpi
    icount(2)=kpj
    icount(3)=1
    icount(4)=1

    istatus=NF90_INQUIRE_ATTRIBUTE(incid,id_var,'missing_value')
    IF (istatus == NF90_NOERR ) THEN
       istatus=NF90_GET_ATT(incid,id_var,'missing_value',spval)
    ELSE
       ! assume spval is 0 ?
       spval = 0.
    ENDIF

    istatus=NF90_INQUIRE_ATTRIBUTE(incid,id_var,'savelog10')
    IF (istatus == NF90_NOERR ) THEN
       ! there is a scale factor for this variable
       istatus=NF90_GET_ATT(incid,id_var,'savelog10',ilog)
       IF ( ilog /= 0 ) llog=.TRUE.
    ENDIF

    istatus=NF90_INQUIRE_ATTRIBUTE(incid,id_var,'scale_factor')
    IF (istatus == NF90_NOERR ) THEN
       ! there is a scale factor for this variable
       istatus=NF90_GET_ATT(incid,id_var,'scale_factor',sf)
       IF ( sf /= 1. ) lsf=.TRUE.
    ENDIF

    istatus=NF90_INQUIRE_ATTRIBUTE(incid,id_var,'add_offset')
    IF (istatus == NF90_NOERR ) THEN
       ! there is a scale factor for this variable
       istatus=NF90_GET_ATT(incid,id_var,'add_offset', ao)
       IF ( ao /= 0.) lao=.TRUE.
    ENDIF


    IF (llperio ) THEN
      ALLOCATE (zend (ipiglo-imin,kpj), zstart(imax-1,kpj) )
      IF (l_mbathy .AND. &
        &  ( cdvar == 'e3t_ps' .OR. cdvar == 'e3w_ps' .OR. cdvar == 'e3u_ps' .OR. cdvar == 'e3v_ps'))  THEN
       istatus=0
       clvar=cdvar
       SELECT CASE ( clvar )
         CASE ( 'e3t_ps', 'e3u_ps', 'e3v_ps' ) 
           DO ji=1,ipiglo-imin
            DO jj=1,kpj
             ik=mbathy(imin+ji-1, jmin+jj-1)
             IF (ilev == ik ) THEN
               zend(ji,jj)=e3t_ps(imin+ji-1, jmin+jj-1)
             ELSE
               zend(ji,jj)=e3t_0(ilev)
             ENDIF
            END DO
           END DO
           DO ji=1,imax-1
            DO jj=1,kpj
             ik=mbathy(ji+1, jmin+jj-1)
             IF (ilev == ik ) THEN
               zstart(ji,jj)=e3t_ps(ji+1, jmin+jj-1)
             ELSE
               zstart(ji,jj)=e3t_0(ilev)
             ENDIF
            END DO
           END DO
          getvar(1:ipiglo-imin,:)=zend
          getvar(ipiglo-imin+1:kpi,:)=zstart
         IF (clvar == 'e3u_ps') THEN
         DO ji=1,kpi-1
          DO jj=1,kpj
            getvar(ji,jj)=MIN(getvar(ji,jj),getvar(ji+1,jj))
          END DO
         END DO
           ! not very satisfactory but still....
           getvar(kpi,:)=getvar(kpi-1,:)
         ENDIF

         IF (clvar == 'e3v_ps') THEN
         DO ji=1,kpi
          DO jj=1,kpj-1
            getvar(ji,jj)=MIN(getvar(ji,jj),getvar(ji,jj+1))
          END DO
         END DO
           ! not very satisfactory but still....
           getvar(:,kpj)=getvar(:,kpj-1)
         ENDIF
         
         CASE ( 'e3w_ps')
           DO ji=1,ipiglo-imin
            DO jj=1,kpj
             ik=mbathy(imin+ji-1, jmin+jj-1)
             IF (ilev == ik ) THEN
               zend(ji,jj)=e3w_ps(imin+ji-1, jmin+jj-1)
             ELSE
               zend(ji,jj)=e3w_0(ilev)
             ENDIF
            END DO
           END DO
           DO ji=1,imax-1
            DO jj=1,kpj
             ik=mbathy(ji+1, jmin+jj-1)
             IF (ilev == ik ) THEN
               zstart(ji,jj)=e3w_ps(ji+1, jmin+jj-1)
             ELSE
               zstart(ji,jj)=e3w_0(ilev)
             ENDIF
            END DO
           END DO
       getvar(1:ipiglo-imin,:)=zend
       getvar(ipiglo-imin+1:kpi,:)=zstart

       END SELECT
      ELSE
       istatus=NF90_GET_VAR(incid,id_var,zend, start=(/imin,jmin,ilev,itime/),count=(/ipiglo-imin,kpj,1,1/))
       istatus=NF90_GET_VAR(incid,id_var,zstart, start=(/2,jmin,ilev,itime/),count=(/imax-1,kpj,1,1/))
       getvar(1:ipiglo-imin,:)=zend
       getvar(ipiglo-imin+1:kpi,:)=zstart
      ENDIF
      DEALLOCATE(zstart, zend )
    ELSE
      IF (l_mbathy .AND. &
        &  ( cdvar == 'e3t_ps' .OR. cdvar == 'e3w_ps' .OR. cdvar == 'e3u_ps' .OR. cdvar == 'e3v_ps'))  THEN
       istatus=0
       clvar=cdvar
       SELECT CASE ( clvar )
         CASE ( 'e3t_ps', 'e3u_ps', 'e3v_ps' ) 
         DO ji=1,kpi
          DO jj=1,kpj
           ik=mbathy(imin+ji-1, jmin+jj-1)
           IF (ilev == ik ) THEN
             getvar(ji,jj)=e3t_ps(imin+ji-1, jmin+jj-1)
           ELSE
             getvar(ji,jj)=e3t_0(ilev)
           ENDIF
          END DO
         END DO
         IF (clvar == 'e3u_ps') THEN
         DO ji=1,kpi-1
          DO jj=1,kpj
            getvar(ji,jj)=MIN(getvar(ji,jj),getvar(ji+1,jj))
          END DO
         END DO
           ! not very satisfactory but still....
           getvar(kpi,:)=getvar(2,:) 
         ENDIF
         IF (clvar == 'e3v_ps') THEN
         DO ji=1,kpi
          DO jj=1,kpj-1
            getvar(ji,jj)=MIN(getvar(ji,jj),getvar(ji,jj+1))
          END DO
         END DO
           ! not very satisfactory but still....
           getvar(:,kpj)=getvar(:,kpj-1)
         ENDIF

         CASE ( 'e3w_ps')
         DO ji=1,kpi
          DO jj=1,kpj
           ik=mbathy(imin+ji-1, jmin+jj-1)
           IF (ilev == ik ) THEN
             getvar(ji,jj)=e3w_ps(imin+ji-1, jmin+jj-1)
           ELSE
             getvar(ji,jj)=e3w_0(ilev)
           ENDIF
          END DO
         END DO

       END SELECT
      ELSE
        istatus=NF90_GET_VAR(incid,id_var,getvar, start=istart,count=icount)
      ENDIF
    ENDIF
    IF ( istatus /= 0 ) THEN
       PRINT *,' Problem in getvar for ', TRIM(clvar)
       CALL ERR_HDL(istatus)
       STOP
    ENDIF

    ! Caution : order does matter !
    IF (lsf )  WHERE (getvar /= spval )  getvar=getvar*sf
    IF (lao )  WHERE (getvar /= spval )  getvar=getvar + ao
    IF (llog)  WHERE (getvar /= spval )  getvar=10**getvar

    istatus=NF90_CLOSE(incid)

  END FUNCTION getvar


  FUNCTION  getvarxz (cdfile, cdvar, kj, kpi, kpz, kimin, kkmin, ktime)
    !!-------------------------------------------------------------------------
    !!                  ***  FUNCTION  getvar  ***
    !!
    !! ** Purpose : Return the 2D REAL variable x-z slab cvar, from cdfile at j=kj
    !!              kpi,kpz are the  size of the 2D variable
    !!
    !!-------------------------------------------------------------------------
    CHARACTER(LEN=*),          INTENT(in) :: cdfile        ! file name to work with
    CHARACTER(LEN=*),          INTENT(in) :: cdvar         ! variable name to work with
    INTEGER(KIND=4),           INTENT(in) :: kj            ! Optional variable. If missing 1 is assumed
    INTEGER(KIND=4),           INTENT(in) :: kpi, kpz      ! size of the 2D variable
    INTEGER(KIND=4), OPTIONAL, INTENT(in) :: kimin, kkmin  ! Optional variable. If missing 1 is assumed
    INTEGER(KIND=4), OPTIONAL, INTENT(in) :: ktime         ! Optional variable. If missing 1 is assumed 
    REAL(KIND=4), DIMENSION(kpi,kpz)      :: getvarxz      ! 2D REAL 4 holding variable x-z slab at kj

    INTEGER(KIND=4), DIMENSION(4) :: istart, icount
    INTEGER(KIND=4)               :: incid, id_var
    INTEGER(KIND=4)               :: istatus, ilev, imin, kmin
    INTEGER(KIND=4)               :: itime, ilog
    INTEGER(KIND=4)               :: idum
    REAL(KIND=4)                  :: sf=1., ao=0.       !  Scale factor and add_offset
    REAL(KIND=4)                  :: spval              !  Missing values
    LOGICAL                       :: llog=.FALSE. , lsf=.FALSE. , lao=.FALSE.
    !!-------------------------------------------------------------------------

    IF (PRESENT(kimin) ) THEN
       imin=kimin
    ELSE
       imin=1
    ENDIF

    IF (PRESENT(kkmin) ) THEN
       kmin=kkmin
    ELSE
       kmin=1
    ENDIF

    IF (PRESENT(ktime) ) THEN
       itime=ktime
    ELSE
       itime=1
    ENDIF

    ! Must reset the flags to false for every call to getvar
    llog=.FALSE.
    lsf=.FALSE.
    lao=.FALSE.


    CALL ERR_HDL(NF90_OPEN(cdfile,NF90_NOWRITE,incid) )
    CALL ERR_HDL(NF90_INQ_VARID ( incid,cdvar,id_var))

    istatus=NF90_INQUIRE_ATTRIBUTE(incid,id_var,'missing_value')
    IF (istatus == NF90_NOERR ) THEN
       istatus=NF90_GET_ATT(incid,id_var,'missing_value',spval)
    ELSE
       ! assume spval is 0 ?
       spval = 0.
    ENDIF

    istatus=NF90_INQUIRE_ATTRIBUTE(incid,id_var,'savelog10')
    IF (istatus == NF90_NOERR ) THEN
       ! there is a scale factor for this variable
       istatus=NF90_GET_ATT(incid,id_var,'savelog10',ilog)
       IF ( ilog /= 0 ) llog=.TRUE.
    ENDIF

    istatus=NF90_INQUIRE_ATTRIBUTE(incid,id_var,'scale_factor')
    IF (istatus == NF90_NOERR ) THEN
       ! there is a scale factor for this variable
       istatus=NF90_GET_ATT(incid,id_var,'scale_factor',sf)
       IF ( sf /= 1. ) lsf=.TRUE.
    ENDIF

    istatus=NF90_INQUIRE_ATTRIBUTE(incid,id_var,'add_offset')
    IF (istatus == NF90_NOERR ) THEN
       ! there is a scale factor for this variable
       istatus=NF90_GET_ATT(incid,id_var,'add_offset',ao)
       IF ( ao /= 0.) lao=.TRUE.
    ENDIF

    ! detect if there is a y dimension in cdfile
    istatus=NF90_INQ_DIMID(incid,'y',idum)
    IF ( istatus == NF90_NOERR ) THEN  ! the file has a 'y' dimension
      istart=(/imin,kj,kmin,itime/)
      ! JMM ! it workd for X Y Z T file,   not for X Y T .... try to found a fix !
      icount=(/kpi,1,kpz,1/)
    ELSE    ! no y dimension
      istart=(/imin,kmin,itime,1/)
      icount=(/kpi,kpz,1,1/)
    ENDIF

    istatus=NF90_GET_VAR(incid,id_var,getvarxz, start=istart,count=icount)
    IF ( istatus /= 0 ) THEN
       PRINT *,' Problem in getvarxz for ', TRIM(cdvar)
       CALL ERR_HDL(istatus)
       STOP
    ENDIF

    ! Caution : order does matter !
    IF (lsf )  WHERE (getvarxz /= spval )  getvarxz=getvarxz*sf
    IF (lao )  WHERE (getvarxz /= spval )  getvarxz=getvarxz + ao
    IF (llog)  WHERE (getvarxz /= spval )  getvarxz=10**getvarxz

    istatus=NF90_CLOSE(incid)

  END FUNCTION getvarxz


  FUNCTION  getvaryz (cdfile, cdvar, ki, kpj, kpz, kjmin, kkmin, ktime)
    !!-------------------------------------------------------------------------
    !!                  ***  FUNCTION  getvar  ***
    !!
    !! ** Purpose : Return the 2D REAL variable y-z slab cvar, from cdfile at i=ki
    !!              kpj,kpz are the  size of the 2D variable
    !!
    !!-------------------------------------------------------------------------
    CHARACTER(LEN=*),          INTENT(in) :: cdfile       ! file name to work with
    CHARACTER(LEN=*),          INTENT(in) :: cdvar        ! variable name to work with
    INTEGER(KIND=4),           INTENT(in) :: ki           ! 
    INTEGER(KIND=4),           INTENT(in) :: kpj,kpz      ! size of the 2D variable
    INTEGER(KIND=4), OPTIONAL, INTENT(in) :: kjmin, kkmin ! Optional variable. If missing 1 is assumed
    INTEGER(KIND=4), OPTIONAL, INTENT(in) :: ktime        ! Optional variable. If missing 1 is assumed
    REAL(KIND=4), DIMENSION(kpj,kpz)      :: getvaryz     ! 2D REAL 4 holding variable x-z slab at kj

    INTEGER(KIND=4), DIMENSION(4)       :: istart, icount
    INTEGER(KIND=4)                     :: incid, id_var
    INTEGER(KIND=4)                     :: istatus, ilev, jmin, kmin
    INTEGER(KIND=4)                     :: itime, ilog
    INTEGER(KIND=4)                     :: idum

    REAL(KIND=4)                        :: sf=1., ao=0.   !  Scale factor and add_offset
    REAL(KIND=4)                        :: spval          !  Missing values
    LOGICAL                             :: llog=.FALSE. , lsf=.FALSE. , lao=.FALSE.
    !!-------------------------------------------------------------------------

    IF (PRESENT(kjmin) ) THEN
       jmin=kjmin
    ELSE
       jmin=1
    ENDIF

    IF (PRESENT(kkmin) ) THEN
       kmin=kkmin
    ELSE
       kmin=1
    ENDIF

    IF (PRESENT(ktime) ) THEN
       itime=ktime
    ELSE
       itime=1
    ENDIF

    ! Must reset the flags to false for every call to getvar
    llog=.FALSE.
    lsf=.FALSE.
    lao=.FALSE.


    CALL ERR_HDL(NF90_OPEN(cdfile,NF90_NOWRITE,incid) )
    CALL ERR_HDL(NF90_INQ_VARID ( incid,cdvar,id_var))

    istatus=NF90_INQUIRE_ATTRIBUTE(incid,id_var,'missing_value')
    IF (istatus == NF90_NOERR ) THEN
       istatus=NF90_GET_ATT(incid,id_var,'missing_value',spval)
    ELSE
       ! assume spval is 0 ?
       spval = 0.
    ENDIF

    istatus=NF90_INQUIRE_ATTRIBUTE(incid,id_var,'savelog10')
    IF (istatus == NF90_NOERR ) THEN
       ! there is a scale factor for this variable
       istatus=NF90_GET_ATT(incid,id_var,'savelog10',ilog)
       IF ( ilog /= 0 ) llog=.TRUE.
    ENDIF

    istatus=NF90_INQUIRE_ATTRIBUTE(incid,id_var,'scale_factor')
    IF (istatus == NF90_NOERR ) THEN
       ! there is a scale factor for this variable
       istatus=NF90_GET_ATT(incid,id_var,'scale_factor',sf)
       IF ( sf /= 1. ) lsf=.TRUE.
    ENDIF

    istatus=NF90_INQUIRE_ATTRIBUTE(incid,id_var,'add_offset')
    IF (istatus == NF90_NOERR ) THEN
       ! there is a scale factor for this variable
       istatus=NF90_GET_ATT(incid,id_var,'add_offset', ao)
       IF ( ao /= 0.) lao=.TRUE.
    ENDIF

    ! detect if there is a x dimension in cdfile
    istatus=NF90_INQ_DIMID(incid,'x',idum)
    IF ( istatus == NF90_NOERR ) THEN  ! the file has a 'x' dimension
      istart=(/ki,jmin,kmin,itime/)
      ! JMM ! it workd for X Y Z T file,   not for X Y T .... try to found a fix !
      icount=(/1,kpj,kpz,1/)
    ELSE    ! no x dimension
      istart=(/jmin,kmin,itime,1/)
      icount=(/kpj,kpz,1,1/)
    ENDIF

    istatus=NF90_GET_VAR(incid,id_var,getvaryz, start=istart,count=icount)
    IF ( istatus /= 0 ) THEN
       PRINT *,' Problem in getvaryz for ', TRIM(cdvar)
       CALL ERR_HDL(istatus)
       STOP
    ENDIF

    ! Caution : order does matter !
    IF (lsf )  WHERE (getvaryz /= spval )  getvaryz=getvaryz*sf
    IF (lao )  WHERE (getvaryz /= spval )  getvaryz=getvaryz + ao
    IF (llog)  WHERE (getvaryz /= spval )  getvaryz=10**getvaryz

    istatus=NF90_CLOSE(incid)

  END FUNCTION getvaryz


  FUNCTION  getvar1d (cdfile, cdvar, kk, kstatus)
    !!-------------------------------------------------------------------------
    !!                  ***  FUNCTION  getvar1d  ***
    !!
    !! ** Purpose :  return 1D variable cdvar from cdfile, of size kk
    !!
    !!-------------------------------------------------------------------------
    CHARACTER(LEN=*),           INTENT(in) :: cdfile   ! file name to work with
    CHARACTER(LEN=*),           INTENT(in) :: cdvar    ! variable name to work with
    INTEGER(KIND=4),            INTENT(in) :: kk       ! size of 1D vector to be returned
    INTEGER(KIND=4), OPTIONAL, INTENT(out) :: kstatus  ! return status concerning the variable existence
    REAL(KIND=4), DIMENSION(kk)            :: getvar1d ! real returned vector

    INTEGER(KIND=4), DIMENSION(1) :: istart, icount
    INTEGER(KIND=4) :: incid, id_var
    INTEGER(KIND=4) :: istatus
    !!-------------------------------------------------------------------------
    istart(:) = 1
    icount(1)=kk
    IF ( PRESENT(kstatus) ) kstatus = 0

    istatus=NF90_OPEN(cdfile,NF90_NOWRITE,incid)
    istatus=NF90_INQ_VARID ( incid,cdvar,id_var)
    IF ( istatus == NF90_NOERR ) THEN
       istatus=NF90_GET_VAR(incid,id_var,getvar1d,start=istart,count=icount)
    ELSE
       IF ( PRESENT(kstatus) ) kstatus= istatus
       getvar1d=99999999999.
    ENDIF

    istatus=NF90_CLOSE(incid)

  END FUNCTION getvar1d


  FUNCTION  getvare3 (cdfile,cdvar,kk)
    !!-------------------------------------------------------------------------
    !!                  ***  FUNCTION  getvare3  ***
    !!
    !! ** Purpose :  Special routine for e3, which in fact is a 1D variable
    !!               but defined as e3 (1,1,npk,1) in coordinates.nc (!!)
    !!
    !!-------------------------------------------------------------------------
    CHARACTER(LEN=*), INTENT(in) :: cdfile   ! file name to work with
    CHARACTER(LEN=*), INTENT(in) :: cdvar    ! variable name to work with
    INTEGER(KIND=4),  INTENT(in) :: kk       ! size of 1D vector to be returned
    REAL(KIND=4),  DIMENSION(kk) :: getvare3 ! return e3 variable form the coordinate file

    INTEGER(KIND=4), DIMENSION(4) :: istart, icount
    INTEGER(KIND=4)               :: incid, id_var
    INTEGER(KIND=4)               :: istatus
    CHARACTER(LEN=256)            :: clvar   ! local name for cdf var (modified)
    !!-------------------------------------------------------------------------
    istart(:) = 1
    icount(:) = 1
    icount(3)=kk
    clvar=cdvar

    istatus=NF90_OPEN(cdfile,NF90_NOWRITE,incid)
    ! check for IOM style mesh_zgr or coordinates :
    ! IOIPSL (x_a=y_a=1)               IOM 
    ! gdept(time,z,y_a,x_a)            gdept_0(t,z)
    ! gdepw(time,z,y_a,x_a)            gdepw_0(t,z)
    !   e3t(time,z,y_a,x_a)            e3t_0(t,z)
    !   e3w(time,z,y_a,x_a)            e3w_0(t,z)
    istatus=NF90_INQ_VARID ( incid,'e3t_0',id_var)
    IF ( istatus == NF90_NOERR) THEN
     icount(1)=kk ; icount(3)=1
     SELECT CASE (clvar)
        CASE ('gdepw') 
           clvar='gdepw_0'
        CASE ('gdept')
           clvar='gdept_0'
        CASE ('e3t')
           clvar='e3t_0'
        CASE ('e3w')
           clvar='e3w_0'
      END SELECT
    ENDIF

    istatus=NF90_INQ_VARID ( incid,clvar,id_var)
    istatus=NF90_GET_VAR(incid,id_var,getvare3,start=istart,count=icount)
    IF ( istatus /= 0 ) THEN
       PRINT *,' Problem in getvare3 for ', TRIM(cdvar)
       PRINT *,TRIM(cdfile), kk
       CALL ERR_HDL(istatus)
       STOP
    ENDIF

    istatus=NF90_CLOSE(incid)

  END FUNCTION getvare3


  INTEGER(KIND=4) FUNCTION putheadervar(kout, cdfile, kpi, kpj, kpk, pnavlon, pnavlat , pdep, cdep)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION  putheadervar  ***
    !!
    !! ** Purpose :  copy header variables from cdfile to the already open ncfile (ncid=kout)
    !!
    !! ** Method  :  header variables are nav_lat, nav_lon and either (deptht, depthu, or depthv )
    !!               Even if the use of different variable name for deptht, depthu depthv is
    !!               one of the many non sense of IOIPSL, we are forced to stick with !
    !!               (Note that these 3 depth are identical in OPA. On the other hand, nav_lon, nav_lat
    !!               differ for U and V and T points but have the same variable name).
    !!               If pnavlon and pnavlat are provided as arguments, they are used for nav_lon, nav_lat
    !!               instead of the nav_lon,nav_lat read on the file cdfile.
    !!
    !! ** Action  : header variables for file kout is copied from cdfile
    !!
    !!----------------------------------------------------------------------
    INTEGER(KIND=4),                            INTENT(in) :: kout     ! ncid of the outputfile (already open )
    CHARACTER(LEN=*),                           INTENT(in) :: cdfile   ! file from where the headers will be copied
    INTEGER(KIND=4),                            INTENT(in) :: kpi, kpj ! dimension of nav_lon (kpi,kpj)
    INTEGER(KIND=4),                            INTENT(in) :: kpk      ! dimension of depht(kpk)
    REAL(KIND=4), OPTIONAL, DIMENSION(kpi,kpj), INTENT(in) :: pnavlon  ! array provided optionaly to overrid the
    REAL(KIND=4), OPTIONAL, DIMENSION(kpi,kpj), INTENT(in) :: pnavlat  ! corresponding arrays in cdfile 
    REAL(KIND=4), OPTIONAL, DIMENSION(kpk),     INTENT(in) :: pdep     ! dep array if not on cdfile
    CHARACTER(LEN=*), OPTIONAL,                 INTENT(in) :: cdep     ! optional name of vertical variable

    INTEGER(KIND=4), PARAMETER                :: jpdep=6
    INTEGER(KIND=4)                           :: istatus, idep, jj
    REAL(KIND=4), DIMENSION(:,:), ALLOCATABLE :: z2d
    REAL(KIND=4), DIMENSION(kpk)              :: z1d
    CHARACTER(LEN=256), DIMENSION(jpdep )     :: cldept= (/'deptht ','depthu ','depthv ','depthw ','nav_lev','z      '/)
    CHARACTER(LEN=256)                        :: cldep
    !!----------------------------------------------------------------------
    ALLOCATE ( z2d (kpi,kpj) )

    IF (PRESENT(pnavlon) ) THEN 
       z2d = pnavlon
    ELSE
       z2d=getvar(cdfile,cn_vlon2d, 1,kpi,kpj)
    ENDIF
    istatus = putvar(kout, nid_lon,z2d,1,kpi,kpj)

    IF (PRESENT(pnavlat) ) THEN
       z2d = pnavlat
    ELSE
       z2d=getvar(cdfile,cn_vlat2d, 1,kpi,kpj)
    ENDIF

    istatus = putvar(kout, nid_lat,z2d,1,kpi,kpj)

    IF (kpk /= 0 ) THEN
       IF (PRESENT(pdep) ) THEN
          z1d = pdep
       ELSE
          idep = NF90_NOERR

          IF ( PRESENT (cdep)) THEN
             z1d=getvar1d(cdfile,cdep,kpk,idep)
          ENDIF

          ! Test name specified in the namelist (P.M.)
          z1d=getvar1d(cdfile,cn_vdeptht,kpk,idep)
          IF ( idep /= NF90_NOERR ) z1d=getvar1d(cdfile,cn_vdepthu,kpk,idep)
          IF ( idep /= NF90_NOERR ) z1d=getvar1d(cdfile,cn_vdepthv,kpk,idep)
          IF ( idep /= NF90_NOERR ) z1d=getvar1d(cdfile,cn_vdepthw,kpk,idep)
          ! End (P.M.)

          IF ( .NOT. PRESENT(cdep) .OR. idep /= NF90_NOERR ) THEN  ! look for standard dep name
             DO jj = 1,jpdep
                cldep=cldept(jj)
                z1d=getvar1d(cdfile,cldep,kpk,idep)
                IF ( idep == NF90_NOERR )  EXIT
             END DO
             IF (jj == jpdep +1 ) THEN
                PRINT *,' No depth variable found in ', TRIM(cdfile)
                STOP
             ENDIF
          ENDIF
       ENDIF

       istatus = putvar1d(kout,z1d,kpk,'D')
    ENDIF

    putheadervar=istatus

    DEALLOCATE (z2d)

  END FUNCTION putheadervar


  INTEGER(KIND=4) FUNCTION putvarr8(kout, kid, ptab, klev, kpi, kpj, ktime, kwght)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION putvarr8  ***
    !!            
    !! ** Purpose : copy a 2D level of ptab in already open file kout, 
    !!              using variable kid
    !!
    !! ** Method  : this corresponds to the generic function putvar with r8 arg.
    !!----------------------------------------------------------------------
    INTEGER(KIND=4),                  INTENT(in) :: kout     ! ncid of output file
    INTEGER(KIND=4),                  INTENT(in) :: kid      ! varid of output variable
    REAL(KIND=8), DIMENSION(kpi,kpj), INTENT(in) :: ptab     ! 2D array to write in file
    INTEGER(KIND=4),                  INTENT(in) :: klev     ! level at which ptab will be written
    INTEGER(KIND=4),                  INTENT(in) :: kpi, kpj ! dimension of ptab
    INTEGER(KIND=4), OPTIONAL,        INTENT(in) :: ktime    ! dimension of ptab
    INTEGER(KIND=4), OPTIONAL,        INTENT(in) :: kwght    ! weight of this variable

    INTEGER(KIND=4)               :: istatus, itime, id_dimunlim
    INTEGER(KIND=4), DIMENSION(4) :: istart, icount, inldim
    !!----------------------------------------------------------------------
    IF (PRESENT(ktime) ) THEN
       itime=ktime
    ELSE
       itime=1
    ENDIF

    ! Look for a unlimited dimension
    istatus=NF90_INQUIRE(kout, unlimitedDimId = id_dimunlim)
    inldim(:) = 0
    istart(:) = 1
    istatus=NF90_INQUIRE_VARIABLE(kout, kid, dimids = inldim(:) )

    IF ( inldim(3) == id_dimunlim)  THEN  ! this is a x,y,t file
     istart(3)=itime ; istart(4)=1
    ELSE
     istart(3)=klev ; istart(4)=itime     ! this is a x,y,z, t file
    ENDIF

    icount(:) = 1 ; icount(1) = kpi ; icount(2) = kpj
    istatus=NF90_PUT_VAR(kout,kid, ptab, start=istart,count=icount)

    IF (PRESENT(kwght) ) THEN
      istatus=NF90_PUT_ATT(kout, kid, 'iweight', kwght)
    ENDIF
    putvarr8=istatus

  END FUNCTION putvarr8


  INTEGER(KIND=4) FUNCTION putvarr4(kout, kid, ptab, klev, kpi, kpj, ktime, kwght)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION putvarr4  ***
    !!            
    !! ** Purpose : copy a 2D level of ptab in already open file kout, 
    !!              using variable kid
    !!
    !! ** Method  : this corresponds to the generic function putvar with r4 arg.
    !!----------------------------------------------------------------------
    INTEGER(KIND=4),                  INTENT(in) :: kout     ! ncid of output file
    INTEGER(KIND=4),                  INTENT(in) :: kid      ! varid of output variable
    REAL(KIND=4), DIMENSION(kpi,kpj), INTENT(in) :: ptab     ! 2D array to write in file
    INTEGER(KIND=4),                  INTENT(in) :: klev     ! level at which ptab will be written
    INTEGER(KIND=4),                  INTENT(in) :: kpi, kpj ! dimension of ptab
    INTEGER(KIND=4), OPTIONAL,        INTENT(in) :: ktime    ! dimension of ptab
    INTEGER(KIND=4), OPTIONAL,        INTENT(in) :: kwght    ! weight of this variable

    INTEGER(KIND=4)               :: istatus, itime, id_dimunlim
    INTEGER(KIND=4), DIMENSION(4) :: istart, icount, inldim
    !!----------------------------------------------------------------------
    IF (PRESENT(ktime) ) THEN
       itime=ktime
    ELSE
       itime=1
    ENDIF

    ! Look for a unlimited dimension
    istatus=NF90_INQUIRE(kout, unlimitedDimId = id_dimunlim)
    inldim(:) = 0
    istart(:) = 1
    istatus=NF90_INQUIRE_VARIABLE(kout, kid, dimids = inldim(:) )

    IF ( inldim(3) == id_dimunlim)  THEN  ! this is a x,y,t file
     istart(3)=itime ; istart(4)=1
    ELSE
     istart(3)=klev ; istart(4)=itime     ! this is a x,y,z, t file
    ENDIF

    icount(:) = 1 ; icount(1) = kpi ; icount(2) = kpj
    istatus=NF90_PUT_VAR(kout,kid, ptab, start=istart,count=icount)

    IF (PRESENT(kwght) ) THEN
      istatus=NF90_PUT_ATT(kout, kid, 'iweight', kwght)
    ENDIF
    putvarr4=istatus

  END FUNCTION putvarr4


  INTEGER(KIND=4) FUNCTION putvari2(kout, kid, ktab, klev, kpi, kpj, ktime, kwght)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION putvari2  ***
    !!            
    !! ** Purpose : copy a 2D level of ptab in already open file kout, 
    !!              using variable kid
    !!
    !! ** Method  : this corresponds to the generic function putvar with i2 arg.
    !!----------------------------------------------------------------------
    INTEGER(KIND=4),                     INTENT(in) :: kout     ! ncid of output file
    INTEGER(KIND=4),                     INTENT(in) :: kid      ! varid of output variable
    INTEGER(KIND=2), DIMENSION(kpi,kpj), INTENT(in) :: ktab     ! 2D array to write in file
    INTEGER(KIND=4),                     INTENT(in) :: klev     ! level at which ktab will be written
    INTEGER(KIND=4),                     INTENT(in) :: kpi, kpj ! dimension of ktab
    INTEGER(KIND=4), OPTIONAL,           INTENT(in) :: ktime    ! dimension of ktab
    INTEGER(KIND=4), OPTIONAL,           INTENT(in) :: kwght    ! weight of this variable

    INTEGER(KIND=4)               :: istatus, itime, id_dimunlim
    INTEGER(KIND=4), DIMENSION(4) :: istart, icount, inldim
    !!----------------------------------------------------------------------
    IF (PRESENT(ktime) ) THEN
       itime=ktime
    ELSE
       itime=1
    ENDIF

    ! Look for a unlimited dimension
    istatus=NF90_INQUIRE(kout, unlimitedDimId = id_dimunlim)
    inldim(:) = 0
    istart(:) = 1
    istatus=NF90_INQUIRE_VARIABLE(kout, kid, dimids = inldim(:) )

    IF ( inldim(3) == id_dimunlim)  THEN  ! this is a x,y,t file
     istart(3)=itime ; istart(4)=1
    ELSE
     istart(3)=klev ; istart(4)=itime     ! this is a x,y,z, t file
    ENDIF

    icount(:) = 1 ; icount(1) = kpi ; icount(2) = kpj
    istatus=NF90_PUT_VAR(kout,kid, ktab, start=istart,count=icount)

    IF (PRESENT(kwght) ) THEN
      istatus=NF90_PUT_ATT(kout, kid, 'iweight', kwght)
    ENDIF
    putvari2=istatus

  END FUNCTION putvari2


  INTEGER(KIND=4) FUNCTION reputvarr4 (cdfile, cdvar, klev, kpi, kpj, kimin, kjmin, ktime, ptab, kwght)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION reputvarr4  ***
    !!
    !! ** Purpose :  Change an existing variable in inputfile 
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*),                 INTENT(in) :: cdfile       ! file name to work with
    CHARACTER(LEN=*),                 INTENT(in) :: cdvar        ! variable name to work with
    INTEGER(KIND=4), OPTIONAL,        INTENT(in) :: klev         ! Optional variable. If missing 1 is assumed
    INTEGER(KIND=4),                  INTENT(in) :: kpi, kpj     ! horizontal size of the 2D variable
    INTEGER(KIND=4), OPTIONAL,        INTENT(in) :: kimin, kjmin ! Optional variable. If missing 1 is assumed
    INTEGER(KIND=4), OPTIONAL,        INTENT(in) :: ktime        ! Optional variable. If missing 1 is assumed
    REAL(KIND=4), DIMENSION(kpi,kpj), INTENT(in) :: ptab        ! 2D REAL 4 holding variable field at klev
    INTEGER(KIND=4), OPTIONAL,        INTENT(in) :: kwght        ! weight of this variable

    INTEGER(KIND=4), DIMENSION(4) :: istart, icount, inldim
    INTEGER(KIND=4) :: incid, id_var, id_dimunlim
    INTEGER(KIND=4) :: istatus, ilev, iimin, ijmin, itime
    !!----------------------------------------------------------------------
    ilev  = 1 ; IF (PRESENT(klev ) ) ilev  = klev
    iimin = 1 ; IF (PRESENT(kimin) ) iimin = kimin
    ijmin = 1 ; IF (PRESENT(kjmin) ) ijmin = kjmin
    itime = 1 ; IF (PRESENT(ktime) ) itime = ktime

    istatus=NF90_OPEN(cdfile,NF90_WRITE,incid)
    istatus=NF90_INQ_VARID(incid,cdvar,id_var)
    !! look for eventual unlimited dim (time_counter)
    istatus=NF90_INQUIRE(incid, unlimitedDimId=id_dimunlim)
    
    inldim=0
    istatus=NF90_INQUIRE_VARIABLE(incid, id_var,dimids=inldim(:) )

    ! if the third dim of id_var is time, then adjust the starting point 
    ! to take ktime into account (case XYT file)
    IF ( inldim(3) == id_dimunlim)  THEN ; ilev=itime ; itime=1 ; ENDIF
    istatus=NF90_PUT_VAR(incid,id_var, ptab,start=(/iimin,ijmin,ilev,itime/), count=(/kpi,kpj,1,1/) )

    IF (PRESENT(kwght)) THEN
      istatus=NF90_PUT_ATT(incid,id_var,'iweight',kwght)
    ENDIF

    reputvarr4=istatus

    istatus=NF90_CLOSE(incid)

  END FUNCTION reputvarr4


  INTEGER(KIND=4) FUNCTION putvarzo(kout, kid, ptab, klev, kpi, kpj, ktime)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION putvarzo  ***
    !!
    !! ** Purpose : Copy a 2D level of ptab in already open file kout, using variable kid
    !!              This variant deals with degenerated 2D (1 x jpj) zonal files
    !!
    !!----------------------------------------------------------------------
    INTEGER(KIND=4),              INTENT(in) :: kout             ! ncid of output file
    INTEGER(KIND=4),              INTENT(in) :: kid              ! varid of output variable
    REAL(KIND=4), DIMENSION(kpj), INTENT(in) :: ptab             ! 2D array to write in file
    INTEGER(KIND=4),              INTENT(in) :: klev             ! level at which ptab will be written
    INTEGER(KIND=4),              INTENT(in) :: kpi, kpj         ! dimension of ptab
    INTEGER(KIND=4), OPTIONAL,    INTENT(in) :: ktime            ! time to write

    INTEGER(KIND=4)               :: istatus, itime, ilev, id_dimunlim
    INTEGER(KIND=4), DIMENSION(4) :: istart, icount,inldim
    !!----------------------------------------------------------------------
    ilev=klev
    IF (PRESENT(ktime) ) THEN
       itime=ktime
    ELSE
       itime=1
    ENDIF

     ! look for unlimited dim (time_counter)
    istatus=NF90_INQUIRE(kout, unlimitedDimId=id_dimunlim)
    inldim=0
    istatus=NF90_INQUIRE_VARIABLE(kout,kid,dimids=inldim(:) )

    !  if the third dim of id_var is time, then adjust the starting point 
    !  to take ktime into account (case XYT file)
    IF ( inldim(3) == id_dimunlim)  THEN ; ilev=itime ; itime=1 ; ENDIF
    istart(:) = 1 ; istart(3)=ilev ; istart(4)=itime
    icount(:) = 1 ; icount(1) = kpi ; icount(2) = kpj
    istatus=NF90_PUT_VAR(kout,kid, ptab, start=istart,count=icount)
    putvarzo=istatus

  END FUNCTION putvarzo


  INTEGER(KIND=4) FUNCTION putvar1d4(kout, ptab, kk, cdtype)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION putvar1d4  ***
    !!
    !! ** Purpose :  Copy 1D variable (size kk) hold in ptab,  with id 
    !!               kid, into file id kout 
    !!
    !! ** Method  : cdtype is either T (time_counter) or D (depth.)
    !!
    !!----------------------------------------------------------------------
    INTEGER(KIND=4),            INTENT(in) :: kout   ! ncid of output file
    REAL(KIND=4), DIMENSION(kk),INTENT(in) :: ptab   ! 1D array to write in file
    INTEGER(KIND=4),            INTENT(in) :: kk     ! number of elements in ptab
    CHARACTER(LEN=1),           INTENT(in) :: cdtype ! either T or D

    INTEGER(KIND=4)               :: istatus, iid
    INTEGER(KIND=4), DIMENSION(1) :: istart, icount
    !!----------------------------------------------------------------------
    SELECT CASE ( cdtype )
    CASE ('T', 't' ) 
       iid = nid_tim
    CASE ('D', 'd' )
       iid = nid_dep
    END SELECT

    istart(:) = 1
    icount(:) = kk
    istatus=NF90_PUT_VAR(kout,iid, ptab, start=istart,count=icount)
    putvar1d4=istatus

  END FUNCTION putvar1d4

  INTEGER(KIND=4) FUNCTION reputvar1d4(cdfile, cdvar, ptab, kk )
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION reputvar1d4  ***
    !!
    !! ** Purpose : Copy 1d variable cdfvar in cdfile, an already existing file
    !!              ptab is the 1d array to write and kk the size of ptab
    !!
    !! ** Method  :   
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*),            INTENT(in) :: cdfile      ! filename
    CHARACTER(LEN=*),            INTENT(in) :: cdvar       ! variable name
    REAL(KIND=4), DIMENSION(kk), INTENT(in) :: ptab        ! 1D array to write in file
    INTEGER(KIND=4),             INTENT(in) :: kk          ! number of elements in ptab

    INTEGER                                 :: istatus, incid, id
    !!-----------------------------------------------------------
    istatus = NF90_OPEN(cdfile, NF90_WRITE, incid)
    istatus = NF90_INQ_VARID(incid, cdvar, id )
    istatus = NF90_PUT_VAR(incid, id, ptab, start=(/1/), count=(/kk/) )
    reputvar1d4 = istatus
    istatus = NF90_CLOSE(incid)

  END FUNCTION reputvar1d4

  INTEGER(KIND=4) FUNCTION putvar0dt(kout, kvarid, pvalue, ktime)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION putvar0dt  ***
    !!
    !! ** Purpose : Copy single value, with id varid, into file id kout
    !!
    !! ** Method  :  use argument as dummy array(1,1) 
    !!
    !!----------------------------------------------------------------------
    INTEGER(KIND=4),              INTENT(in) :: kout   ! ncid of output file
    INTEGER(KIND=4),              INTENT(in) :: kvarid ! id of the variable
    REAL(KIND=4), DIMENSION(1,1), INTENT(in) :: pvalue ! single value to write in file
    INTEGER(KIND=4), OPTIONAL,    INTENT(in) :: ktime  ! time frame to write

    INTEGER(KIND=4) :: istatus
    INTEGER(KIND=4) :: itime
    !!----------------------------------------------------------------------
    IF (PRESENT(ktime) ) THEN
      itime = ktime
    ELSE
      itime = 1
    ENDIF

    istatus=NF90_PUT_VAR(kout, kvarid, pvalue, start=(/1,1,itime/), count=(/1,1,1/) )

    putvar0dt=istatus

  END FUNCTION putvar0dt

  INTEGER(KIND=4) FUNCTION putvar0ds(kout, kvarid, pvalue, ktime)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION putvar0ds  ***
    !!
    !! ** Purpose : Copy single value, with id varid, into file id kout
    !!
    !! ** Method  : use argument as scalar
    !!
    !!----------------------------------------------------------------------
    INTEGER(KIND=4),              INTENT(in) :: kout   ! ncid of output file
    INTEGER(KIND=4),              INTENT(in) :: kvarid ! id of the variable
    REAL(KIND=4),                 INTENT(in) :: pvalue ! single value to write in file
    INTEGER(KIND=4), OPTIONAL,    INTENT(in) :: ktime  ! time frame to write

    INTEGER(KIND=4) :: istatus
    INTEGER(KIND=4) :: itime
    REAL(KIND=4), DIMENSION(1,1)             :: ztab   ! dummy array for PUT_VAR
    !!----------------------------------------------------------------------
    IF (PRESENT(ktime) ) THEN
      itime = ktime
    ELSE
      itime = 1
    ENDIF
    ztab = pvalue

    istatus=NF90_PUT_VAR(kout, kvarid, ztab, start=(/1,1,itime/), count=(/1,1,1/) )

    putvar0ds=istatus

  END FUNCTION putvar0ds



  INTEGER(KIND=4) FUNCTION closeout(kout)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION closeout  ***
    !!
    !! ** Purpose :  close opened output files 
    !!
    !!----------------------------------------------------------------------
    INTEGER(KIND=4), INTENT(in) :: kout   ! ncid of file to be closed
    !!----------------------------------------------------------------------
    closeout=NF90_CLOSE(kout)

  END FUNCTION closeout

  INTEGER(KIND=4) FUNCTION ncopen(cdfile)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION  ncopen  ***
    !!
    !! ** Purpose : open file cdfile and return file ID
    !!
    !!---------------------------------------------------------------------
      CHARACTER(LEN=*), INTENT(in) :: cdfile ! file name

      INTEGER(KIND=4) :: istatus, incid
    !!---------------------------------------------------------------------
      istatus = NF90_OPEN(cdfile,NF90_WRITE,incid)

      ncopen=incid

  END FUNCTION ncopen

  SUBROUTINE ERR_HDL(kstatus)
    !!---------------------------------------------------------------------
    !!                  ***  ROUTINE ERR_HDL  ***
    !!
    !! ** Purpose : Error handle for NetCDF routine.
    !!              Stop if kstatus indicates error conditions.  
    !!
    !!----------------------------------------------------------------------
    INTEGER(KIND=4), INTENT(in) ::  kstatus
    !!----------------------------------------------------------------------
    IF (kstatus /=  NF90_NOERR ) THEN
       PRINT *, 'ERROR in NETCDF routine, status=',kstatus
       PRINT *,NF90_STRERROR(kstatus)
       STOP
    END IF

  END SUBROUTINE ERR_HDL


  SUBROUTINE gettimeseries (cdfile, cdvar, kilook, kjlook, klev)
    !!---------------------------------------------------------------------
    !!                  ***  ROUTINE gettimeseries  ***
    !!
    !! ** Purpose : Display a 2 columns output ( time, variable) for
    !!              a given variable of a given file at a given point 
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*),          INTENT(in) :: cdfile, cdvar
    INTEGER(KIND=4),           INTENT(in) :: kilook,kjlook
    INTEGER(KIND=4), OPTIONAL, INTENT(in) :: klev

    INTEGER(KIND=4)                         :: jt, jk
    INTEGER(KIND=4)                         :: iint
    INTEGER(KIND=4)                         :: istatus
    INTEGER(KIND=4)                         :: incid, id_t, id_var
    INTEGER(KIND=4)                         :: indim
    REAL(KIND=4), DIMENSION(:), ALLOCATABLE :: ztime, zval
    REAL(KIND=4)                            :: ztmp  
    REAL(KIND=4)                            :: zao=0., zsf=1.0   !: add_offset, scale_factor
    !!----------------------------------------------------------------------
    ! Klev can be used to give the model level we want to look at
    IF ( PRESENT(klev) ) THEN
       jk=klev
    ELSE
       jk=1
    ENDIF

    ! Open cdf dataset
    istatus=NF90_OPEN(cdfile,NF90_NOWRITE,incid)

    ! read time dimension
    istatus=NF90_INQ_DIMID(incid, cn_t, id_t)
    istatus=NF90_INQUIRE_DIMENSION(incid,id_t, len=iint)

    ! Allocate space
    ALLOCATE (ztime(iint), zval(iint) )

    ! gettime
    istatus=NF90_INQ_VARID(incid,cn_vtimec,id_var)
    istatus=NF90_GET_VAR(incid,id_var,ztime,(/1/),(/iint/) )

    ! read variable
    istatus=NF90_INQ_VARID(incid,cdvar,id_var)

    ! look for scale_factor and add_offset attribute:
    istatus=NF90_GET_ATT(incid,id_var,'add_offset',ztmp)
    IF ( istatus == NF90_NOERR ) zao = ztmp
    istatus=NF90_GET_ATT(incid,id_var,'scale_factor',ztmp)
    IF ( istatus == NF90_NOERR ) zsf = ztmp

    ! get number of dimension of the variable ( either x,y,t or x,y,z,t )
    istatus=NF90_INQUIRE_VARIABLE(incid,id_var, ndims=indim)
    IF ( indim == 3 ) THEN
       istatus=NF90_GET_VAR(incid,id_var,zval,(/kilook,kjlook,1/),(/1,1,iint/) )
    ELSE IF ( indim == 4 ) THEN
       istatus=NF90_GET_VAR(incid,id_var,zval,(/kilook,kjlook,jk,1/),(/1,1,1,iint/) )
    ELSE 
       PRINT *,'  ERROR : variable ',TRIM(cdvar),' has ', indim, &
            &       ' dimensions !. Only 3 or 4 supported'
       STOP
    ENDIF

    ! convert to physical values
    zval=zval*zsf + zao

    ! display results :
    DO jt=1,iint
       PRINT *,ztime(jt)/86400., zval(jt)
    ENDDO

    istatus=NF90_CLOSE(incid)

  END SUBROUTINE gettimeseries

  LOGICAL FUNCTION chkfile (cd_file) 
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION chkfile  ***
    !!
    !! ** Purpose :  Check if cd_file exists.
    !!               Return false if it exists, true if it does not
    !!               Do nothing is filename is 'none'
    !!
    !! ** Method  : Doing it this way allow statements such as
    !!              IF ( chkfile( cf_toto) ) STOP  ! missing file
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*), INTENT(in) :: cd_file

    LOGICAL                      :: ll_exist
    !!----------------------------------------------------------------------
    IF ( TRIM(cd_file) /= 'none')  THEN 
       INQUIRE (file = TRIM(cd_file), EXIST=ll_exist)

       IF (ll_exist) THEN
          chkfile = .false.
       ELSE
          PRINT *, ' File ',TRIM(cd_file),' is missing '
          chkfile = .true.
       ENDIF
    ELSE  
       chkfile = .false.  ! 'none' file is not checked
    ENDIF

  END FUNCTION chkfile

  LOGICAL FUNCTION chkvar (cd_file, cd_var)
    !!---------------------------------------------------------------------
    !!                  ***  FUNCTION chkvar  ***
    !!
    !! ** Purpose :  Check if cd_var exists in file cd_file.
    !!               Return false if it exists, true if it does not
    !!               Do nothing is varname is 'none'
    !!
    !! ** Method  : Doing it this way allow statements such as
    !!              IF ( chkvar( cf_toto, cv_toto) ) STOP  ! missing var
    !!
    !!----------------------------------------------------------------------
    CHARACTER(LEN=*), INTENT(in) :: cd_file
    CHARACTER(LEN=*), INTENT(in) :: cd_var

    INTEGER(KIND=4)              :: istatus
    INTEGER(KIND=4)              :: incid, id_t, id_var

    !!----------------------------------------------------------------------
    IF ( TRIM(cd_var) /= 'none')  THEN
    
       ! Open cdf dataset
       istatus = NF90_OPEN(cd_file, NF90_NOWRITE,incid)
       ! Read variable
       istatus = NF90_INQ_VARID(incid, cd_var, id_var)

       IF ( istatus == NF90_NOERR ) THEN
          chkvar = .false.
       ELSE
          PRINT *, ' '
          PRINT *, ' Var ',TRIM(cd_var),' is missing in file ',TRIM(cd_file)
          chkvar = .true.
       ENDIF
       
       ! Close file
       istatus = NF90_CLOSE(incid) 
    ELSE
       chkvar = .false.  ! 'none' file is not checked
    ENDIF

  END FUNCTION chkvar

END MODULE cdfio


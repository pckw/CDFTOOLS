#!/bin/ksh
# @ wall_clock_limit = 10:00:00
# @ job_name   = vt-YYYY
# @ as_limit = 1gb
# @ output     = $(job_name).$(jobid)
# @ error      =  $(job_name).$(jobid)
# @ notify_user = molines@hmg.inpg.fr
# @ notification = error
# @ queue

### OAR is valid on ZEPHIR
#OAR -n metavt
#OAR -l /nodes=1/cpu=1,walltime=5:00:00
#OAR -E METAVT.%jobid%
#OAR -O METAVT.%jobid%

### QSUB is valid on JADE
#PBS -N metavt
#PBS -l select=1:ncpus=8:mpiprocs=1
#PBS -l walltime=02:00:00
#PBS -l place=scatter:excl
#PBS -M molines@hmg.inpg.fr
#PBS -mb -me

#################################################################################
# This script is used to compute time mean averages for DRAKKAR model output.
# It replaces an older script which was also computing quarterly means.
# In this script mean quadratic terms US UT VS VT are computed from 5 days averages
# All customisable variable are set in Part I.
#
# $Rev$
# $Date$
# $Id$
################################################################################

set -x
. $HOME/.profile
P_CDF_DIR=$PDIR/RUN_CCOONNFF/CCOONNFF-CCAASSEE/CTL/CDF
. $P_CDF_DIR/config_def.ksh
chkdir $TMPDIR

cp $P_CDF_DIR/config_def.ksh $TMPDIR
cp $P_CDF_DIR/function_def.ksh $TMPDIR
cd $TMPDIR


# Part I : setup config dependent names
#--------------------------------------
. ./config_def.ksh   # config_def.ksh may be a link to an existing configuration file

# Part II  define some usefull functions
#---------------------------------------
. ./function_def.ksh # function_def.ksh may be a link to customizable function file

# Part III : main loops : no more customization below
#-----------------------------------------------------
# set up list of years to process
# Metamoy meta script will subtitute YYYY and YYYE with correct begining and ending years
YEARS=YYYY
YEARE=YYYE
LOCAL_SAVE=${LOCAL_SAVE:=0}

YEARLST=""
y=$YEARS

while (( $y <= $YEARE )) ; do
  YEARLST="$YEARLST $y "
  y=$(( y + 1 ))
done

#
CONFCASE=${CONFIG}-${CASE}

# always work in TMPDIR ! not in the data dir as file will be erased at the end of the script !
cd $TMPDIR
mkdir MONTHLY
   if [ $LOCAL_SAVE = 1 ] ; then
    chkdir $WORKDIR/$CONFIG
    chkdir $WORKDIR/$CONFIG/${CONFCASE}-MEAN
   fi

for YEAR in $YEARLST ; do
   SDIR=${CONFIG}/${CONFCASE}-S/$YEAR
   MDIR=$PREF/${CONFIG}/${CONFCASE}-MEAN/$YEAR
   chkdirg $MDIR
   if [ $LOCAL_SAVE = 1 ] ; then
    chkdir $WORKDIR/$CONFIG/${CONFCASE}-MEAN/$YEAR
   fi

 # Monthly mean
 #
 for month in 01 02 03 04 05 06 07 08 09 10 11 12  ; do
   getmonth $month gridT
   getmonth $month gridU
   getmonth $month gridV

   list=''
   for f in ${CONFCASE}_y${YEAR}m${month}d??_gridT.nc ; do
     tag=$( echo $f | awk -F_ '{print $2}' )
     list="$list $tag"
   done

   $CDFTOOLS/cdfvT $CONFCASE $list
   putvtmonth $month
   \rm ${CONFCASE}_y${YEAR}m${month}d??_grid[UVT].nc
 done

 # annual mean  (uses a ponderation to compute the exact annual mean ). ! suppose 5 day averages when creating monthly mean
 cd $TMPDIR/MONTHLY
 $CDFTOOLS/cdfmoy_annual ${CONFCASE}_y${YEAR}m??_VT.nc
 putvtannual
 
 # clean directory for eventually next year:
 \rm ${CONFCASE}_y${YEAR}m??_VT.nc
 cd $TMPDIR
done
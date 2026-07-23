#!/bin/bash -x

#script to run generic lhe generation tarballs
#kept as simply as possible to minimize need
#to update the cmssw release
#(all the logic goes in the run script inside the tarball
# on frontier)
#J.Bendavid

#exit on first error
set -e

echo "   ______________________________________     "
echo "         Running Generic Tarball/Gridpack     "
echo "   ______________________________________     "

path=${1}
echo "gridpack tarball path = $path"

nevt=${2}
echo "%MSG-MG5 number of events requested = $nevt"

rnum=${3}
echo "%MSG-MG5 random seed used for the run = $rnum"

ncpu=${4}
echo "%MSG-MG5 thread count requested = $ncpu"

use_singularity=0

for arg in "${@:5}"; do
  if [ "$arg" = "use_singularity" ]; then
      use_singularity=1
  else
      extra_args+=("$arg")
  fi
done

# Rebuild all positional parameters excluding the use_singularity keyword
set -- "$path" "$nevt" "$rnum" "$ncpu" "${extra_args[@]}"

echo "%MSG-MG5 residual/optional arguments = ${@:5}"

if [ -n "${5}" ]; then
  use_gridpack_env=${5}
  echo "%MSG-MG5 use_gridpack_env = $use_gridpack_env"
fi

if [ -n "${6}" ]; then
  scram_arch_version=${6}
  echo "%MSG-MG5 override scram_arch_version = $scram_arch_version"
fi

if [ -n "${7}" ]; then
  cmssw_version=${7}
  echo "%MSG-MG5 override cmssw_version = $cmssw_version"
fi

LHEWORKDIR=`pwd`

if [ "$use_gridpack_env" = false -a -n "$scram_arch_version" -a -n  "$cmssw_version" ]; then
  echo "%MSG-MG5 CMSSW version = $cmssw_version"
  export SCRAM_ARCH=${scram_arch_version}
  scramv1 project CMSSW ${cmssw_version}
  cd ${cmssw_version}/src
  eval `scramv1 runtime -sh`
  cd $LHEWORKDIR
fi

# we should now have SCRAM_ARCH defined, check if gridpack has /SCRAM_ARCH/:
if [[ ${path} == */SCRAM_ARCH/* ]]; then
   echo "Gridpack with heterogeneous architecture support"
   gridpath="${path/\/SCRAM_ARCH\//"/$SCRAM_ARCH/"}"
   if [ ! -f "$gridpath" ]; then
      echo "No gridpack for ${SCRAM_ARCH}"
      tmparch="${SCRAM_ARCH#*_}"
      subarch="*_${tmparch%_*}_*"
      gridpaths=`ls -1 ${path/\/SCRAM_ARCH\//"/$subarch/"} 2>/dev/null`
      if [ -z "$gridpaths" ]; then
         echo "No gridpack for ${subarch}, exiting"
         exit 1
      else
         scram_osys="${SCRAM_ARCH%%_*}"
         scram_osno=`echo "$scram_osys" | grep -Eo "[0-9]*"`
         scram_comp="${SCRAM_ARCH##*_}"
         scram_cmpn=`echo "$scram_comp" | grep -Eo "[0-9]*"`
         gridstem="${path%%SCRAM_ARCH/*}"
         for gridpath in $gridpaths; do
            gridarch=`echo "${gridpath##$gridstem}" | cut -d/ -f1`
            gridosys="${gridarch%%_*}"
            gridosno=`echo "$gridosys" | grep -Eo "[0-9]*"`
            gridcomp="${gridarch##*_}"
            gridcmpn=`echo "$gridcomp" | grep -Eo "[0-9]*"`
            if [ ${gridosno:-0} -le ${scram_osno:-0} ] && \
               [ ${gridcmpn:-0} -le ${scram_cmpn:-0} ]; then
                  echo "Using ${gridarch}"
                  break
            else
               echo "Inappropriate ${gridarch}"
            fi
         done
      fi
   else
      echo "Using ${SCRAM_ARCH}"
   fi
else
   echo "Mono-architecture gridpack"
   gridpath=$path
fi

if [[ -d lheevent ]]
    then
    echo 'lheevent directory found'
    echo 'Setting up the environment'
    rm -rf lheevent
fi
mkdir lheevent; cd lheevent

#untar the tarball directly from cvmfs
tar -xaf ${gridpath} 

# If TMPDIR is unset, set it to the condor scratch area if present
# and fallback to /tmp
export TMPDIR=${TMPDIR:-${_CONDOR_SCRATCH_DIR:-/tmp}}

# define singularity
if [ "$use_gridpack_env" != false ]; then
    if [ -n "$scram_arch_version" ]; then
        sing=$(echo ${scram_arch_version} | sed -E 's/^[^0-9]*([0-9]{1,2}).*/\1/')
    elif egrep -q "scram_arch_version=[^$]" runcmsgrid.sh; then
        sing=$(grep "scram_arch_version=[^$]" runcmsgrid.sh | sed -E 's/^[^0-9]*([0-9]{1,2}).*/\1/')
    fi
    if [ -n "${sing}" ]; then
        sing="cmssw-el"${sing}" --"
    fi
fi

#generate events
if [ "$use_singularity" -eq 1 ]; then
    echo "Using singularity for running events"
    ${sing} ./runcmsgrid.sh $nevt $rnum $ncpu ${@:5}
else
    ./runcmsgrid.sh $nevt $rnum $ncpu ${@:5}
fi

mv cmsgrid_final.lhe $LHEWORKDIR/

cd $LHEWORKDIR

#cleanup working directory (save space on worker node for edm output)
rm -rf lheevent

exit 0


#!/bin/bash -e

module purge
ml PrgEnv-cray/8.3.3 
ml cpe/23.03
ml craype-x86-trento craype-accel-amd-gfx90a

module use /pfs/lustrep2/projappl/project_462000125/samantao-public/mymodules
module load rocm/5.4.3

wd=$(pwd)

set -x

#
# Make sure we have a recent cmake
#
if [ ! -f $wd/cmake/bin/cmake ] ; then
  cd $wd
  rm -rf $wd/cmake
  mkdir $wd/cmake
  curl -LO https://github.com/Kitware/CMake/releases/download/v3.27.7/cmake-3.27.7-linux-x86_64.sh
  bash cmake-3.27.7-linux-x86_64.sh --skip-license --prefix=$wd/cmake 
  rm -rf cmake-3.27.7-linux-x86_64.sh
fi
export PATH=$wd/cmake/bin:$PATH

#
# Download code.
#
if [ ! -d $wd/src ] ; then
    git clone -b hip_improvements https://github.com/LatticeQCD/SIMULATeQCD $wd/src
fi
sed -i 's/Wno-deprecated-copy-with-user-provided-copy/Wno-deprecated-copy/g' $wd/src/CMakeLists.txt 

#
# Configure code.
#
export CXX=$ROCM_PATH/llvm/bin/clang++

if [ ! -f $wd/src/build/Makefile ] ; then
    rm -rf $wd/src/build
    mkdir $wd/src/build
    cd $wd/src/build

    export CMAKE_PREFIX_PATH=$CRAY_MPICH_DIR:$CMAKE_PREFIX_PATH

    cmake $wd/src \
    -DCMAKE_PREFIX_PATH=$ROCM_PATH \
    -DARCHITECTURE="gfx90a" \
    -DAMDGPU_TARGETS="gfx90a" \
    -DUSE_GPU_AWARE_MPI=ON \
    -DUSE_GPU_P2P=OFF \
    -DBACKEND="hip_amd" \
    -DUSE_MARKER=ON \
    -DUSE_TILED_MULTIRHS=ON \
    -DCMAKE_CXX_COMPILER=$CXX \
    -DCMAKE_HIP_COMPILER=$CXX \
    -DCMAKE_CXX_FLAGS="-g -ggdb" \
    -DCMAKE_EXE_LINKER_FLAGS="$PE_MPICH_GTL_DIR_amd_gfx90a $PE_MPICH_GTL_LIBS_amd_gfx90a"
fi

#
# Build
#
cd $wd/src/build
nice make -j VERBOSE=1 V=1 multiRHSProf


c=fe
MYMASKS1="0x${c}000000000000,0x${c}00000000000000,0x${c}0000,0x${c}000000,0x${c},0x${c}00,0x${c}00000000,0x${c}0000000000"

mkdir -p $wd/runs
cd $wd/runs

Nodes=1
srun \
  -N $Nodes \
  -n $((Nodes*8)) \
  --cpu-bind=mask_cpu:$MYMASKS1 \
  --gpus $((Nodes*8)) \
  $wd/src/build/profiling/multiRHSProf

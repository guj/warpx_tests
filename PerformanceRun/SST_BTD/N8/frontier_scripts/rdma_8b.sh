#!/usr/bin/env bash

#SBATCH -A csc143
#SBATCH -J warpx
#SBATCH -t 00:10:00
#SBATCH -p batch
#SBATCH --ntasks-per-node=8
# Due to Frontier's Low-Noise Mode Layout only 7 instead of 8 cores are available per process
# https://docs.olcf.ornl.gov/systems/frontier_user_guide.html#low-noise-mode-layout
#SBATCH --cpus-per-task=7
#SBATCH --gpus-per-task=1
#SBATCH --gpu-bind=closest
#SBATCH -N 12
# #SBATCH -o %x-%j.out
#SBATCH -o log.rdma8b.o%j
#SBATCH -e log.rdma8b.e%j


# load cray libs and ROCm libs
#export LD_LIBRARY_PATH=${CRAY_LD_LIBRARY_PATH}:${LD_LIBRARY_PATH}

# From the documentation:
# Each Frontier compute node consists of [1x] 64-core AMD EPYC 7A53
# "Optimized 3rd Gen EPYC" CPU (with 2 hardware threads per physical core) with
# access to 512 GB of DDR4 memory.
# Each node also contains [4x] AMD MI250X, each with 2 Graphics Compute Dies
# (GCDs) for a total of 8 GCDs per node. The programmer can think of the 8 GCDs
# as 8 separate GPUs, each having 64 GB of high-bandwidth memory (HBM2E).

# note (5-16-22 and 7-12-22)
# this environment setting is currently needed on Frontier to work-around a
# known issue with Libfabric (both in the May and June PE)
#export FI_MR_CACHE_MAX_COUNT=0  # libfabric disable caching
# or, less invasive:
export FI_MR_CACHE_MONITOR=memhooks  # alternative cache monitor

# Seen since August 2023
# OLCFDEV-1597: OFI Poll Failed UNDELIVERABLE Errors
# https://docs.olcf.ornl.gov/systems/frontier_user_guide.html#olcfdev-1597-ofi-poll-failed-undeliverable-errors
export MPICH_SMP_SINGLE_COPY_MODE=NONE
export FI_CXI_RX_MATCH_MODE=software

# note (9-2-22, OLCFDEV-1079)
# this environment setting is needed to avoid that rocFFT writes a cache in
# the home directory, which does not scale.
export ROCFFT_RTC_CACHE_PATH=/dev/null

export OMP_NUM_THREADS=1
export WARPX_NMPI_PER_NODE=8
export SIM_NNODES=8
export SST_TRANSPORT=rdma
export TOTAL_NMPI=$(( ${SIM_NNODES} * ${WARPX_NMPI_PER_NODE} ))

module list
date

pwd=`pwd`
echo ${pwd}

export BPLS=${pwd}/../../bpls
export EXE=${pwd}/../../../EXE
export MONITOR=${pwd}/../mpi_monitor_b.sh

### SST export
export SstVerbose=5
export MPICH_GPU_SUPPORT_ENABLED=0

### running code 

echo "bpls=", ${BPLS}
echo "EXE=", ${EXE}
echo "MONITOR", ${MONITOR}


checkData()
{
    bpPath=$1
    jsonDestination=$2
    prefix=$3
    desc=$4

    fileName=${prefix}_${desc}
    if [ -f ${bpPath}/*.json ]; then
	mv ${bpPath}/*json ${JSON_DIR}/${jsonDestination}/${fileName}
	echo "Time of:  bpls  ${bpPath} ($desc) "
	time  ${BPLS}  ${bpPath} >> ${MISC_DIR}/${jsonDestination}/${fileName}_bpls

	idVarName=`grep id ${MISC_DIR}/${jsonDestination}/${fileName}_bpls | head -1 | awk '{print $2 }' `
	
	if [[ $desc == never_tls_rank ]]
	then
	    echo "Time of:  bpls  ${bpPath} -t  .. ($desc) .."
            #time ${BPLS}  ${bpPath} -d /data/0/particles/beam/id | tail  >> ${MISC_DIR}/${jsonDestination}/${fileName}_bid_bpls_d
	    time ${BPLS}  ${bpPath} -d ${idVarName} | tail  >> ${MISC_DIR}/${jsonDestination}/${fileName}_bid_bpls_d
	fi
    fi
    
    du -m ${bpPath}
    ls -lt ${bpPath} |wc
    
    #rm -rf ${bpPath}/data*
}

runMe()
{
    export OPENPMD_ADIOS2_BP5_TypeAgg=$1
    echo "export OPENPMD_ADIOS2_BP5_TypeAgg=$1"
    aggDesc=$2
    export OPENPMD_ADIOS2_BP5_NumAgg=$3
    echo "export OPENPMD_ADIOS2_BP5_NumAgg=$3"
    
    cp ${INPUTS} ${MISC_DIR}
    cp ${MONITOR} ${MISC_DIR}
    OP_NETWORK_MPIDP="--network=single_node_vni,job_vni"
    #srun -N${SLURM_JOB_NUM_NODES} -n${TOTAL_NMPI} --ntasks-per-node=${WARPX_NMPI_PER_NODE} ${EXE} ${INPUTS}  > ${OUTPUT_DIR}/output.${key}_${aggDesc} &
    srun -N${SIM_NNODES} -n${TOTAL_NMPI} ${OP_NETWORK_MPIDP} --ntasks-per-node=${WARPX_NMPI_PER_NODE} --exclusive ${EXE} ${INPUTS}  > ${OUTPUT_DIR}/output.${key}_${aggDesc} 2>&1 &
    echo "now monitor ${MONITOR}  ${OUTPUT_DIR}/output.${key}_${aggDesc} diags/diag1 .sst ${SST_TRANSPORT} 8 2 2 2"
    pwd
    bash  ${MONITOR}  ${OUTPUT_DIR}/output.${key}_${aggDesc} diags/diag1 .sst ${SST_TRANSPORT} 8 "2 2 2"
    ## move to 
    #mv *.bp* diags/diag1
    if [[ ${aggDesc} != *"nullcore"* ]]; then
      pushd diags
      for dir in *
      do
        pushd ${dir}
        for n in open*bp*
        do
           echo "   ${n}"
           checkData ${n} ${key} ${dir}_${n} ${aggDesc}
        done
        popd
      done
      popd
    fi
}

# encoding
ENC=g
key=default

mkdir ${SLURM_JOBID}

useConfig()
{
    ENC=$1
    key=$2
    deco=$3

    if [ -z "$2" ]; then
	key=default
    fi
    
    # executable & inputs file or python interpreter & PICMI script here
    INPUTS=${pwd}/../../../inputs_3d/opmd/btd_${key}_sst/${SST_TRANSPORT}/input.n${SIM_NNODES}${ENC}

    mkdir   ${SLURM_JOBID}/${ENC}_${SLURM_JOBID}_${deco}${key}_${SIM_NNODES}n
    pushd   ${SLURM_JOBID}/${ENC}_${SLURM_JOBID}_${deco}${key}_${SIM_NNODES}n

    workingDir=`pwd`
    OUTPUT_DIR=${workingDir}/outs
    JSON_DIR=${workingDir}/jsons
    MISC_DIR=${workingDir}/misc
    
    mkdir ${OUTPUT_DIR}
    mkdir ${JSON_DIR}
    mkdir ${JSON_DIR}/${key}    
    mkdir ${MISC_DIR}
    mkdir ${MISC_DIR}/${key}

    #if [ -z "$2" ]; then
    if [ "$3" = "nullcore" ]; then
	echo "Nullcore Test"
	export OPENPMD_ADIOS2_ENGINE=nullcore
	runMe TwoLevelShm          tls_rank_nullcore   ${TOTAL_NMPI}
	export OPENPMD_ADIOS2_ENGINE=BP5	
    else    
	date

	runMe TwoLevelShm          tls_rank   ${TOTAL_NMPI} 
	runMe EveryoneWritesSerial ews_rank   ${TOTAL_NMPI} 
	
	date
    fi
    
    popd
}

export OPENPMD_ADIOS2_ASYNC_WRITE=0
#useConfig f joined nullcore
useConfig f default
#useConfig f flatten
#useConfig f joined 
#useConfig f default nullcore









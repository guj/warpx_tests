#!/bin/bash -l
# Copyright 2021-2023 Axel Huebl, Kevin Gott
#
# This file is part of WarpX.
#
# License: BSD-3-Clause-LBNL

#SBATCH -t 00:10:00
#SBATCH -N 8
#SBATCH -J flatten
#SBATCH -A m4272_g
#SBATCH -q regular
# A100 40GB (most nodes)
#SBATCH -C gpu
# A100 80GB (256 nodes)
#S BATCH -C gpu&hbm80g
#SBATCH --exclusive
#SBATCH --cpus-per-task=32
# ideally single:1, but NERSC cgroups issue
#SBATCH --gpu-bind=none
#SBATCH --ntasks-per-node=4
#SBATCH --gpus-per-node=4
#SBATCH -o log.8.o%j
#SBATCH -e log.8.e%j


# GPU-aware MPI optimizations
GPU_AWARE_MPI="amrex.use_gpu_aware_mpi=1"

# CUDA visible devices are ordered inverse to local task IDs
#   Reference: nvidia-smi topo -m

module list
date

pwd=`pwd`
echo ${pwd}

export BPLS=${pwd}/../../../bpls
export EXE=${pwd}/../../../EXE
#export MONITOR=${pwd}/../mpi_monitor.sh
echo "bpls=", ${BPLS}
echo "EXE=", ${EXE}
#echo "MONITOR", ${MONITOR}

export SIM_NNODES=8
export SST_TRANSPORT=wan

numNodes=${SIM_NNODES}
numCorePerNode=${SLURM_NTASKS_PER_NODE}
TOTAL_NMPI=$((numNodes * numCorePerNode))


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
    ls -lt ${bpPath} | wc
    ls -laR ${bpPath} | grep -v '^d' | grep -v ' 0 '
    
    rm -rf ${bpPath}/data*
}

runMe()
{
    export OPENPMD_ADIOS2_BP5_TypeAgg=$1
    echo "export OPENPMD_ADIOS2_BP5_TypeAgg=$1"
    aggDesc=$2
    export OPENPMD_ADIOS2_BP5_NumAgg=$3
    ## NumSubFiles for DSB
    export OPENPMD_ADIOS2_BP5_NumSubFiles=$3
    echo "export OPENPMD_ADIOS2_BP5_NumAgg=$3"
    
    cp ${INPUTS} ${MISC_DIR}
    #cp ${MONITOR} ${MISC_DIR}  
    ## frontier
    ## srun -N${SLURM_JOB_NUM_NODES} -n${TOTAL_NMPI} --ntasks-per-node=${WARPX_NMPI_PER_NODE} ${EXE} ${INPUTS}  > ${OUTPUT_DIR}/output.${key}_${aggDesc}
    #srun --cpu-bind=cores bash -c "    
    srun -N${SIM_NNODES} -n${TOTAL_NMPI} --ntasks-per-node=${numCorePerNode} --cpu-bind=cores bash -c "
    export CUDA_VISIBLE_DEVICES=\$((3-SLURM_LOCALID));
    ${EXE} ${INPUTS} ${GPU_AWARE_MPI}" \
	 > ${OUTPUT_DIR}/output.${key}_${aggDesc} 
    #echo "${MONITOR}  ${OUTPUT_DIR}/output.${key}_${aggDesc} diags/diag1 .sst"
    #pwd
    #${MONITOR}  ${OUTPUT_DIR}/output.${key}_${aggDesc} diags/diag1 .sst

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
    #INPUTS=${pwd}/../../../inputs_3d/opmd/btd_${key}/input.n${SLURM_NNODES}${ENC}
    INPUTS=${pwd}/../../../inputs_3d/opmd/btd_${key}/bp/input.n${SIM_NNODES}${ENC}

    mkdir   ${SLURM_JOBID}/${ENC}_${SLURM_JOBID}_${deco}${key}_${SLURM_NNODES}n
    pushd   ${SLURM_JOBID}/${ENC}_${SLURM_JOBID}_${deco}${key}_${SLURM_NNODES}n

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
    #if [ "$3" = "nullcore" ]; then
    if [[ "$3" = nullcore* ]]; then
	echo "Nullcore Test"
	export OPENPMD_ADIOS2_ENGINE=nullcore
	runMe TwoLevelShm          tls_rank_nullcore   ${TOTAL_NMPI}
	export OPENPMD_ADIOS2_ENGINE=BP5	
    else    
	date

	runMe TwoLevelShm          tls_rank   ${TOTAL_NMPI} 
	runMe EveryoneWritesSerial ews_rank   ${TOTAL_NMPI}
	runMe DataSizeBased        dsb_rank   ${TOTAL_NMPI} 	
	
	date
    fi
    
    popd
}

#export OPENPMD_ADIOS2_ASYNC_WRITE=1
#useConfig f default async
#useConfig f flatten async
#useConfig f joined async
#    # never run flatten_joined useConfig f flatten_joined async
#    # never run flatten_joined useConfig g flatten_joined async

export OPENPMD_ADIOS2_ASYNC_WRITE=0

## run a nullcore0 to avoid first job punishment
## seen in some large warpx runs
useConfig f default nullcore0
useConfig f default nullcore
#useConfig f flatten 
#useConfig f joined nullcore
useConfig f default
#useConfig f flatten
#useConfig f joined
#useConfig f joined nullcore


#!/bin/bash

# Check if exactly two parameters are provided
if [ $# -le 2 ]; then
    echo "Usage: $0 <command> <directory>"
    exit 1
fi

OUTPUT=$1
DIRECTORY=$2
FILE_EXTENSION=$3

SSTDIR=${DIRECTORY}
ADIOS_REORG=/lustre/orion/csc143/scratch/junmin/2025-May/binary/adios/bin/adios2_reorganize
#ADIOS_REORG=/lustre/orion/csc143/scratch/junmin/2025-May/binary/adios/bin/adios2_reorganize_mpi

# Verify directory exists
#if [ ! -d "$DIRECTORY" ]; then
#fi
while [ ! -d "$DIRECTORY" ]; do
    echo "Error: Directory '$DIRECTORY' does not exist"      
    sleep 0.5
    #exit 1
done

while [ -z "$(ls -1 "$DIRECTORY"/*${FILE_EXTENSION} 2>/dev/null)" ]; do
    echo "Waiting for a ${FILE_EXTENSION} file to appear in $DIRECTORY..."
    sleep 0.5
done

echo "======  found: ", "$DIRECTORY", "with file ext: ", ${FILE_EXTENSION}
# Normalize file extension (remove leading dot if present)
FILE_EXTENSION=${FILE_EXTENSION#.}

# Get initial list of files
#previous_files=$(ls -1 "$DIRECTORY"/*."$FILE_EXTENSION" 2>/dev/null | xargs -n 1 basename)
#echo $previous_files
previous_files=""
# Check if command is running and monitor for new files
#while ps aux | grep -v grep | grep "$COMMAND" > /dev/null; do
while ! grep -q "Total" "$OUTPUT"; do
    echo "====== waitting "
    current_files=$(ls -1 "$DIRECTORY"/*."$FILE_EXTENSION" 2>/dev/null | xargs -n 1 basename)
    
    # Compare current files with previous files
    diff_output=$(diff <(echo "$previous_files") <(echo "$current_files") | grep '^>')
    
    # Print new files (lines starting with ">")
    if [ ! -z "$diff_output" ]; then
	echo "==============="
        echo "$diff_output" | while read -r line; do
            # Extract filename (remove "> " prefix)
            filename=$(echo "$line" | cut -c 3-)
            echo "New file detected: $filename in $DIRECTORY, see ${SSTDIR}/$filename"
            suffix=".sst"
            result="${filename%$suffix}"
            #python3 sstReader.py ${SSTDIR}/$filename &
	    pwd
            echo "  calling reorg: ${ADIOS_REORG}  ${SSTDIR}/${result} ${result}.bp5 SST space BPFile space"	    
            #srun -N 1 ${ADIOS_REORG}  ${SSTDIR}/${result}  ${result}.bp5 SST "verbose=5" BPFile ""  &
	    #srun --nodes=1 --ntasks=1 --exclusive ${ADIOS_REORG}  ${SSTDIR}/${result}  ${result}.bp5 SST "verbose=5" BPFile "Substreams=10"  > out.${result}.reader 2>&1 &
	    srun --nodes=1 --ntasks=1 --exclusive ${ADIOS_REORG}  ${SSTDIR}/${result}  ${result}.bp5 SST "" BPFile "Substreams=10"  > out.${result}.reader 2>&1 &
	    echo "sent out client for ${result}.bp5 "
            #$(python3 sstReader.py /Users/dec2023/software/ECP-AMReX/TestApplications/WarpX/perlmutter/nov/Tests-frontier/sstTest/diags/diag1/openpmd_000003
        done
    fi
    
    # Update previous files list
    previous_files="$current_files"
    
    # Sleep briefly to avoid excessive CPU usage
    sleep 0.5
done

wait
mv *.bp5 ${SSTDIR}

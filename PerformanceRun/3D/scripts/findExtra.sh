 
#!/bin/bash

compute_time_diff() {    
path="$1"

if [[ ! -f "$path" ]]; then
  echo "Error: File not found: $path" >&2
  exit 1
fi

evolveTime=$(awk '/This step/ {line=$4} END {print line}' "$path")
total=$(awk '/Total Time/ {print $4}' "$path")

# Compute difference
diff=$(awk -v t="$total" -v e="$evolveTime" 'BEGIN {printf "%.10f", t - e}')

# Output
echo "Evolve Time: $evolveTime"
echo "Total Time:  $total"
echo "Difference (Total - Evolve): $diff"
}

job_dir=$1
echo "null"
compute_time_diff ${job_dir}/*null*/outs/*

echo "ews"
compute_time_diff ${job_dir}/*default*/outs/*ews*

echo "tls"
compute_time_diff ${job_dir}/*default*/outs/*tls*

#!/bin/bash

# 1. Defaults for the sweep
MIN=4
MAX=10
OTHER_ARGS=()

# 2. Parse arguments to get the range
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --min) MIN="$2"; shift 2 ;;
        --max) MAX="$2"; shift 2 ;;
        *) OTHER_ARGS+=("$1"); shift 1 ;; # Save everything else (radius, inertia, etc.)
    esac
done

echo "Starting sweep from $MIN to $MAX atoms..."

# 3. The Loop
for (( a=$MIN; a<=$MAX; a++ )); do
    echo "Submitting job for atoms=$a"
    # This sends the job to the queue with all your extra flags
    qsub jobr.sh --atoms "$a" "${OTHER_ARGS[@]}"
done

echo "Done. Use 'qstat' to monitor progress."

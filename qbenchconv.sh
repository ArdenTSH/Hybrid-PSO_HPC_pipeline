#!/bin/bash -l
#$ -pe smp 8
#$ -l gpu=1
#$ -l mem=8G
#$ -l h_rt=6:00:00
#$ -l tmpfs=10G
#$ -cwd
#$ -N pso_c6_bench
#$ -P Free
#$ -A KCL_De_Tomas
#$ -o /dev/null
#$ -e /dev/null

# C6 inertia benchmark — preserves all 40 PSO outputs (4 inertias × 10 runs each)
#
# Output layout:
#   c6_benchmark/
#     ├── linear/    run01_final_pso.xyz, run01_structure_data.json, ..., run10_*
#     ├── adaptive/  ...
#     ├── random/    ...
#     └── chaotic/   ...
#
# json files are CUMULATIVE within each inertia:
#   run01_structure_data.json — 500 iterations  (run 1 only)
#   run07_structure_data.json — 3500 iterations (runs 1–7 concatenated)
#   run10_structure_data.json — 5000 iterations (runs 1–10 concatenated, equivalent
#                                                to the single cumulative json the
#                                                original c11 script produced; use
#                                                this one with the plotting script)
#
# To later run PBE on a chosen structure: pick runNN_final_pso.xyz, take its paired
# runNN_structure_data.json back to the cluster, drop it next to pso_optimizer.py
# as structure_data.json, and run with --restart (no --no-pbe).


module purge
module load gcc-libs/10.2.0 compilers/gnu/10.2.0 cmake/3.27.3 cuda/12.2.2/gnu-10.2.0
module load python/miniconda3/24.3.0-0

source $UCL_CONDA_PATH/etc/profile.d/conda.sh
conda activate pso_env

export PYTHONPATH="${PYTHONPATH}:/home/$(whoami)/gpu4pyscf"



# --- Benchmark configuration ---

ATOMS=5
INERTIAS=(linear adaptive random chaotic)
RUNS=40

SWARM=30
ITER=500
RADIUS=2.4
MIN_DIST=1.35

# --- Output directory ---
WORKDIR="c${ATOMS}_benchmark"
mkdir -p "$WORKDIR"

# --- Main loop ---
for inertia in "${INERTIAS[@]}"; do
    INERTIA_DIR="${WORKDIR}/${inertia}"
    mkdir -p "$INERTIA_DIR"

    # Each inertia starts from a clean cumulative json
    rm -f structure_data.json

    for run in $(seq 1 $RUNS); do
        RUN_TAG=$(printf "run%02d" $run)

        echo ""
        echo "=== ${inertia} | ${RUN_TAG} (${run}/${RUNS}) ==="

        python pso_optimizer.py \
            --element C \
            --atoms "$ATOMS" \
            --swarm-size "$SWARM" \
            --iter "$ITER" \
            --radius "$RADIUS" \
            --min-dist "$MIN_DIST" \
            --inertia "$inertia" \
            --no-pbe

        # Snapshot the cumulative json AFTER this run finishes (so the snapshot
        # contains the appended history of runs 1..run). cp not mv, so the next
        # run can append to the live file.
        cp structure_data.json "${INERTIA_DIR}/${RUN_TAG}_structure_data.json"

        # Keep the per-run xyz, discard the per-run initial.xyz
        mv final_pso_GFN2-xTB.xyz "${INERTIA_DIR}/${RUN_TAG}_final_pso.xyz"
        rm -f initial.xyz
    done

    # Reset before the next inertia so its json starts empty
    rm -f structure_data.json
done

echo ""
echo "=== Benchmark complete ==="
echo "40 xyz + 40 json files in ${WORKDIR}/<inertia>/run<NN>_*"
echo "run10_structure_data.json in each inertia folder is the file your plotting script expects."


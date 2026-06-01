#!/bin/bash -l
#$ -pe smp 8
#$ -l gpu=1
#$ -l mem=8G
#$ -l h_rt=24:00:00
#$ -l tmpfs=10G
#$ -cwd
#$ -N pso_c20_conv
#$ -P Free
#$ -A KCL_De_Tomas
#$ -o /dev/null
#$ -e /dev/null

# ---------------------------------------------------------------------------
# C20 PSO convergence campaign.
#   - round-robin over inertia strategies (balanced coverage if the job dies)
#   - each "sample" = 1 fresh run + JOLTS jolt-restarts (refines its own basin)
#   - runs in parallel, gated at the number of allocated cores
#   - resumable: finished samples leave a DONE marker and are skipped
# Nothing here edits pso_optimizer.py. This script must live next to it.
# ---------------------------------------------------------------------------

module purge
module load gcc-libs/10.2.0 compilers/gnu/10.2.0 cmake/3.27.3 cuda/12.2.2/gnu-10.2.0
module load python/miniconda3/24.3.0-0
source $UCL_CONDA_PATH/etc/profile.d/conda.sh
conda activate pso_env
export PYTHONPATH="${PYTHONPATH}:/home/$(whoami)/gpu4pyscf"

# --- Config: edit here for the common case, OR override at submit time with -v,
#     e.g.  qsub -v ATOMS=24,RADIUS=2.4,PER_INERTIA=20 qconv.sh
ELEMENT=${ELEMENT:-C}
ATOMS=${ATOMS:-20}
RADIUS=${RADIUS:-2.4}
MIN_DIST=${MIN_DIST:-1.35}
SWARM=${SWARM:-40}
METHOD=${METHOD:-GFN2-xTB}

PER_INERTIA=${PER_INERTIA:-40}
INERTIAS=(adaptive random chaotic)

ITER=${ITER:-500}              # length of the fresh exploratory run
JOLTS=${JOLTS:-3}              # number of jolt-restarts per sample
JOLT_ITER=${JOLT_ITER:-100}    # length of each jolt (deliberately short)

MAXPAR=${NSLOTS:-8}            # NSLOTS is set by SGE from `-pe smp`; 1 core/run

# --- Paths (we cd into per-sample scratch, so everything below is absolute)
SUBMIT_DIR=$(pwd)
WORKDIR="${SUBMIT_DIR}/${WORKDIR_NAME:-c${ATOMS}_conv}"
mkdir -p "$WORKDIR"
PROGRESS="${WORKDIR}/campaign_progress.log"
echo "=== campaign start $(date) : ${PER_INERTIA}x${#INERTIAS[@]} samples, ${JOLTS} jolts, ${MAXPAR}-way ===" >> "$PROGRESS"

# ---------------------------------------------------------------------------
run_sample() {
    local inertia=$1 cycle=$2
    local tag; tag=$(printf "run%02d" "$cycle")
    local dest="${WORKDIR}/${inertia}/${tag}"

    # resume: skip anything already completed
    if [[ -f "${dest}/DONE" ]]; then
        echo "[skip] ${inertia}/${tag}" >> "$PROGRESS"
        return 0
    fi
    mkdir -p "$dest"

    # isolated, node-local working dir so the fixed output filenames never collide
    local scratch="${TMPDIR}/${inertia}_${tag}"
    rm -rf "$scratch"; mkdir -p "$scratch"

    (
        cd "$scratch" || exit 1
        echo "[start] ${inertia}/${tag} $(date '+%H:%M:%S')" >> "$PROGRESS"

        # 1) fresh exploratory run
        python "${SUBMIT_DIR}/pso_optimizer.py" \
            --element "$ELEMENT" --atoms "$ATOMS" --swarm-size "$SWARM" \
            --iter "$ITER" --radius "$RADIUS" --min-dist "$MIN_DIST" \
            --inertia "$inertia" --method "$METHOD" --no-pbe || exit 1

        # snapshot the GENUINE starting geometry now: each jolt's --restart run
        # rewrites initial.xyz with a fresh (unused) random structure, so grabbing
        # it after the jolts would record the wrong thing.
        [[ -f initial.xyz ]] && cp initial.xyz "${dest}/initial.xyz"

        # 2) JOLTS jolt-restarts. Each --restart reads THIS dir's structure_data.json,
        #    recenters on the running best (re-injected as particle 0, so the best
        #    can only stay or improve), and re-explores for a short JOLT_ITER.
        for ((j=1; j<=JOLTS; j++)); do
            python "${SUBMIT_DIR}/pso_optimizer.py" \
                --element "$ELEMENT" --atoms "$ATOMS" --swarm-size "$SWARM" \
                --iter "$JOLT_ITER" --radius "$RADIUS" --min-dist "$MIN_DIST" \
                --inertia "$inertia" --method "$METHOD" --no-pbe --restart || exit 1
        done

        # 3) copy out. final_pso is the sample best by construction (monotone jolts).
        cp "final_pso_${METHOD}.xyz" "${dest}/final_pso.xyz" || exit 1
        cp structure_data.json       "${dest}/structure_data.json" || exit 1
    ) > "${dest}/run.log" 2>&1

    # only mark DONE on a real result, so a crashed sample is retried on resume
    if [[ -f "${dest}/final_pso.xyz" ]]; then
        touch "${dest}/DONE"
        echo "[done] ${inertia}/${tag} $(date '+%H:%M:%S')" >> "$PROGRESS"
    else
        echo "[FAIL] ${inertia}/${tag} -- see ${dest}/run.log" >> "$PROGRESS"
    fi
    rm -rf "$scratch"
}

# --- Round-robin scheduler with a concurrency gate.
#     One inertia of each per cycle, so a death at cycle N leaves ~N of every
#     strategy rather than all of one and none of another.
for ((cycle=1; cycle<=PER_INERTIA; cycle++)); do
    for inertia in "${INERTIAS[@]}"; do
        run_sample "$inertia" "$cycle" &
        # hold the number of in-flight samples at MAXPAR
        while (( $(jobs -rp | wc -l) >= MAXPAR )); do wait -n; done
    done
done
wait

echo "=== campaign complete $(date) ===" >> "$PROGRESS"

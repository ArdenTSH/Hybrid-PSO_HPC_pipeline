#!/bin/bash -l

# 1. Hardware and Time Requests (Matched to Prof's script)
#$ -pe smp 8
#$ -l gpu=1
#$ -l mem=8G
#$ -l h_rt=6:00:00
#$ -l tmpfs=10G
#$ -cwd
#$ -N pso_opt


#$ -P Free
#$ -A KCL_De_Tomas

# 2. Log Management (Keeps your root folder clean)
#$ -j y
#$ -o .sge_logs/

# --- Environment Setup ---
module purge
module load gcc-libs/10.2.0 compilers/gnu/10.2.0 cmake/3.27.3 cuda/12.2.2/gnu-10.2.0
module load python/miniconda3/24.3.0-0

source $UCL_CONDA_PATH/etc/profile.d/conda.sh
conda activate pso_env

# Point to the gpu4pyscf directory dynamically
export PYTHONPATH="${PYTHONPATH}:/home/$(whoami)/gpu4pyscf"

# --- Execute the Wrapper ---
# Pass ALL arguments received by this qsub script straight into the wrapper
bash wrapper.sh "$@"

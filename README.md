# PSO HPC Optimization Pipeline (Wrapper, Sweep, Jobr)

This pipeline automates Particle Swarm Optimization (PSO) and PBE calculations on an High-Performance Computing cluster. 

*Prerequisite: This documentation assumes a working knowledge of the base `pso_optimizer.py` script and its arguments.*

## 🚀 Pipeline Architecture

The execution flows from the compute node's execution engine all the way up to the login node's bulk job submitter. 

---
## Directory Structure

The wrapper uses a nested folder tree to preserve the history of every restart without overwriting previous `.xyz` or `.json` files.
```text
root_directory/
├── pso_optimizer.py
├── sweep.sh
├── jobr.sh
├── wrapper.sh
├── master_run_log.csv           <-- Aggregates energies from all steps
└── run/
    ├── run_3A_r_trial1/  <-- Base directory (Auto-named by parameters)
    │   ├── step1/               <-- Initial generation
    │   │   ├── optimization.log
    |   |   ├── pbe_vv10_opt.log
    |   |   ├── initial.xyz
    │   │   ├── structure_data.json
    │   │   ├── final_pso_GFN2-xTB.xyz
    |   |   └── final_pbe_optimized.xyz
    │   └── step2/               <-- Restarted sequence (Inherits JSON from step1)
    │       ├── optimization.log
    |       ├── initial.xyz
    │       ├── structure_data.json
    │       └── final_pso_GFN2-xTB.xyz
    └── run_3A_adaptive_trial2/  <-- Completely fresh trial generated via --new_trial

```

### 1. `wrapper.sh` 
This is made so that the files doesn't get dumped on cwd, and is autosorted into named folders. It acts as a protective shell around `pso_optimizer.py`.

 To support this without overwriting files, the wrapper uses **Trials** and **Steps**. 

* A new argument `--res` numbers the amount of restarts a submission goes through, each restart creates a new **step** folder. `--res 2` will create folder `step1` `step2` `step3`  for 2 restarts. 

* A run is defined by new hyperparameters. Whenever anything is ran, it will look through all the runs and if an exact hyperparameter match is found, it will look into the folder, if no run of the same exact sort is found, a new folder is created.

* If you don't want to do a new step (as it will just do a inertia restart from the last found coordinates), but instead a fresh run from random initialisation, there is **Trial**.

* The `--new_trial` flag ensures a completely fresh swarm is generated in an isolated folder regardless of which trial you are on. 

* The `--trial` argument lets you decide which trial to run restart on, so you can resume running restart on any previous run.

* The Smart Auto-Restart logic relies on these trial folders. By explicitly targeting a trial, the script knows exactly which `structure_data.json` memory to pull forward into a nested `step2` or `step3` folder, perfectly preserving your optimization history across sequential restarts.

* If both `--new_trial` and `--trial` is left out, and it finds previous trials with the identitical hyperparameters, it will take the newest trial and run a restart on it, generating a new **step** folder and placing the results there.

* Logistiically, restart works because when it creates a new step (say step2) file, it copies the .xyz and .json files from the step1 file to step2 and runs restart there. 

#### Wrapper Arguments
| Argument | Default | Description |
| :--- | :--- | :--- |
| `--res` | `0` | Number of automated, sequential restarts to execute in a single submission. |
| `--trial` | `1` | Explicitly target a specific trial folder number for a run or manual restart. |
| `--new_trial` | `False` | Automatically generate a fresh, incremented trial folder to avoid overwriting. |
| *(Python Args)* | *Varies* | All standard args (e.g., `--atoms`, `--inertia`) are passed directly to Python. |

**Direct Usage Example (Interactive Session):**
`bash wrapper.sh --atoms 5 --inertia chaotic --new_trial`
> **What to expect:** The wrapper will scan the `run/` directory. If `run_5C_trial1` exists, it will create `run_5A_chaotic_trial2/step1/`. It will execute Python, save the outputs, and log the final energies into `master_run_log.csv`. If `run_5C_trial1` doesn't exist, it will generate it. 

**Example 2:** `bash wrapper.sh --atoms 5 --swarm-size 30 --iter 500 --inertia chaotic --radius 2.4 --no-pbe  --trial 3 --res 1`
> **What to expect:** The wrapper will scan the `run/` directory. It will look for folder `run_5C_r2.4_s30_i500_nopbe_trial3` and if it exist, it will look into the folder. If it finds `step1` `step2`, it will generate `step3` `step4`.

**Example 3:** `bash wrapper.sh --atoms 7 --inertia adaptive`
> **What to expect:** The wrapper will scan the `run/` directory. It will look for `run_7A_trial1` and if it doesn't exist, it will generate the folder and run the calculation. If it does exist, it will look into the folder, and if it finds `step1` `step2`, it will create `step3` and run a restart. If `run_7A_trial1`, `run_7A_trial2`, `run_7A_trial3` all exist, since there is no specification of `--new_trial` or `--trial`, it will look into the newest trial: `run_7A_trial3` and generate a new `step` folder and run a restart. 

---

### 2. `jobr.sh` 
This is the job queue HPC scheduler via `qsub`. 

**Core Capabilities:**
It requests a node with the same setting as an interactive session and it does the same module purge...etc when we first start an interactive session. 

**Direct Usage Example (Login Node):**
`qsub jobr.sh --atoms 5 --res 2`
> **What to expect:** The scheduler places one job in the queue. Standard logs route to the hidden `.sge_logs/` folder. 

---

### 3. `sweep.sh` (The Bulk Submitter)
A lightweight bash script designed to run strictly on the **Login Node**. It calculates ranges and rapidly fires jobs into the SGE queue.

#### Sweep Arguments
| Argument | Default | Description |
| :--- | :--- | :--- |
| `--min` | *(Required)* | Minimum atom count for the batch loop. |
| `--max` | *(Required)* | Maximum atom count for the batch loop. |
| *(Wrapper Args)* | *Varies* | Any additional arguments typed here are forwarded to `jobr.sh` -> `wrapper.sh`. |

**Direct Usage Example (Login Node):**
`bash sweep.sh --min 3 --max 5 --swarm-size 44 --new_trial`
> **What to expect:** The script instantly submits three distinct jobs to the queue (`atoms=3`, `atoms=4`, `atoms=5`). The actual optimizations run asynchronously, generating brand new trial folders for each atom count.

---



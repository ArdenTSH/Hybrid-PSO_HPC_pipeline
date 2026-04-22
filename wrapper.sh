#!/bin/bash

# 1. Define defaults
ATOMS="5"
INERTIA="adaptive"
RADIUS="2.75"
MIN_DIST="1.35"
SWARM="20"
ITER="1000"
METHOD="GFN2-xTB"
TEMP="300"
NO_PBE=0 
RESTARTS=0
TRIAL="1" 
TRIAL_GIVEN=0
NEW_TRIAL=0

# 2. Parse arguments and hide wrapper-specific flags from Python
CLEAN_ARGS=()

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --res)        RESTARTS="$2"; shift 2 ;; 
        --trial)      TRIAL="$2"; TRIAL_GIVEN=1; shift 2 ;; 
        --new_trial)  NEW_TRIAL=1; shift 1 ;; 
        --atoms)      ATOMS="$2"; CLEAN_ARGS+=("$1" "$2"); shift 2 ;;
        --inertia)    INERTIA="$2"; CLEAN_ARGS+=("$1" "$2"); shift 2 ;;
        --radius)     RADIUS="$2"; CLEAN_ARGS+=("$1" "$2"); shift 2 ;;
        --min-dist)   MIN_DIST="$2"; CLEAN_ARGS+=("$1" "$2"); shift 2 ;;
        --swarm-size) SWARM="$2"; CLEAN_ARGS+=("$1" "$2"); shift 2 ;;
        --iter)       ITER="$2"; CLEAN_ARGS+=("$1" "$2"); shift 2 ;;
        --method)     METHOD="$2"; CLEAN_ARGS+=("$1" "$2"); shift 2 ;;
        --temp)       TEMP="$2"; CLEAN_ARGS+=("$1" "$2"); shift 2 ;;
        --no-pbe)     NO_PBE=1; CLEAN_ARGS+=("$1"); shift 1 ;;
        --restart)    shift 1 ;; # Strip manual restart; wrapper handles it automatically
        *)            CLEAN_ARGS+=("$1"); shift 1 ;;
    esac
done

# 3. Map the inertia strategy
case $INERTIA in
    adaptive) I_CODE="A" ;;
    random)   I_CODE="R" ;;
    linear)   I_CODE="L" ;;
    chaotic)  I_CODE="C" ;;
    constant) I_CODE="Co" ;;
    *)        I_CODE="A" ;;
esac

# 4. Construct the BASE directory name
BASE_DIR="run_${ATOMS}${I_CODE}"

if [[ "$RADIUS" != "2.75" ]]; then BASE_DIR="${BASE_DIR}_r${RADIUS}"; fi
if [[ "$MIN_DIST" != "1.35" ]]; then BASE_DIR="${BASE_DIR}_md${MIN_DIST}"; fi
if [[ "$SWARM" != "20" ]]; then BASE_DIR="${BASE_DIR}_s${SWARM}"; fi
if [[ "$ITER" != "1000" ]]; then BASE_DIR="${BASE_DIR}_i${ITER}"; fi
if [[ "$METHOD" != "GFN2-xTB" ]]; then BASE_DIR="${BASE_DIR}_${METHOD}"; fi
if [[ "$TEMP" != "300" ]]; then BASE_DIR="${BASE_DIR}_t${TEMP}"; fi
if [[ "$NO_PBE" -eq 1 ]]; then BASE_DIR="${BASE_DIR}_nopbe"; fi

MASTER_DIR="run"
mkdir -p "$MASTER_DIR"

# 5. Auto-Detect Trial Logic
if [[ "$NEW_TRIAL" -eq 1 ]]; then
    # Find the NEXT available trial number
    TRIAL=1
    if [[ -d "$MASTER_DIR/$BASE_DIR" ]]; then
        ((TRIAL++))
        while [[ -d "$MASTER_DIR/${BASE_DIR}_trial${TRIAL}" ]]; do
            ((TRIAL++))
        done
    fi
elif [[ "$TRIAL_GIVEN" -eq 0 ]]; then
    # Auto-detect the HIGHEST existing trial to restart
    TRIAL=1
    if [[ -d "$MASTER_DIR/$BASE_DIR" ]]; then
        TEMP_TRIAL=2
        while [[ -d "$MASTER_DIR/${BASE_DIR}_trial${TEMP_TRIAL}" ]]; do
            TRIAL=$TEMP_TRIAL
            ((TEMP_TRIAL++))
        done
    fi
fi

# 6. Lock in the final directory name and step inside
if [[ "$TRIAL" -gt 1 ]]; then 
    DIR_NAME="${BASE_DIR}_trial${TRIAL}"
else 
    DIR_NAME="$BASE_DIR"
fi

echo "Target directory: $MASTER_DIR/$DIR_NAME"
mkdir -p "$MASTER_DIR/$DIR_NAME"
cd "$MASTER_DIR/$DIR_NAME" || exit

# ==========================================
# 7. THE EXECUTION LOOP (Nested sub-folders)
# ==========================================
TOTAL_RUNS=$((RESTARTS + 1))
ALL_PSO_ENGS=""
ALL_PBE_ENGS=""

for (( r=1; r<=TOTAL_RUNS; r++ )); do
    
    # Check for the next available nested step folder
    NEXT_STEP=1
    while [[ -d "step${NEXT_STEP}" ]]; do
        ((NEXT_STEP++))
    done

    mkdir -p "step${NEXT_STEP}"

    # If a previous step exists in this trial, pull its memory forward
    if [[ $NEXT_STEP -gt 1 ]]; then
        PREV_STEP=$((NEXT_STEP - 1))
        
        # Copy JSON and XYZ files silently (errors sent to /dev/null if missing)
        cp "step${PREV_STEP}/structure_data.json" "step${NEXT_STEP}/" 2>/dev/null
        cp "step${PREV_STEP}/final_pso_${METHOD}.xyz" "step${NEXT_STEP}/" 2>/dev/null
        cp "step${PREV_STEP}/final_pbe_optimized.xyz" "step${NEXT_STEP}/" 2>/dev/null
        
        # Step in and run WITH restart (3 levels deep now)
        cd "step${NEXT_STEP}" || exit
        python ../../../pso_optimizer.py "${CLEAN_ARGS[@]}" --restart 2>&1 | tee optimization.log
    else
        # Step in and run FRESH (3 levels deep)
        cd "step${NEXT_STEP}" || exit
        python ../../../pso_optimizer.py "${CLEAN_ARGS[@]}" 2>&1 | tee optimization.log
    fi

    # Scrape energies for the CSV from the current optimization.log
    CUR_PSO=$(grep "New global best energy:" optimization.log | tail -n 1 | awk '{print $NF}')
    if [[ -z "$CUR_PSO" ]]; then
        CUR_PSO=$(grep "Initial ${METHOD} energy:" optimization.log | tail -n 1 | awk '{print $NF}')
    fi
    ALL_PSO_ENGS="${ALL_PSO_ENGS}${ALL_PSO_ENGS:+ | }$CUR_PSO"

    if [[ "$NO_PBE" -eq 1 ]]; then
        CUR_PBE="SKIPPED"
    else
        CUR_PBE=$(grep "Final optimized PBE" optimization.log | tail -n 1 | awk '{print $(NF-1)}')
        [[ -z "$CUR_PBE" ]] && CUR_PBE="FAIL"
    fi
    ALL_PBE_ENGS="${ALL_PBE_ENGS}${ALL_PBE_ENGS:+ | }$CUR_PBE"
    
    # Step back out to the trial directory
    cd ..
done

# ==========================================
# 8. POST-RUN ANALYSIS & MASTER LOGGING
# ==========================================
# Look at the last step folder generated to determine final success status
if [[ -f "step${NEXT_STEP}/final_pso_${METHOD}.xyz" ]]; then PSO_STAT="SUCCESS"; else PSO_STAT="FAIL"; fi

if [[ "$NO_PBE" -eq 1 ]]; then PBE_STAT="SKIPPED"
elif [[ -f "step${NEXT_STEP}/final_pbe_optimized.xyz" ]]; then PBE_STAT="SUCCESS"
else PBE_STAT="FAIL"; fi

# Path back out to the root directory for the master log
MASTER_LOG="../../master_run_log.csv"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

if [[ ! -f "$MASTER_LOG" ]]; then
    echo "Timestamp,Folder,Atoms,Inertia,Trial,Restarts_Executed,PSO_Status,PSO_Energy_History,PBE_Status,PBE_Energy_History,Full_Args" > "$MASTER_LOG"
fi

echo "$DATE,$DIR_NAME,$ATOMS,$INERTIA,$TRIAL,$RESTARTS,$PSO_STAT,$ALL_PSO_ENGS,$PBE_STAT,$ALL_PBE_ENGS,${CLEAN_ARGS[*]}" >> "$MASTER_LOG"

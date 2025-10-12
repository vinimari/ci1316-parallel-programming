#!/bin/bash

# Stop script on any command error
set -e
set -o pipefail

##############################################################################
# Hardcore Benchmark Script for OpenMP Shortest Superstring Problem
#
# Applies best practices for consistent and reliable performance measurement:
# 1. Requires sudo to control CPU settings.
# 2. Sets CPU governor to 'performance' to disable frequency scaling.
# 3. Disables Intel Turbo Boost for consistent clock speeds.
# 4. Clears system page caches before runs for a "cold start".
# 5. Pins processes to specific CPU cores using 'taskset'.
# 6. Runs benchmarks with high priority using 'nice'.
# 7. Restores all system settings automatically on exit.
# 8. Includes a correctness check before running performance tests.
##############################################################################

# --- Configuration ---
NUM_RUNS=20

PARALLEL_EXE="./parallel/shsup_par"
SEQUENTIAL_EXE="./sequential/shsup_seq"
OUTPUT_DIR="results"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Globals for restoring state ---
declare -A ORIGINAL_GOVERNORS
ORIGINAL_TURBO_STATE=""

##############################################################################
# Helper Functions
##############################################################################

print_header() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║        Hardcore SSP Benchmark - Data Collection              ║"
    echo "║ (Applying CPU pinning, fixed frequency, and high priority)   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
}

check_prerequisites() {
    # Check for root privileges
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run with sudo to control CPU settings.${NC}"
        exit 1
    fi

    # Check executables
    for exe in "$PARALLEL_EXE" "$SEQUENTIAL_EXE"; do
        if [ ! -f "$exe" ]; then
            echo -e "${RED}Error: Executable '$exe' not found!${NC}"
            exit 1
        fi
    done

    # Check for inputs
    if [ ! -d "inputs" ] || [ -z "$(ls -A inputs/*.txt 2>/dev/null)" ]; then
        echo -e "${RED}Error: No input files found in 'inputs/' folder.${NC}"
        exit 1
    fi
}

# Sets the environment for stable benchmarking
setup_environment() {
    echo -e "${YELLOW}--- Configuring system for stable benchmarking ---${NC}"

    # Set CPU governor to 'performance' for all cores
    echo "  > Setting CPU governor to 'performance'..."
    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        cpu_num=$(basename "$cpu" | tr -d 'cpu')
        ORIGINAL_GOVERNORS[$cpu_num]=$(cat "$cpu/cpufreq/scaling_governor")
        echo "performance" > "$cpu/cpufreq/scaling_governor"
    done

    # Disable Intel Turbo Boost
    if [ -f "/sys/devices/system/cpu/intel_pstate/no_turbo" ]; then
        echo "  > Disabling Intel Turbo Boost..."
        ORIGINAL_TURBO_STATE=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)
        echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo
    else
        echo "  > Intel Turbo Boost control not found, skipping."
    fi
    echo -e "${GREEN}✓ System configured.${NC}\n"
}

# Restores the system to its original state
cleanup_environment() {
    echo -e "\n${YELLOW}--- Restoring original system settings ---${NC}"

    # Restore CPU governors
    echo "  > Restoring CPU governors..."
    for cpu_num in "${!ORIGINAL_GOVERNORS[@]}"; do
        echo "${ORIGINAL_GOVERNORS[$cpu_num]}" > "/sys/devices/system/cpu/cpu$cpu_num/cpufreq/scaling_governor"
    done

    # Restore Intel Turbo Boost
    if [ -f "/sys/devices/system/cpu/intel_pstate/no_turbo" ] && [ -n "$ORIGINAL_TURBO_STATE" ]; then
        echo "  > Re-enabling Intel Turbo Boost..."
        echo "$ORIGINAL_TURBO_STATE" > /sys/devices/system/cpu/intel_pstate/no_turbo
    fi
    echo -e "${GREEN}✓ System restored. Goodbye!${NC}\n"
}

# Trap to ensure cleanup runs on exit (normal, error, or ctrl-c)
trap cleanup_environment EXIT

calculate_stats() {
    local file=$1
    # Using awk for stats to remove python dependency
    awk '
        BEGIN {
            count = 0;
            sum = 0;
            sum_sq = 0;
        }
        {
            if ($1 ~ /^[0-9.]+$/) {
                data[count] = $1;
                sum += $1;
                sum_sq += $1 * $1;
                count++;
            }
        }
        END {
            if (count > 0) {
                mean = sum / count;
                if (count > 1) {
                    std_dev = sqrt((sum_sq - sum*sum/count) / (count-1));
                } else {
                    std_dev = 0;
                }
                printf "%.6f,%.6f\n", mean, std_dev;
            } else {
                print "0.0,0.0";
            }
        }
    ' "$file"
}

##############################################################################
# ## ALTERADO ##: Nova função para verificação de corretude
##############################################################################

check_correctness() {
    local input_file=$1
    local input_name=$(basename "$input_file")
    local seq_output_file="$OUTPUT_DIR/correctness_seq_output.txt"

    echo -e "${YELLOW}--- Running Correctness Check on '${input_name}' ---${NC}"

    # 1. Gerar saída de referência com a versão sequencial
    echo "  > Generating reference output from sequential executable..."
    "$SEQUENTIAL_EXE" < "$input_file" > "$seq_output_file"

    # 2. Testar a versão paralela com cada contagem de threads
    for t in "${THREADS[@]}"; do
        local par_output_file="$OUTPUT_DIR/correctness_par_${t}t_output.txt"
        echo -n "  > Verifying with $t thread(s)... "
        export OMP_NUM_THREADS=$t
        "$PARALLEL_EXE" < "$input_file" > "$par_output_file"

        # 3. Comparar as saídas com 'diff'
        if diff -q "$seq_output_file" "$par_output_file" &>/dev/null; then
            echo -e "${GREEN}✓ OK${NC}"
        else
            echo -e "${RED}✗ FAILED!${NC}"
            echo "    Outputs do not match for $t thread(s)."
            echo "    Expected output (first 3 lines):"
            head -n 3 "$seq_output_file" | sed 's/^/      /'
            echo "    Got:"
            head -n 3 "$par_output_file" | sed 's/^/      /'
            # Interrompe o script imediatamente em caso de falha
            exit 1
        fi
    done
    echo -e "${GREEN}✓ All correctness checks passed.${NC}\n"
}

##############################################################################
# Benchmark Execution
##############################################################################

run_benchmark() {
    local exe_path=$1
    local input_file=$2
    local output_file=$3
    local num_threads=$4
    local num_runs=$5
    local run_type=$6
    local input_name=$(basename "$input_file" .txt)

    echo -e "${BLUE}[$run_type] Testing: ${input_name} with ${num_threads} thread(s) for ${num_runs} runs${NC}"

    # Clear system page cache for a cold start
    echo "  > Clearing file system caches..."
    sync
    echo 3 > /proc/sys/vm/drop_caches
    sleep 1

    > "$output_file"
    export OMP_NUM_THREADS=$num_threads

    # Pin execution to the first N cores
    local core_list="0-$((num_threads-1))"

    for i in $(seq 1 "$num_runs"); do
        TIMEFORMAT='%3R'
        # Run with high priority (-20) and pinned to specific cores
        { time nice -n -20 taskset -c "$core_list" "$exe_path" < "$input_file" > /dev/null 2>&1; } 2>> "$output_file"
        printf "."
    done
    echo ""

    IFS=',' read -r mean std <<< $(calculate_stats "$output_file")
    echo -e "${GREEN}✓ Mean: ${mean}s, StdDev: ${std}s${NC}\n"

    echo "$input_name,$run_type,$num_threads,$mean,$std" >> "$OUTPUT_DIR/raw_data.csv"
}

##############################################################################
# MAIN
##############################################################################

print_header
check_prerequisites
setup_environment

# Setup output directory and CSV header
mkdir -p "$OUTPUT_DIR"
echo "input,type,threads,mean_time,std_dev" > "$OUTPUT_DIR/raw_data.csv"

# Get system info
INPUTS=(inputs/*.txt)
NUM_CORES=$(nproc)
# Ensure thread counts do not exceed available cores
THREADS=()
for t in 1 2 4 $(seq 6 2 "$NUM_CORES"); do
    if (( t <= NUM_CORES )); then
        THREADS+=("$t")
    fi
done
# Remove duplicates and sort
THREADS=($(printf "%s\n" "${THREADS[@]}" | sort -un))

echo -e "${YELLOW}System Info:${NC}"
echo "  Cores available: $NUM_CORES"
echo "  Thread counts to test: ${THREADS[@]}"
echo "  Runs per test configuration: ${NUM_RUNS}"
echo ""

# ## ALTERADO ##: Adicionada a chamada para a verificação de corretude
# Roda a verificação de corretude antes dos testes de desempenho.
# Usa o primeiro (geralmente o menor) arquivo de entrada para ser rápido.
check_correctness "${INPUTS[0]}"

# Run performance benchmarks
echo -e "${BLUE}=== COLLECTING PERFORMANCE DATA ===${NC}\n"

for input in "${INPUTS[@]}"; do
    input_name=$(basename "$input" .txt)
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Input File: ${input_name}${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # Sequential
    seq_output="$OUTPUT_DIR/${input_name}_seq.times"
    run_benchmark "$SEQUENTIAL_EXE" "$input" "$seq_output" 1 "$NUM_RUNS" "sequential"

    # Parallel
    for threads in "${THREADS[@]}"; do
        par_output="$OUTPUT_DIR/${input_name}_${threads}t.times"
        run_benchmark "$PARALLEL_EXE" "$input" "$par_output" "$threads" "$NUM_RUNS" "parallel"
    done
done

# Summary
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║              Data Collection Complete!                 ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

echo -e "Raw data saved in: ${BLUE}$OUTPUT_DIR/raw_data.csv${NC}"
echo -e "Individual times: ${BLUE}$OUTPUT_DIR/*.times${NC}"
#!/bin/bash

##############################################################################
# Benchmark Script for the OpenMP Assignment
# Runs tests with different numbers of threads and input sizes
#
# MODIFIED FOR:
# - Use the folder structure: inputs/, parallel/, sequential/
# - Restore system settings upon completion
##############################################################################

# Settings
NUM_RUNS=20                          # Number of runs per test
EXECUTABLE="./parallel/shsup_par"        # Parallel executable
SEQ_EXECUTABLE="./sequential/shsup_seq" # Sequential executable
OUTPUT_DIR="results"                 # Directory for results

# Variables to store the original system state
ORIGINAL_TURBO_STATE=""
ORIGINAL_GOVERNOR=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create results directory
mkdir -p $OUTPUT_DIR

##############################################################################
# Function to restore system settings on exit
##############################################################################
restore_system() {
    echo -e "\n${YELLOW}Restoring original system settings...${NC}"

    # Restore Turbo Boost
    if [ -n "$ORIGINAL_TURBO_STATE" ] && [ "$ORIGINAL_TURBO_STATE" != "not_found" ]; then
        if sudo sh -c "echo $ORIGINAL_TURBO_STATE > /sys/devices/system/cpu/intel_pstate/no_turbo" 2>/dev/null; then
            echo -e "${GREEN}✓ Turbo Boost restored to its original state.${NC}"
        else
            echo -e "${RED}✗ Failed to restore Turbo Boost.${NC}"
        fi
    fi

    # Restore CPU Governor
    if [ -n "$ORIGINAL_GOVERNOR" ] && [ "$ORIGINAL_GOVERNOR" != "not_found" ]; then
        if sudo cpupower frequency-set -g "$ORIGINAL_GOVERNOR" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ CPU governor restored to '${ORIGINAL_GOVERNOR}'.${NC}"
        else
            echo -e "${RED}✗ Failed to restore CPU governor.${NC}"
        fi
    fi
    echo ""
}

# Ensures the restore_system function is called on script exit
trap restore_system EXIT

##############################################################################
# Function to calculate mean and standard deviation
##############################################################################
calculate_stats() {
    local file=$1
    python3 - <<EOF
import numpy as np
data = []
with open('$file', 'r') as f:
    for line in f:
        try:
            data.append(float(line.strip()))
        except:
            pass
if data:
    mean = np.mean(data)
    std = np.std(data, ddof=1)
    print(f"{mean:.4f} {std:.4f}")
else:
    print("0.0000 0.0000")
EOF
}

##############################################################################
# Function to run a benchmark
##############################################################################
run_benchmark() {
    local input_file=$1
    local num_threads=$2
    local output_file=$3
    local input_name=$(basename $input_file .txt)

    echo -e "${BLUE}Testing: ${input_name} with ${num_threads} threads${NC}"

    # Clear output file
    > $output_file

    # Execute NUM_RUNS times
    for i in $(seq 1 $NUM_RUNS); do
        export OMP_NUM_THREADS=$num_threads

        # Measure time with `time`
        TIMEFORMAT='%3R'
        { time $EXECUTABLE < $input_file > /dev/null 2>&1; } 2>> $output_file

        # Progress bar
        printf "."
    done

    echo "" # New line after the progress bar

    # Calculate statistics
    read mean std <<< $(calculate_stats $output_file)
    echo -e "${GREEN}✓ Mean: ${mean}s, StdDev: ${std}s${NC}"

    # Save statistics to CSV file
    echo "$input_name,$num_threads,$mean,$std" >> $OUTPUT_DIR/summary.csv
}

##############################################################################
# Function to check correctness
##############################################################################
check_correctness() {
    local input_file=$1
    echo -e "${YELLOW}Checking correctness for $(basename $input_file)...${NC}"

    # Run sequential version
    $SEQ_EXECUTABLE < $input_file > $OUTPUT_DIR/output_seq.txt

    # Run parallel with 1, 2, 4, 8 threads
    for T in 1 2 4 8; do
        export OMP_NUM_THREADS=$T
        $EXECUTABLE < $input_file > $OUTPUT_DIR/output_${T}t.txt

        if diff -q $OUTPUT_DIR/output_seq.txt $OUTPUT_DIR/output_${T}t.txt > /dev/null; then
            echo -e "${GREEN}✓ ${T} threads: OK${NC}"
        else
            echo -e "${RED}✗ ${T} threads: FAILED!${NC}"
            echo "Expected:"
            head -n 3 $OUTPUT_DIR/output_seq.txt
            echo "Got:"
            head -n 3 $OUTPUT_DIR/output_${T}t.txt
            exit 1
        fi
    done

    echo -e "${GREEN}All correctness tests passed!${NC}\n"
}

##############################################################################
# System Configuration
##############################################################################
setup_system() {
    echo -e "${YELLOW}=== System Configuration ===${NC}"

    # System information
    lscpu | grep "Model name"
    lscpu | grep "^CPU(s):"

    # Attempt to disable turbo boost (requires sudo)
    echo -e "\n${YELLOW}Attempting to disable Turbo Boost (may require sudo)...${NC}"
    if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
        ORIGINAL_TURBO_STATE=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)
        if sudo sh -c "echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo" 2>/dev/null; then
            echo -e "${GREEN}✓ Turbo Boost disabled${NC}"
        else
            echo -e "${RED}✗ Could not disable Turbo Boost${NC}"
        fi
    else
        ORIGINAL_TURBO_STATE="not_found"
        echo -e "${YELLOW}! Turbo Boost control not available${NC}"
    fi

    # Set governor to performance
    echo -e "\n${YELLOW}Setting CPU governor to 'performance'...${NC}"
    if command -v cpupower >/dev/null; then
        ORIGINAL_GOVERNOR=$(cpupower frequency-info -p | sed -n 's/.*The governor "\([^"]*\)".*/\1/p' | head -n 1)
        if sudo cpupower frequency-set -g performance 2>/dev/null; then
            echo -e "${GREEN}✓ Governor set to 'performance'${NC}"
        else
            echo -e "${YELLOW}! Could not set governor (may not be available)${NC}"
        fi
    else
        ORIGINAL_GOVERNOR="not_found"
        echo -e "${YELLOW}! 'cpupower' command not found. Skipping governor configuration.${NC}"
    fi
    echo ""
}

##############################################################################
# MAIN
##############################################################################

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║      Automatic Benchmark - OpenMP Parallel Programming     ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

# Check if executables exist
if [ ! -f "$EXECUTABLE" ]; then
    echo -e "${RED}Error: Parallel executable '$EXECUTABLE' not found!${NC}"
    echo "Make sure it is in the 'parallel/' folder."
    exit 1
fi

if [ ! -f "$SEQ_EXECUTABLE" ]; then
    echo -e "${YELLOW}Warning: Sequential executable '$SEQ_EXECUTABLE' not found. Skipping correctness tests.${NC}"
    SKIP_CORRECTNESS=1
fi

# Configure system
setup_system

# Create CSV header
echo "input,threads,mean_time,std_dev" > $OUTPUT_DIR/summary.csv

# List of inputs to test (automatic search in the inputs/ folder)
INPUTS=(inputs/*.txt)
if [ ! -e "${INPUTS[0]}" ]; then
    echo -e "${RED}Error: No input files found in the 'inputs/' folder${NC}"
    exit 1
fi

# List of thread counts (adjust according to your processor)
THREADS=(1 2 4)
NUM_PROCS=$(nproc)
if [ $NUM_PROCS -ge 16 ]; then
    THREADS+=(16)
fi

echo -e "${YELLOW}Tests will be run with the following thread counts: ${THREADS[@]}${NC}\n"

# Correctness test first (use a small file for this)
if [ -z "$SKIP_CORRECTNESS" ]; then
    if [ -f "inputs/input_tiny.txt" ]; then
        echo -e "${BLUE}=== CORRECTNESS TESTS ===${NC}"
        check_correctness "inputs/input_tiny.txt"
    else
        echo -e "${YELLOW}Warning: 'inputs/input_tiny.txt' not found. Skipping correctness test.${NC}\n"
    fi
fi

# Run benchmarks
echo -e "${BLUE}=== RUNNING BENCHMARKS ===${NC}"
echo -e "Each test will be run ${NUM_RUNS} times\n"

for input in "${INPUTS[@]}"; do
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Input file: $(basename $input)${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    for threads in "${THREADS[@]}"; do
        output_file="$OUTPUT_DIR/$(basename ${input%.txt})_${threads}t.times"
        run_benchmark "$input" "$threads" "$output_file"
        echo ""
    done
done

# Generate final report
echo -e "${BLUE}=== GENERATING REPORT ===${NC}"

python3 - <<'PYTHON_SCRIPT'
import csv
import sys

# Read data
data = {}
try:
    with open('results/summary.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            input_name = row['input']
            threads = int(row['threads'])
            mean_time = float(row['mean_time'])
            std_dev = float(row['std_dev'])

            if input_name not in data:
                data[input_name] = {}
            data[input_name][threads] = (mean_time, std_dev)
except FileNotFoundError:
    print("'results/summary.csv' file not found. Cannot generate report.")
    sys.exit(1)
except Exception as e:
    print(f"An error occurred while reading the CSV file: {e}")
    sys.exit(1)

if not data:
    print("No benchmark data found to generate the report.")
    sys.exit(0)

# Calculate speedup and efficiency
print("\n" + "="*80)
print("SPEEDUP TABLE")
print("="*80)

for input_name in sorted(data.keys()):
    print(f"\nInput: {input_name}")
    print("-" * 60)

    # Check if the baseline (1 thread) exists
    if 1 not in data[input_name]:
        print(f"  No data for 1 thread. Skipping Speedup calculation.")
        continue

    baseline_time = data[input_name][1][0]

    print(f"{'Threads':<10} {'Time (s)':<15} {'StdDev':<15} {'Speedup':<15}")
    print("-" * 60)

    for threads in sorted(data[input_name].keys()):
        mean_time, std_dev = data[input_name][threads]
        speedup = baseline_time / mean_time
        print(f"{threads:<10} {mean_time:<15.4f} {std_dev:<15.4f} {speedup:<15.2f}x")

print("\n" + "="*80)
print("EFFICIENCY TABLE")
print("="*80)

for input_name in sorted(data.keys()):
    print(f"\nInput: {input_name}")
    print("-" * 60)

    if 1 not in data[input_name]:
        print(f"  No data for 1 thread. Skipping Efficiency calculation.")
        continue

    baseline_time = data[input_name][1][0]

    print(f"{'Threads':<10} {'Speedup':<15} {'Efficiency (%)':<15}")
    print("-" * 60)

    for threads in sorted(data[input_name].keys()):
        mean_time, std_dev = data[input_name][threads]
        speedup = baseline_time / mean_time
        efficiency = (speedup / threads) * 100
        print(f"{threads:<10} {speedup:<15.2f}x {efficiency:<15.1f}%")

print("\n" + "="*80)
print(f"Detailed results saved in: results/summary.csv")
print("="*80 + "\n")

PYTHON_SCRIPT

echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║                 Benchmark Complete!                 ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

echo -e "Results saved in: ${BLUE}$OUTPUT_DIR/${NC}"
echo -e "CSV file: ${BLUE}$OUTPUT_DIR/summary.csv${NC}"
echo -e "Individual times: ${BLUE}$OUTPUT_DIR/*.times${NC}"
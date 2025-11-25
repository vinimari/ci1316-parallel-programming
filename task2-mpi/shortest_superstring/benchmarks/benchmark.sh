#!/usr/bin/env bash
set -euo pipefail

################################################################################
# benchmark.sh
#
# Script de benchmark configurável para executar programas sequencial e paralelo
# (MPI). Para cada input o script executa N repetições (default 10) e grava o
# tempo de execução de cada repetição em CSV. Também gera uma sumarização com
# métricas: speedup e estimativa da fração paralela via Lei de Amdahl.
#
# Decisões principais (explicação resumida):
# - Não assumimos a configuração do cluster; o usuário deve fornecer
#   --nodes e --ppn (cores por nó) ou fornecer explicitamente a lista de
#   processos (--procs). Isso evita chutes sobre o tamanho do cluster.
# - O launcher MPI é configurável: `srun` (para SLURM) ou `mpirun`/`mpiexec`.
# - As medições usam timestamps de alta resolução (`date +%s.%N`) para medir
#   o tempo wall-clock total de cada execução.
# - Para evitar que `set -euo pipefail` interrompa o script por SIGPIPE em
#   pipelines internas, tratamos casos onde isso pode ocorrer com `|| true`.
# - O script grava resultados brutos (cada execução) em `results/raw.csv` e
#   um resumo em `results/summary.csv` com métricas básicas.
#
# Uso (exemplo):
# ./benchmark.sh \
#   --seq-bin ../sequential/shsup_seq \
#   --par-bin ../parallel/shsup_par \
#   --inputs ../inputs --runs 10 --launcher srun --nodes 14 --ppn 6
#
# Observações importantes (perguntas/checagens):
# - Este script deve ser executado dentro de uma alocação SLURM (srun) ou em
#   um nó onde `mpirun` funciona. Ele não faz `sbatch` por si só.
# - Para cálculos de escalabilidade fraca: é necessário definir como mapear
#   tamanho do problema para número de processos (ex.: dividir entradas por
#   processo). Se quiser, eu adapto o script para gerar automaticamente esses
#   mapeamentos.

################################################################################

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
RESULTS_DIR="$HERE/results"
mkdir -p "$RESULTS_DIR"

# Defaults
RUNS=10
LAUNCHER=""
SEQ_BIN=""
PAR_BIN=""
INPUT_DIR="$ROOT/inputs"
PROCS_LIST=""
NODES=""
PPN=""
WEAK_SCALING=false

# Try to detect binaries inside the containing `task2-mpi` directory when
# user did not provide explicit paths.
try_detect_bins() {
  TASK2_DIR=$(cd "$ROOT/.." && pwd)
  if [[ -z "$SEQ_BIN" ]]; then
    cand=$(find "$TASK2_DIR" -type f -executable -name 'shsup_seq' -print -quit 2>/dev/null || true)
    if [[ -n "$cand" ]]; then
      SEQ_BIN=$cand
      echo "Detected sequential binary: $SEQ_BIN"
    fi
  fi
  if [[ -z "$PAR_BIN" ]]; then
    cand=$(find "$TASK2_DIR" -type f -executable -name 'shsup_par' -print -quit 2>/dev/null || true)
    if [[ -n "$cand" ]]; then
      PAR_BIN=$cand
      echo "Detected parallel binary: $PAR_BIN"
    fi
  fi
}

print_usage() {
  cat <<EOF
Usage: $0 --seq-bin PATH --par-bin PATH [options]

Required:
  --seq-bin PATH        Caminho para executável sequencial (ex: shsup_seq)
  --par-bin PATH        Caminho para executável paralelo (ex: shsup_par)

Options:
  --inputs DIR          Diretório com arquivos de input (default: ./inputs)
  --runs N              Número de repetições por configuração (default: 10)
  --launcher NAME       MPI launcher: 'srun' (SLURM) or 'mpirun' (default: must provide)
  --nodes N             Número de nós disponíveis (usado para gerar lista de processos)
  --ppn N               Processos por nó (cores por nó)
  --procs "p1,p2,.."    Lista explícita de processos para testar (overrides nodes/ppn)
  --outdir DIR          Diretório de resultados (default: ./results)
  -h|--help             Mostra esta ajuda

Examples:
  # Usando SLURM (já dentro de uma alocação)
  $0 --seq-bin ../sequential/shsup_seq --par-bin ../parallel/shsup_par --launcher srun --nodes 14 --ppn 6

  # Usando mpirun localmente
  $0 --seq-bin ../sequential/shsup_seq --par-bin ../parallel/shsup_par --launcher mpirun --procs "1,2,4,8"

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seq-bin) SEQ_BIN="$2"; shift 2;;
    --par-bin) PAR_BIN="$2"; shift 2;;
    --inputs) INPUT_DIR="$2"; shift 2;;
    --runs) RUNS="$2"; shift 2;;
    --launcher) LAUNCHER="$2"; shift 2;;
    --nodes) NODES="$2"; shift 2;;
    --ppn) PPN="$2"; shift 2;;
    --procs) PROCS_LIST="$2"; shift 2;;
    --weak) WEAK_SCALING=true; shift 1;;
    --outdir) RESULTS_DIR="$2"; mkdir -p "$RESULTS_DIR"; shift 2;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown option: $1"; print_usage; exit 1;;
  esac
done

# Basic validation
# If the user did not provide explicit binaries, attempt detection in
# the `task2-mpi` directory (one level above the `shortest_superstring`
# tree). If detection fails, require explicit flags.
try_detect_bins
if [[ -z "$SEQ_BIN" || -z "$PAR_BIN" ]]; then
  echo "ERROR: --seq-bin and --par-bin are required (or detectable in task2-mpi)." >&2
  print_usage
  exit 1
fi

if [[ -z "$LAUNCHER" ]]; then
  echo "ERROR: --launcher is required (use 'srun' or 'mpirun')." >&2
  print_usage
  exit 1
fi

if [[ -z "$PROCS_LIST" ]]; then
  if [[ -n "$NODES" && -n "$PPN" ]]; then
    max=$((NODES * PPN))
    # Generate a reasonable progression: multiples of PPN up to max
    arr=(1)
    p=$PPN
    while [[ $p -le $max ]]; do
      arr+=("$p")
      p=$((p + PPN))
    done
    PROCS_LIST=$(IFS=,; echo "${arr[*]}")
  else
    echo "ERROR: either --procs or ( --nodes and --ppn ) must be provided." >&2
    print_usage
    exit 1
  fi
fi

IFS=',' read -r -a PROCS_ARR <<< "$PROCS_LIST"

# CSV headers
RAW_CSV="$RESULTS_DIR/raw.csv"
SUMMARY_CSV="$RESULTS_DIR/summary.csv"
echo "input,mode,procs,run,elapsed" > "$RAW_CSV"

run_and_time() {
  local cmd=("$@")
  local start end elapsed
  start=$(date +%s.%N)
  "${cmd[@]}"
  end=$(date +%s.%N)
  # floating point subtraction
  elapsed=$(awk "BEGIN{print $end - $start}")
  echo "$elapsed"
}

echo "Benchmark: seq=$SEQ_BIN par=$PAR_BIN launcher=$LAUNCHER runs=$RUNS procs=(${PROCS_ARR[*]})"

for input in "$INPUT_DIR"/*; do
  [[ -f "$input" ]] || continue
  infile=$(basename "$input")
  echo "Running input: $infile"

  # Sequential runs
  for ((r=1;r<=RUNS;r++)); do
    echo "  seq run $r..."
    t=$(run_and_time "$SEQ_BIN" "$input")
    echo "$infile,seq,1,$r,$t" >> "$RAW_CSV"
  done

  # Parallel runs
  if [[ "$WEAK_SCALING" == true ]]; then
    # Map input -> procs by extracting the first number in the filename
    # and dividing by 100 (as agreed): input_100_30.txt -> 1 proc, etc.
    num=$(echo "$infile" | grep -oP '\\d+' | head -n1 || true)
    if [[ -z "$num" ]]; then
      p=1
    else
      p=$((num / 100))
      if [[ $p -lt 1 ]]; then p=1; fi
    fi
    echo "  weak-scaling: using p=$p for $infile"
    for ((r=1;r<=RUNS;r++)); do
      echo "  par p=$p run $r..."
      if [[ "$LAUNCHER" == "srun" ]]; then
        srun_cmd=(srun --mpi=pmix -n "$p")
        if [[ -n "$PPN" && -n "$NODES" ]]; then
          srun_cmd+=(--nodes "$NODES" --ntasks-per-node "$PPN")
        fi
        t=$(run_and_time "${srun_cmd[@]}" "$PAR_BIN" "$input" || true)
      else
        if command -v mpirun >/dev/null 2>&1; then
          t=$(run_and_time mpirun -np "$p" "$PAR_BIN" "$input" || true)
        else
          t=$(run_and_time mpiexec -n "$p" "$PAR_BIN" "$input" || true)
        fi
      fi
      echo "$infile,par,$p,$r,$t" >> "$RAW_CSV"
    done
  else
    for p in "${PROCS_ARR[@]}"; do
      for ((r=1;r<=RUNS;r++)); do
        echo "  par p=$p run $r..."
        if [[ "$LAUNCHER" == "srun" ]]; then
          srun_cmd=(srun --mpi=pmix -n "$p")
          if [[ -n "$PPN" && -n "$NODES" ]]; then
            srun_cmd+=(--nodes "$NODES" --ntasks-per-node "$PPN")
          fi
          t=$(run_and_time "${srun_cmd[@]}" "$PAR_BIN" "$input" || true)
        else
          if command -v mpirun >/dev/null 2>&1; then
            t=$(run_and_time mpirun -np "$p" "$PAR_BIN" "$input" || true)
          else
            t=$(run_and_time mpiexec -n "$p" "$PAR_BIN" "$input" || true)
          fi
        fi
        echo "$infile,par,$p,$r,$t" >> "$RAW_CSV"
      done
    done
  fi
done

echo "Raw results written to $RAW_CSV"

# Summarize: compute mean times for seq and each par config and speedup
python3 - <<'PY'
import csv,math
from collections import defaultdict

raw = '$RAW_CSV'
summary = '$SUMMARY_CSV'
metrics = '$RESULTS_DIR/metrics.csv'

groups = defaultdict(list)
with open(raw) as f:
  r = csv.DictReader(f)
  for row in r:
    key = (row['input'], row['mode'], int(row['procs']))
    groups[key].append(float(row['elapsed']))

stats = defaultdict(dict)
with open(summary, 'w', newline='') as out:
  w = csv.writer(out)
  w.writerow(['input','mode','procs','mean','stddev','runs'])
  for (inp,mode,procs), vals in sorted(groups.items()):
    n = len(vals)
    mean = sum(vals)/n if n>0 else 0.0
    var = sum((x-mean)**2 for x in vals)/n if n>0 else 0.0
    std = math.sqrt(var)
    w.writerow([inp, mode, procs, mean, std, n])
    stats[inp][(mode,procs)] = (mean, std, n)

with open(metrics, 'w', newline='') as out:
  w = csv.writer(out)
  w.writerow(['input','procs','mean_seq','mean_par','stddev_par','runs','speedup','amdahl_f'])
  for inp in sorted(stats.keys()):
    # find seq mean
    seq_mean = None
    for (mode,procs), (mean, std, n) in stats[inp].items():
      if mode == 'seq':
        seq_mean = mean
    if seq_mean is None:
      continue
    for (mode,procs), (mean_par, std_par, runs) in stats[inp].items():
      if mode != 'par':
        continue
      speedup = seq_mean/mean_par if mean_par>0 else 0.0
      p = procs
      if speedup<=1 or p<=1:
        f = 0.0
      else:
        f = (p*(1 - 1.0/speedup))/(p - 1)
      w.writerow([inp, p, seq_mean, mean_par, std_par, runs, speedup, f])

print('Summary written to', summary)
print('Metrics written to', metrics)
PY

echo "Benchmark finished. Review $RESULTS_DIR for raw and summarized data."

echo "Notes and next steps:"
echo "- If you want weak-scaling experiments, tell me how inputs map to processes (e.g., input_100_30.txt -> 1 proc, input_200_30.txt -> 2 procs, ...), que eu adiciono a lógica."
echo "- Confirme qual launcher prefere (srun ou mpirun) e se deseja que eu gere também um `sbatch` wrapper para submeter o benchmark automaticamente."

exit 0

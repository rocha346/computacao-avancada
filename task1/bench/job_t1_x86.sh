#!/bin/bash
# =============================================================================
# ACA WA2 - Task 1.1/1.2 - Benchmarks do nó x86 (2x AMD EPYC 7742).
# ANTES: correr o teste rápido (test_x86.sh / test_arm.sh) e ter tudo OK.
# Submeter a partir da pasta bench:   sbatch job_t1_x86.sh
# Corre: latência (D07), pico + tetos (D05/D16), frequência real (D14),
#        banda das caches com triad, banda da RAM com STREAM (D06), SGEMM (D05).
# Estatística (D10): 1 aquecimento + 10 repetições de cada medição.
# =============================================================================
#SBATCH --job-name=t1-bench-x86
#SBATCH --account=f202500010hpcvlabuminhox
#SBATCH --partition=normal-x86
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --time=01:30:00
#SBATCH --output=t1-bench-x86-%j.out

set -u
cd "${SLURM_SUBMIT_DIR}"
ml GCC/13.3.0 || { echo 'ERRO: GCC/13.3.0 não existe (ml spider GCC)'; exit 1; }
ml numactl 2>/dev/null   # o comando numactl vem neste módulo
NUMA="numactl --physcpubind=0 --membind=0"; command -v numactl >/dev/null || NUMA="taskset -c 0"
#                 # confirmar versões com: ml spider GCC
ml OpenBLAS 2>/dev/null || echo "AVISO: módulo OpenBLAS não encontrado (ml spider OpenBLAS)"
OUT=res-x86-${SLURM_JOB_ID}; mkdir -p $OUT
REPS=10
# Binários numa pasta SÓ desta arquitetura: os jobs x86 e ARM correm ao mesmo
# tempo na mesma pasta, e com nomes iguais um apagava os binários do outro.
B=build-x86-${SLURM_JOB_ID}; mkdir -p $B

# ---- compilar (flags registadas no ficheiro de resultados: reprodutibilidade) ----
CFLAGS="-O3 -march=znver2 -fopenmp"
echo "gcc $(gcc -dumpfullversion) ($(command -v gcc)); $(as --version | head -1); CFLAGS=$CFLAGS" > $OUT/build.txt
gcc $CFLAGS -o $B/latency latency.c
gcc -O2 -mavx2 -mfma -fopenmp -o $B/peak peak.c          # -O2: não queremos que o compilador "otimize" o benchmark
gcc $CFLAGS -o $B/triad triad.c
gcc -O2 -fopenmp -o $B/sgemm sgemm.c -lopenblas 2>>$OUT/build.txt || echo "sgemm não compilou" >> $OUT/build.txt

export OMP_PLACES=cores OMP_PROC_BIND=close

# ---- 1) latência: 1 thread no core 0, memória no nó NUMA 0 ----
echo ">> latência"
$NUMA $B/latency 4 2048 > $OUT/latency.csv

# ---- 2) pico e tetos de cálculo: 1 core e 128 cores ----
echo ">> pico"
for T in 1 128; do
  for m in fma muladd add sfma lat div sdiv; do
    it=100000000; [[ $m == div || $m == sdiv ]] && it=20000000
    for r in $(seq 0 $REPS); do        # r=0 é o aquecimento (descartar na análise)
      OMP_NUM_THREADS=$T $B/peak $m $it | grep -v '^CSV,arch' | sed "s/^/rep=$r,/"
    done
  done
done > $OUT/peak.csv

# ---- 3) frequência real sob carga AVX2 (D14): ciclos / tempo ----
echo ">> frequência"
if command -v perf >/dev/null; then
  for T in 1 16 64 128; do
    echo "== T=$T"; OMP_NUM_THREADS=$T perf stat -e cycles,task-clock $B/peak fma 200000000 2>&1
  done > $OUT/freq.txt
else
  echo "perf não disponível: usar o modo lat (latência FMA Zen2 = 5 ciclos -> f = 5/t)" > $OUT/freq.txt
fi

# ---- 4) banda das caches com triad (KiB por thread, os 3 arrays juntos) ----
#  L1d 32 KiB -> 16 KiB | L2 512 KiB -> 256 KiB | L3 16 MiB/4 cores -> 2048 KiB por thread
#  RAM (para comparar com o STREAM) -> 262144 KiB por thread
echo ">> triad"
for T in 1 128; do
  for k in 16 256 2048 262144; do
    for r in $(seq 0 $REPS); do
      OMP_NUM_THREADS=$T $B/triad $k 0.5 | grep -v '^CSV,threads' | sed "s/^/rep=$r,/"
    done
  done
done > $OUT/triad.csv

# ---- 5) STREAM na RAM (D06) ----
# Cada array >= 4x a cache total do nó (2 x 256 MiB L3) -> 2^28 doubles = 2 GiB por array
echo ">> stream"
STREAM_DIR=/projects/F202500010HPCVLABUMINHO/ACA/lab2.5/stream
if [ -f $STREAM_DIR/stream.c ]; then
  gcc -O3 -march=znver2 -fopenmp -mcmodel=medium -DSTREAM_ARRAY_SIZE=268435456 -DNTIMES=20 \
      $STREAM_DIR/stream.c -o $B/stream_x86
  for T in 16 32 64 128; do
    echo "== T=$T"; OMP_NUM_THREADS=$T $B/stream_x86
  done > $OUT/stream.txt
else
  echo "Não encontrei $STREAM_DIR/stream.c: ver 'ls $STREAM_DIR'" > $OUT/stream.txt
fi

# ---- 6) SGEMM (validação do pico) ----
echo ">> sgemm"
if [ -x $B/sgemm ]; then
  OMP_NUM_THREADS=128 OPENBLAS_NUM_THREADS=128 $B/sgemm 8192 $REPS > $OUT/sgemm.csv 2>&1
else
  echo "sgemm não compilou: ver $OUT/build.txt" > $OUT/sgemm.csv
fi

echo "FIM. Resultados em $OUT/"

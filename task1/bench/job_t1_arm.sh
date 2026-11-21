#!/bin/bash
# =============================================================================
# ACA WA2 - Task 1.1/1.2 - Benchmarks do nó ARM (Fujitsu A64FX).
# ANTES: correr o teste rápido (test_x86.sh / test_arm.sh) e ter tudo OK.
# Submeter a partir da pasta bench:   sbatch job_t1_arm.sh
# Compila NO nó ARM (o login é x86). Mesmos testes que o x86, para comparar.
# =============================================================================
#SBATCH --job-name=t1-bench-arm
#SBATCH --account=f202500010hpcvlabuminhoa
#SBATCH --partition=normal-arm
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --time=02:00:00
#SBATCH --output=t1-bench-arm-%j.out

set -u
cd "${SLURM_SUBMIT_DIR}"
ml GCC/13.3.0 || { echo 'ERRO: GCC/13.3.0 não existe (ml spider GCC)'; exit 1; }
ml numactl 2>/dev/null   # o comando numactl vem neste módulo
NUMA="numactl --physcpubind=0 --membind=0"; command -v numactl >/dev/null || NUMA="taskset -c 0"
#                 # árvore de módulos ARM é diferente: ml spider GCC
OUT=res-arm-${SLURM_JOB_ID}; mkdir -p $OUT
REPS=10
# Binários numa pasta SÓ desta arquitetura: os jobs x86 e ARM correm ao mesmo
# tempo na mesma pasta, e com nomes iguais um apagava os binários do outro.
B=build-arm-${SLURM_JOB_ID}; mkdir -p $B

CFLAGS="-O3 -mcpu=a64fx -fopenmp"
echo "gcc $(gcc -dumpfullversion) ($(command -v gcc)); $(as --version | head -1); CFLAGS=$CFLAGS" > $OUT/build.txt
gcc $CFLAGS -o $B/latency latency.c
gcc -O2 -mcpu=a64fx -fopenmp -o $B/peak peak.c
gcc $CFLAGS -o $B/triad triad.c

export OMP_PLACES=cores OMP_PROC_BIND=close

echo ">> latência"
$NUMA $B/latency 4 2048 > $OUT/latency.csv

# A divisão SVE no A64FX deve ser MUITO lenta: menos iterações para não demorar horas
echo ">> pico"
for T in 1 48; do
  for m in fma muladd add sfma lat div sdiv; do
    it=100000000; [[ $m == div || $m == sdiv ]] && it=5000000
    for r in $(seq 0 $REPS); do
      OMP_NUM_THREADS=$T $B/peak $m $it | grep -v '^CSV,arch' | sed "s/^/rep=$r,/"
    done
  done
done > $OUT/peak.csv

# A frequência não aparece no Linux (ver info-dev-arm): medimos com perf se existir;
# senão, pelo modo lat (latência FMA do A64FX = 9 ciclos -> f = 9 / t_por_FMA)
echo ">> frequência"
if command -v perf >/dev/null; then
  for T in 1 12 48; do echo "== T=$T"; OMP_NUM_THREADS=$T perf stat -e cycles,task-clock $B/peak fma 200000000 2>&1; done > $OUT/freq.txt
else
  echo "perf não disponível: usar o modo lat" > $OUT/freq.txt
fi

#  L1d 64 KiB -> 32 KiB | L2 8 MiB/12 cores -> 512 KiB por thread | HBM -> 131072 KiB por thread
echo ">> triad"
for T in 1 12 48; do
  for k in 32 512 131072; do
    for r in $(seq 0 $REPS); do
      OMP_NUM_THREADS=$T $B/triad $k 0.5 | grep -v '^CSV,threads' | sed "s/^/rep=$r,/"
    done
  done
done > $OUT/triad.csv

# STREAM do Lab 2.5 (inclui as versões zfill, que evitam o write-allocate)
echo ">> stream"
STREAM_DIR=/projects/F202500010HPCVLABUMINHO/ACA/lab2.5/stream
ls $STREAM_DIR > $OUT/stream_dir.txt 2>&1
for src in stream stream_openmp stream_zfill stream_zfill_acle; do
  if [ -f $STREAM_DIR/$src.c ]; then
    gcc -O3 -mcpu=a64fx -fopenmp -DSTREAM_ARRAY_SIZE=80000000 -DNTIMES=20 $STREAM_DIR/$src.c -o $B/$src.arm 2>>$OUT/build.txt || continue
    for T in 12 24 48; do echo "== $src T=$T"; OMP_NUM_THREADS=$T $B/$src.arm; done
  fi
done > $OUT/stream.txt

# SGEMM com a SSL2 da Fujitsu (como no Lab 2.5)
echo ">> sgemm"
if ml FJSVstclanga 2>/dev/null; then
  fcc -Kfast,openmp sgemm.c -SSL2BLAMP -o $B/sgemm_fj && OMP_NUM_THREADS=48 $B/sgemm_fj 8192 $REPS > $OUT/sgemm.csv 2>&1
else
  echo "módulo FJSVstclanga não encontrado" > $OUT/sgemm.csv
fi

echo "FIM. Resultados em $OUT/"

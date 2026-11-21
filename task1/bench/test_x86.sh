#!/bin/bash
# TESTE RÁPIDO x86 (~5 min) - correr ANTES de job_t1_x86.sh:  sbatch test_x86.sh
#SBATCH --job-name=t1-test-x86
#SBATCH --account=f202500010hpcvlabuminhox
#SBATCH --partition=dev-x86
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --time=00:15:00
#SBATCH --output=t1-test-x86-%j.out
cd "${SLURM_SUBMIT_DIR}"
ml GCC/13.3.0 || { echo "GCC/13.3.0 não existe; versões:"; ml spider GCC 2>&1 | head -20; }
ml numactl 2>/dev/null
ARCH=x86; CFLAGS="-O3 -march=znver2 -fopenmp"; PEAKFLAGS="-mavx2 -mfma"; NCORES=128
source ./test_common.sh

echo "== específico x86" | tee -a $LOG
STREAM_DIR=/projects/F202500010HPCVLABUMINHO/ACA/lab2.5/stream
if [ -f $STREAM_DIR/stream.c ]; then
  gcc -O3 -march=znver2 -fopenmp -DSTREAM_ARRAY_SIZE=10000000 -DNTIMES=5 $STREAM_DIR/stream.c -o $B/stream 2>>$LOG \
    && OMP_NUM_THREADS=128 $B/stream 2>&1 | grep -q "Triad:" && ok "STREAM compila e corre" || fail "STREAM" "ver $LOG"
else fail "STREAM" "não há stream.c em $STREAM_DIR (ver ls no log)"; fi
ml OpenBLAS 2>>$LOG && ok "módulo OpenBLAS ($(ml -t list 2>&1 | grep -i openblas))" || fail "módulo OpenBLAS" "ver: ml spider OpenBLAS"
gcc -O2 -fopenmp -o $B/sgemm sgemm.c -lopenblas 2>>$LOG && ok "compila sgemm" || fail "compila sgemm" "ver $LOG"
check "sgemm n=1024" env OMP_NUM_THREADS=128 OPENBLAS_NUM_THREADS=128 $B/sgemm 1024 2

echo; echo "RESUMO: ${#OKS[@]} OK, ${#FAILS[@]} FALHOU" | tee -a $LOG
for f in "${FAILS[@]}"; do echo "  FALHOU: $f" | tee -a $LOG; done

#!/bin/bash
# TESTE RÁPIDO ARM (~5 min) - correr ANTES de job_t1_arm.sh:  sbatch test_arm.sh
#SBATCH --job-name=t1-test-arm
#SBATCH --account=f202500010hpcvlabuminhoa
#SBATCH --partition=dev-arm
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --time=00:15:00
#SBATCH --output=t1-test-arm-%j.out
cd "${SLURM_SUBMIT_DIR}"
ml GCC/13.3.0 || { echo "GCC/13.3.0 não existe; versões:"; ml spider GCC 2>&1 | head -20; }
ml numactl 2>/dev/null
ARCH=arm; CFLAGS="-O3 -mcpu=a64fx -fopenmp"; PEAKFLAGS="-mcpu=a64fx"; NCORES=48
source ./test_common.sh

echo "== específico ARM" | tee -a $LOG
STREAM_DIR=/projects/F202500010HPCVLABUMINHO/ACA/lab2.5/stream
n=0
for src in stream stream_openmp stream_zfill stream_zfill_acle; do
  [ -f $STREAM_DIR/$src.c ] || continue; n=$((n+1))
  gcc -O3 -mcpu=a64fx -fopenmp -DSTREAM_ARRAY_SIZE=10000000 -DNTIMES=5 $STREAM_DIR/$src.c -o $B/$src 2>>$LOG \
    && OMP_NUM_THREADS=48 $B/$src 2>&1 | grep -q "Triad:" && ok "$src compila e corre" || fail "$src" "ver $LOG"
done
[ $n -gt 0 ] || fail "STREAM" "nenhum stream*.c em $STREAM_DIR (ver ls no log)"
if ml FJSVstclanga 2>>$LOG; then
  ok "módulo FJSVstclanga"
  fcc -Kfast,openmp sgemm.c -SSL2BLAMP -o $B/sgemm_fj 2>>$LOG && ok "compila sgemm (fcc+SSL2)" || fail "compila sgemm" "ver $LOG"
  check "sgemm n=1024" env OMP_NUM_THREADS=48 $B/sgemm_fj 1024 2
  check "sgemm n=8192 (tamanho do job longo)" env OMP_NUM_THREADS=48 $B/sgemm_fj 8192 1
else fail "módulo FJSVstclanga" "ver: ml spider FJSVstclanga"; fi

echo; echo "RESUMO: ${#OKS[@]} OK, ${#FAILS[@]} FALHOU" | tee -a $LOG
for f in "${FAILS[@]}"; do echo "  FALHOU: $f" | tee -a $LOG; done

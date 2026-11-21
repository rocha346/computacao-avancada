#!/bin/bash
#SBATCH --job-name=t1-sgemm-gcc
#SBATCH --account=f202500010hpcvlabuminhox
#SBATCH --partition=normal-x86
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --time=00:30:00
#SBATCH --output=t1-sgemm-gcc-%j.out
set -u
cd "${SLURM_SUBMIT_DIR}"
QUICK=${QUICK:-0}
ml purge
ml GCC/13.3.0 OpenBLAS/0.3.27-GCC-13.3.0 || { echo "ERRO: modulos"; exit 1; }
ml numactl 2>/dev/null; command -v numactl >/dev/null || { echo "ERRO: numactl"; exit 1; }
OUT=res-sgemm-gcc-${SLURM_JOB_ID}; B=build-sgemm-gcc-${SLURM_JOB_ID}; mkdir -p $OUT $B
NFAIL=0
ml -t list > $OUT/modules.txt 2>&1
gcc -O2 -fopenmp -o $B/sgemm sgemm.c -lopenblas 2>$OUT/build.txt || { echo 'ERRO: sgemm nao compilou'; exit 1; }
ldd $B/sgemm | grep -i -E "omp|blas" > $OUT/ldd.txt
cat $OUT/ldd.txt
if grep -q "libomp\.so" $OUT/ldd.txt; then echo "FALHOU: ainda carrega libomp" >> $OUT/falhas.txt; NFAIL=$((NFAIL+1)); fi
if [ "$QUICK" = 1 ]; then NS="1024"; REPS=2; else NS="8192 16384"; REPS=10; fi
T=128
for n in $NS; do
  for cfg in livre livreInterleave bindClose bindSpread; do
    case $cfg in
      livre)           run=(env -u OMP_PLACES -u OMP_PROC_BIND) ;;
      livreInterleave) run=(env -u OMP_PLACES -u OMP_PROC_BIND numactl --interleave=all) ;;
      bindClose)       run=(env OMP_PLACES=cores OMP_PROC_BIND=close) ;;
      bindSpread)      run=(env OMP_PLACES=cores OMP_PROC_BIND=spread) ;;
    esac
    out=$(OMP_NUM_THREADS=$T OPENBLAS_NUM_THREADS=$T timeout 300 "${run[@]}" $B/sgemm $n $REPS 2>>$OUT/stderr.txt)
    nl=$(echo "$out" | grep -c '^CSV,[0-9]')
    echo "$out" | grep '^CSV,[0-9]' | sed "s/^/cfg=$cfg,/"
    if [ "$nl" -ne "$REPS" ]; then echo "FALHOU: $cfg n=$n ($nl de $REPS)" >> $OUT/falhas.txt; NFAIL=$((NFAIL+1)); fi
  done
done > $OUT/sgemm.csv
echo "== GFLOP/s por repeticao"
cat $OUT/falhas.txt 2>/dev/null
awk -F, '{k=$1" n="$3; s[k]=s[k]" "$6} END{for(k in s) print k":"s[k]}' $OUT/sgemm.csv | sort
echo "RESUMO: $NFAIL FALHOU   (resultados em $OUT/)"

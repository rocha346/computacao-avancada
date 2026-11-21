#!/bin/bash
#SBATCH --job-name=t1-sgemm-diag
#SBATCH --account=f202500010hpcvlabuminhox
#SBATCH --partition=normal-x86
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --time=00:40:00
#SBATCH --output=t1-sgemm-diag-%j.out
set -u
cd "${SLURM_SUBMIT_DIR}"
QUICK=${QUICK:-0}
OUT=res-sgemm-diag-${SLURM_JOB_ID}; mkdir -p $OUT
NFAIL=0
if [ "$QUICK" = 1 ]; then N=1024; REPS=2; else N=16384; REPS=5; fi
for v in v027 v032; do
  (
    ml purge
    if [ $v = v027 ]; then ml GCC/13.3.0 OpenBLAS/0.3.27-GCC-13.3.0; else ml GCC/13.3.0 OpenBLAS; fi
    ml numactl 2>/dev/null
    ml -t list > $OUT/modules-$v.txt 2>&1
    gcc -O2 -fopenmp -o $OUT/sgemm-$v sgemm.c -lopenblas 2>$OUT/build-$v.txt || { echo "FALHOU: build $v"; exit 1; }
    ldd $OUT/sgemm-$v | grep -i -E "omp|blas" > $OUT/ldd-$v.txt
    OPENBLAS_VERBOSE=2 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 $OUT/sgemm-$v 256 1 &> $OUT/core-$v.txt
    for cfg in T128-livre T128-interleave T128-bindClose T64-bindSpread T64-livre; do
      T=${cfg%%-*}; T=${T#T}
      case ${cfg#*-} in
        livre)      run=(env -u OMP_PLACES -u OMP_PROC_BIND) ;;
        interleave) run=(env -u OMP_PLACES -u OMP_PROC_BIND numactl --interleave=all) ;;
        bindClose)  run=(env OMP_PLACES=cores OMP_PROC_BIND=close) ;;
        bindSpread) run=(env OMP_PLACES=cores OMP_PROC_BIND=spread) ;;
      esac
      out=$(OMP_NUM_THREADS=$T OPENBLAS_NUM_THREADS=$T timeout 240 "${run[@]}" $OUT/sgemm-$v $N $REPS 2>>$OUT/stderr-$v.txt)
      rc=$?
      echo "$out" | grep '^CSV,[0-9]' | sed "s/^/$v,$cfg,/"
      [ $rc = 124 ] && echo "TIMEOUT: $v $cfg" >&2
    done; true
  ) >> $OUT/sgemm.csv 2>>$OUT/avisos.txt || NFAIL=$((NFAIL+1))
done
echo "== kernel escolhido pelo OpenBLAS"; grep -H . $OUT/core-*.txt
echo "== bibliotecas"; grep -H . $OUT/ldd-*.txt
echo "== avisos"; cat $OUT/avisos.txt
echo "== GFLOP/s por repeticao (versao, config)"
awk -F, '{k=$1" "$2; s[k]=s[k]" "$7} END{for(k in s) print k":"s[k]}' $OUT/sgemm.csv | sort
echo "RESUMO: $NFAIL FALHOU   (resultados em $OUT/)"

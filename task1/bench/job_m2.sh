#!/bin/bash
# =============================================================================
# ACA WA2 - Task 1.3 - Teto M2 "NUMA errado" (P01 / D16).
# Mede o STREAM com TODAS as threads mas com TODA a memória num só nó NUMA
# (numactl --membind=0). É o que acontece ao Jacobi quando os arrays são
# inicializados por 1 thread (first touch): todas as páginas ficam no nó 0.
# Para comparar, corre também o caso normal (memória espalhada pelo first
# touch paralelo do próprio STREAM), no MESMO job.
# O mesmo script serve para as duas máquinas: ARCH=x86 ou ARCH=arm.
#
# TESTE RÁPIDO primeiro (partição dev, tamanhos pequenos):
#   x86: sbatch -A f202500010hpcvlabuminhox -p dev-x86 -t 00:10:00 --export=ALL,ARCH=x86,QUICK=1 job_m2.sh
#   ARM: sbatch -A f202500010hpcvlabuminhoa -p dev-arm -t 00:10:00 --export=ALL,ARCH=arm,QUICK=1 job_m2.sh
# Se o fim do .out disser "RESUMO: 0 FALHOU", a sério:
#   x86: sbatch -A f202500010hpcvlabuminhox -p normal-x86 -t 00:20:00 --export=ALL,ARCH=x86 job_m2.sh
#   ARM: sbatch -A f202500010hpcvlabuminhoa -p normal-arm -t 00:20:00 --export=ALL,ARCH=arm job_m2.sh
# (-A = conta, -p = partição, -t = tempo: mudam com a máquina, por isso vão
#  na linha de comando e não aqui dentro)
# =============================================================================
#SBATCH --job-name=t1-m2
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --output=t1-m2-%j.out

set -u
cd "${SLURM_SUBMIT_DIR}"
ARCH=${ARCH:?falta --export=ALL,ARCH=x86 ou ARCH=arm}
QUICK=${QUICK:-0}
ml GCC/13.3.0 || { echo 'ERRO: GCC/13.3.0 nao existe'; exit 1; }
ml numactl 2>/dev/null
command -v numactl >/dev/null || { echo 'ERRO: numactl nao existe'; exit 1; }

OUT=res-m2-$ARCH-${SLURM_JOB_ID}; B=build-m2-$ARCH-${SLURM_JOB_ID}; mkdir -p $OUT $B
NFAIL=0
fail() { echo "FALHOU: $1" >> $OUT/falhas.txt; echo "FALHOU: $1" >&2; NFAIL=$((NFAIL+1)); }
export OMP_PLACES=cores OMP_PROC_BIND=close
SRC=/projects/F202500010HPCVLABUMINHO/ACA/lab2.5/stream

# Mesmo STREAM e mesmos tamanhos dos jobs anteriores (comparável com M3/M4)
if [ "$ARCH" = x86 ]; then
  T=128; N=268435456; [ "$QUICK" = 1 ] && N=10000000
  gcc -O3 -march=znver2 -fopenmp -mcmodel=medium -DSTREAM_ARRAY_SIZE=$N -DNTIMES=20 \
      $SRC/stream.c -o $B/stream 2>>$OUT/build.txt || { fail "stream nao compilou"; }
else
  T=48; N=80000000; [ "$QUICK" = 1 ] && N=10000000
  S=$B/stream_src; mkdir -p $S; for f in stream.c stream.h kernel-openmp.c Makefile; do cp $SRC/$f $S/ || fail "copia $f"; done
  ( cd $S && make KERNEL=openmp COMPILER=gnu STREAM_ARRAY_SIZE=$N NTIMES=20 ) >> $OUT/build.txt 2>&1 \
    && cp $S/stream_openmp.exe $B/stream || fail "make KERNEL=openmp"
fi
numactl -H > $OUT/numa.txt 2>&1

for cfg in normal membind0; do
  case $cfg in
    normal)   run=() ;;
    membind0) run=(numactl --membind=0) ;;
  esac
  echo "== $cfg T=$T"
  out=$(OMP_NUM_THREADS=$T ${run[@]+"${run[@]}"} $B/stream 2>&1); echo "$out"
  echo "$out" | grep -q "Solution Validates" || fail "stream $cfg nao validou"
done > $OUT/stream.txt

echo "== STREAM (MB/s): configuracao, Copy, Triad"
awk '/^== /{c=$2} /^Copy:/{cp=$2} /^Triad:/{print c, cp, $2}' $OUT/stream.txt
echo "RESUMO: $NFAIL FALHOU   (resultados em $OUT/)"

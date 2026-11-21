#!/bin/bash
# =============================================================================
# ACA WA2 - Task 1 - JOB DE CORREÇÃO ARM (ver analise_resultados_t1.txt, sec. 3)
# Corrige 2 problemas do job 2253872 e mede o tamanho de página:
#  (a) STREAM: as versões zfill não correram (o script procurava stream_zfill.c).
#      No Lab 2.5 cada versão = stream.c + kernel-<versao>.c, compilada pelo
#      Makefile do professor com KERNEL=<versao>. Aqui usamos ESSE Makefile
#      (numa cópia nossa) para as 4 versões: vanilla, openmp, zfill, zfill-acle.
#      zfill = a instrução DC ZVA zera a linha de cache antes de a escrever, o
#      que evita ler da memória a linha que vai ser toda escrita (write-allocate).
#      -> a diferença zfill vs openmp mede o teto M3 no A64FX.
#  (b) triad na L2 instável a 512 KiB/thread (6 MiB por CMG = limite da L2).
#      Medimos 128 e 256 KiB/thread (1.5 e 3 MiB por CMG, bem dentro dos 8 MiB).
#  (c) getconf PAGESIZE: para confirmar a explicação dos "joelhos" de TLB.
#
# TESTE RÁPIDO primeiro (tamanhos pequenos, partição dev, ~3 min):
#   sbatch -p dev-arm -t 00:15:00 --export=ALL,QUICK=1 job_corr_arm.sh
# Se o fim do .out disser "RESUMO: 0 FALHOU", correr a sério:
#   sbatch job_corr_arm.sh
# =============================================================================
#SBATCH --job-name=t1-corr-arm
#SBATCH --account=f202500010hpcvlabuminhoa
#SBATCH --partition=normal-arm
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --time=00:40:00
#SBATCH --output=t1-corr-arm-%j.out

set -u
cd "${SLURM_SUBMIT_DIR}"
QUICK=${QUICK:-0}
ml GCC/13.3.0 || { echo 'ERRO: GCC/13.3.0 nao existe'; exit 1; }
ml numactl 2>/dev/null

OUT=res-corr-arm-${SLURM_JOB_ID}; B=build-corr-arm-${SLURM_JOB_ID}; mkdir -p $OUT $B
NFAIL=0
# fail: regista no falhas.txt e no ecrã (stderr), nunca no meio dos ficheiros de resultados
fail() { echo "FALHOU: $1" >> $OUT/falhas.txt; echo "FALHOU: $1" >&2; NFAIL=$((NFAIL+1)); }
export OMP_PLACES=cores OMP_PROC_BIND=close

if [ "$QUICK" = 1 ]; then SSIZE=10000000; NT=5; REPS=2; TT=0.05; else SSIZE=80000000; NT=20; REPS=10; TT=0.5; fi

# ---- (c) páginas ----
{ echo "PAGESIZE=$(getconf PAGESIZE)"
  echo "THP=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)"
  grep -i huge /proc/meminfo; } > $OUT/pages.txt
echo "gcc $(gcc -dumpfullversion)" > $OUT/build.txt

# ---- (b) triad L2 com tamanhos seguros ----
echo ">> triad L2"
gcc -O3 -mcpu=a64fx -fopenmp -o $B/triad triad.c 2>>$OUT/build.txt || fail "triad nao compilou"
for T in 1 12 48; do
  for k in 128 256; do
    for r in $(seq 0 $REPS); do
      line=$(OMP_NUM_THREADS=$T $B/triad $k $TT | grep '^CSV,[0-9]')
      [ -n "$line" ] && echo "rep=$r,$line" || fail "triad T=$T k=$k rep=$r"
    done
  done
done > $OUT/triad_l2.csv

# ---- (a) STREAM: as 4 versões, com o Makefile do professor ----
echo ">> stream"
SRC=${STREAM_SRC:-/projects/F202500010HPCVLABUMINHO/ACA/lab2.5/stream}
S=$B/stream_src; mkdir -p $S
cp $SRC/*.c $SRC/*.h $SRC/Makefile $S/ || fail "copia do STREAM"
for k in vanilla openmp zfill zfill-acle; do
  [ -f $S/kernel-$k.c ] || { fail "nao existe kernel-$k.c"; continue; }
  # stream.o tem de ser recompilado para cada versão (o -DSTREAM_KERNEL muda),
  # mas o Makefile só olha para as datas dos ficheiros: apagamos os .o da NOSSA cópia.
  rm -f $S/*.o
  ( cd $S && make KERNEL=$k COMPILER=gnu STREAM_ARRAY_SIZE=$SSIZE NTIMES=$NT ) >> $OUT/build.txt 2>&1 \
    || { fail "make KERNEL=$k"; continue; }
  for T in 12 24 48; do
    echo "== $k T=$T"
    out=$(OMP_NUM_THREADS=$T $S/stream_$k.exe 2>&1); echo "$out"
    echo "$out" | grep -q "Solution Validates" || fail "stream $k T=$T nao validou"
  done
done > $OUT/stream.txt

echo "== pages.txt"; cat $OUT/pages.txt
echo "== STREAM Triad (MB/s) por versao e threads"
awk '/^== /{v=$2" "$3} /^Triad:/{print v, $2}' $OUT/stream.txt
echo "== triad L2 (GB/s): threads, KiB/thread, valores"
awk -F, '{k=$3" "$4; s[k]=s[k]" "$7} END{for(k in s) print k":"s[k]}' $OUT/triad_l2.csv | sort -n
echo "RESUMO: $NFAIL FALHOU   (resultados em $OUT/)"

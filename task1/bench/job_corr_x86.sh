#!/bin/bash
# =============================================================================
# ACA WA2 - Task 1 - JOB DE CORREÇÃO x86 (ver analise_resultados_t1.txt, sec. 4)
# Porquê: o SGEMM do AMD deu só 25% do pico medido (2 782 de 11 269 GFLOP/s).
# Testa 3 hipóteses, mudando UMA coisa de cada vez (para saber qual é a causa):
#   base       = igual ao job 2253871 (OMP_PLACES=cores, OMP_PROC_BIND=close)
#   interleave = base + numactl --interleave=all (páginas espalhadas pelos 8 nós NUMA)
#   semBind    = interleave, mas SEM OMP_PROC_BIND/OMP_PLACES (o OpenBLAS cria
#                threads próprias; o "bind" do OpenMP pode atrapalhá-las)
# e 2 tamanhos (n=8192 como antes, n=16384 = mais trabalho por thread).
# Também regista: tamanho de página (para a curva de latência) e o kernel que o
# OpenBLAS escolheu (OPENBLAS_VERBOSE=2 imprime "Core: ...").
#
# TESTE RÁPIDO primeiro (tamanhos pequenos, partição dev, ~2 min):
#   sbatch -p dev-x86 -t 00:10:00 --export=ALL,QUICK=1 job_corr_x86.sh
# Se o resumo no fim do .out disser "0 FALHOU", correr a sério:
#   sbatch job_corr_x86.sh
# =============================================================================
#SBATCH --job-name=t1-corr-x86
#SBATCH --account=f202500010hpcvlabuminhox
#SBATCH --partition=normal-x86
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --time=00:30:00
#SBATCH --output=t1-corr-x86-%j.out

set -u
cd "${SLURM_SUBMIT_DIR}"
QUICK=${QUICK:-0}
ml GCC/13.3.0 || { echo 'ERRO: GCC/13.3.0 nao existe'; exit 1; }
ml numactl 2>/dev/null
ml OpenBLAS 2>/dev/null || { echo 'ERRO: modulo OpenBLAS nao existe'; exit 1; }
command -v numactl >/dev/null || { echo 'ERRO: numactl nao existe (precisamos do --interleave)'; exit 1; }

OUT=res-corr-x86-${SLURM_JOB_ID}; B=build-corr-x86-${SLURM_JOB_ID}; mkdir -p $OUT $B
NFAIL=0

# ---- páginas de memória (explica os "joelhos" de TLB na curva de latência) ----
{ echo "PAGESIZE=$(getconf PAGESIZE)"
  echo "THP=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)"
  grep -i huge /proc/meminfo; } > $OUT/pages.txt
ml -t list > $OUT/modules.txt 2>&1
echo "gcc $(gcc -dumpfullversion)" > $OUT/build.txt

gcc -O2 -fopenmp -o $B/sgemm sgemm.c -lopenblas 2>>$OUT/build.txt || { echo 'ERRO: sgemm nao compilou'; exit 1; }

# Que kernel o OpenBLAS usa neste CPU? (Zen / Haswell / ...): só informativo
OPENBLAS_VERBOSE=2 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 $B/sgemm 256 1 > $OUT/openblas_core.txt 2>&1

if [ "$QUICK" = 1 ]; then NS="1024"; REPS=2; else NS="8192 16384"; REPS=10; fi
T=128
echo ">> sgemm (n = $NS, $REPS reps, $T threads)"
for n in $NS; do
  # Job 2254225 mostrou que com OMP_PROC_BIND=close o SGEMM cai para 15.7 GFLOP/s
  # (~70 s por chamada): já está medido, não repetimos. Agora, SEM bind, separamos
  # o efeito NUMA:  livre = sem bind, memória onde calhar (first touch)
  #                 livreInterleave = sem bind + páginas espalhadas pelos 8 nós NUMA
  for cfg in livre livreInterleave; do
    R=$REPS
    case $cfg in
      livre)           run=(env -u OMP_PLACES -u OMP_PROC_BIND) ;;
      livreInterleave) run=(env -u OMP_PLACES -u OMP_PROC_BIND numactl --interleave=all) ;;
    esac
    out=$(OMP_NUM_THREADS=$T OPENBLAS_NUM_THREADS=$T "${run[@]}" $B/sgemm $n $R 2>>$OUT/sgemm_stderr.txt)
    nl=$(echo "$out" | grep -c '^CSV,[0-9]')
    echo "$out" | grep '^CSV,[0-9]' | sed "s/^/cfg=$cfg,/"
    if [ "$nl" -ne "$R" ]; then echo "FALHOU: sgemm $cfg n=$n ($nl linhas CSV em vez de $R)" >> $OUT/falhas.txt; NFAIL=$((NFAIL+1)); fi
  done
done > $OUT/sgemm.csv

echo "== pages.txt"; cat $OUT/pages.txt
echo "== GFLOP/s de cada repeticao, por configuracao"
cat $OUT/falhas.txt 2>/dev/null
awk -F, '{k=$1" n="$3; s[k]=s[k]" "$6} END{for(k in s) print k":"s[k]}' $OUT/sgemm.csv | sort
echo "RESUMO: $NFAIL FALHOU   (resultados em $OUT/)"

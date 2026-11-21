#!/bin/bash
# =============================================================================
# ACA WA2 - TESTE RÁPIDO antes dos jobs longos (chamado por test_x86.sh e
# test_arm.sh). Verifica, em poucos minutos e com tamanhos pequenos, que:
#   - os módulos e ferramentas existem (gcc, numactl, perf, OpenBLAS/Fujitsu)
#   - cada programa compila e corre UMA vez com saída válida
#   - os ficheiros do STREAM do Lab 2.5 existem
# No fim imprime um resumo OK/FALHOU. Só avançamos para o job longo com tudo OK.
# Variáveis esperadas: ARCH (x86|arm), PEAKFLAGS, CFLAGS
# =============================================================================
set -u
B=test-build-$ARCH-${SLURM_JOB_ID:-local}; mkdir -p $B
LOG=test-$ARCH-${SLURM_JOB_ID:-local}.log
: > $LOG
OKS=(); FAILS=()
ok()   { OKS+=("$1");   echo "[OK]      $1" | tee -a $LOG; }
fail() { FAILS+=("$1"); echo "[FALHOU]  $1 :: $2" | tee -a $LOG; }
# check NOME COMANDO... : corre o comando, guarda a saída no log e exige
# exit 0 e pelo menos 2 linhas "CSV," (cabeçalho + dados)
check() { local name=$1; shift; local out rc; out=$("$@" 2>&1); rc=$?
          echo "--- $name (exit $rc)" >> $LOG; echo "$out" >> $LOG
          local ncsv; ncsv=$(echo "$out" | grep -c '^CSV,')
          if [ $rc -eq 0 ] && [ "$ncsv" -ge 2 ]; then ok "$name"; else fail "$name" "exit=$rc, linhas CSV=$ncsv: $(echo "$out" | tail -2 | tr '\n' ' ')"; fi; }

echo "== ferramentas" | tee -a $LOG
command -v gcc     >/dev/null && ok "gcc $(gcc -dumpfullversion) em $(command -v gcc); $(as --version | head -1)" || fail "gcc" "não encontrado"
command -v numactl >/dev/null && ok "numactl"  || fail "numactl" "não encontrado (ml numactl)"
command -v perf    >/dev/null && ok "perf"     || echo "[AVISO]   perf não existe: a frequência será medida pelo modo lat" | tee -a $LOG

echo "== compilação" | tee -a $LOG
gcc $CFLAGS -o $B/latency latency.c 2>>$LOG && ok "compila latency" || fail "compila latency" "ver $LOG"
gcc -O2 $PEAKFLAGS -fopenmp -o $B/peak peak.c 2>>$LOG && ok "compila peak" || fail "compila peak" "ver $LOG"
gcc $CFLAGS -o $B/triad triad.c 2>>$LOG && ok "compila triad" || fail "compila triad" "ver $LOG"

echo "== execução (tamanhos pequenos)" | tee -a $LOG
NUMA="numactl --physcpubind=0 --membind=0"; command -v numactl >/dev/null || NUMA="taskset -c 0"
check "latency 4KiB-1MiB"  $NUMA $B/latency 4 1
for m in fma muladd add div sfma sdiv lat; do
  check "peak $m (1 thread)" env OMP_NUM_THREADS=1 $B/peak $m 1000000
done
check "peak fma (todos os cores)" env OMP_NUM_THREADS=$NCORES $B/peak fma 1000000
check "triad L1 (1 thread)"   env OMP_NUM_THREADS=1 $B/triad 16 0.05
check "triad RAM (todos)"     env OMP_NUM_THREADS=$NCORES $B/triad 65536 0.05

# Validação de plausibilidade: o pico fma de 1 core tem de estar entre 10 e 200 GFLOP/s
g=$(env OMP_NUM_THREADS=1 $B/peak fma 20000000 | awk -F, '/^CSV,[a-z]/ && $3=="fma"{print $9}')
awk -v g="$g" 'BEGIN{exit !(g>10 && g<200)}' && ok "peak fma 1 core plausível ($g GFLOP/s)" || fail "peak fma plausível" "valor $g"

echo "== STREAM do Lab 2.5" | tee -a $LOG
STREAM_DIR=/projects/F202500010HPCVLABUMINHO/ACA/lab2.5/stream
ls -la $STREAM_DIR >> $LOG 2>&1 && ok "pasta STREAM existe (conteúdo no log)" || fail "pasta STREAM" "$STREAM_DIR não acessível"

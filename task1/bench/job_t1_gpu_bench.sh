#!/bin/bash
# =============================================================================
# ACA WA2 - Task 1.1 - Medições na A100 (pico FP32, banda HBM, latência).
# Completa a D02 (teórico + medido) para a 3ª partição.
# TESTE RÁPIDO primeiro (~2 min):
#   sbatch --export=ALL,QUICK=1 job_t1_gpu_bench.sh
# Se o fim do .out disser "RESUMO: 0 FALHOU", correr a sério:
#   sbatch job_t1_gpu_bench.sh
# Corre na partição dev-a100-40 (a mesma do gpu_props), com 1 GPU só para nós:
# as outras GPUs do nó podem estar ocupadas, mas a memória e os SMs de cada
# GPU são independentes, por isso não interferem com estas medições.
# =============================================================================
#SBATCH --job-name=t1-gpu-bench
#SBATCH --account=f202500010hpcvlabuminhog
#SBATCH --partition=dev-a100-40
#SBATCH --nodes=1
#SBATCH --gpus=1
#SBATCH --time=00:20:00
#SBATCH --output=t1-gpu-bench-%j.out

set -u
cd "${SLURM_SUBMIT_DIR}"
QUICK=${QUICK:-0}
ml CUDA || { echo 'ERRO: modulo CUDA nao existe (ml spider CUDA)'; exit 1; }
OUT=res-gpu-${SLURM_JOB_ID}; B=build-gpu-${SLURM_JOB_ID}; mkdir -p $OUT $B
NFAIL=0
fail() { echo "FALHOU: $1" >> $OUT/falhas.txt; echo "FALHOU: $1" >&2; NFAIL=$((NFAIL+1)); }
if [ "$QUICK" = 1 ]; then Q=quick; REPS=2; else Q=full; REPS=10; fi

echo "$(nvcc --version | tail -1)" > $OUT/build.txt
nvidia-smi --query-gpu=name,clocks.sm,clocks.max.sm,clocks.applications.graphics,clocks.mem,ecc.mode.current --format=csv >> $OUT/build.txt 2>&1
nvcc -O3 -arch=sm_80 -o $B/gpu_bench gpu_bench.cu 2>>$OUT/build.txt || { fail "nvcc nao compilou (ver build.txt)"; echo "RESUMO: $NFAIL FALHOU"; exit 1; }

# run MODO FICHEIRO NLINHAS: corre, guarda, exige exit 0 e NLINHAS linhas CSV de dados
run() { local m=$1 f=$2 need=$3 out rc
        out=$($B/gpu_bench $m $REPS $Q 2>&1); rc=$?
        echo "$out" > $OUT/$f
        local n; n=$(( $(echo "$out" | grep -c '^CSV,') - 1 ))   # linhas CSV menos o cabeçalho
        [ $rc -eq 0 ] && [ "$n" -ge "$need" ] || fail "$m (exit $rc, $n linhas): $(echo "$out" | tail -1)"; }

echo ">> pico FP32 (com registo do clock do SM a cada 100 ms)"
nvidia-smi --query-gpu=timestamp,clocks.sm,power.draw,temperature.gpu --format=csv -lms 100 > $OUT/clock.csv 2>&1 &
SMI=$!
run peak peak.csv $((REPS+1))
kill $SMI 2>/dev/null; wait $SMI 2>/dev/null

echo ">> banda HBM (triad)"
run triad triad.csv $((REPS+1))

echo ">> latencia (pointer chasing)"
run lat latency.csv 20

echo "== pico (GFLOP/s por repeticao; a 1a e aquecimento)"
awk -F, '/^CSV,peak/{printf " %s", $8} END{print ""}' $OUT/peak.csv
echo "== triad (GB/s por repeticao)"
awk -F, '/^CSV,triad/{printf " %s", $6} END{print ""}' $OUT/triad.csv
echo "== clock do SM durante o pico (MHz, min/max)"
awk -F', ' 'NR>1 && $2+0>0 {v=$2+0; if(!mn||v<mn)mn=v; if(v>mx)mx=v} END{print mn" / "mx}' $OUT/clock.csv
echo "== latencia: primeiras e ultimas linhas"
grep '^CSV,[0-9]' $OUT/latency.csv | sed -n '1p;$p'
echo "RESUMO: $NFAIL FALHOU   (resultados em $OUT/)"

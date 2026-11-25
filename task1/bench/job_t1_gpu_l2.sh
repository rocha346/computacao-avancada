#!/bin/bash
# =============================================================================
# ACA WA2 - Task 1.1 (D28) - Banda da L2 (LLC) da A100 + modelo do nó GPU.
# Preenche o "--" da Tabela I ("L3; LLC BW") pedido na 1.1(iii).
# TESTE RÁPIDO primeiro (~1 min):
#   sbatch --export=ALL,QUICK=1 job_t1_gpu_l2.sh
# Se o fim do .out disser "RESUMO: 0 FALHOU", correr a sério (~2 min):
#   sbatch job_t1_gpu_l2.sh
# Precisa do gpu_bench.cu NOVO (modo l2, versão 3) na mesma pasta.
# =============================================================================
#SBATCH --job-name=t1-gpu-l2
#SBATCH --account=f202500010hpcvlabuminhog
#SBATCH --partition=dev-a100-40
#SBATCH --nodes=1
#SBATCH --gpus=1
#SBATCH --time=00:10:00
#SBATCH --output=t1-gpu-l2-%j.out

set -u
cd "${SLURM_SUBMIT_DIR}"
QUICK=${QUICK:-0}
ml CUDA || { echo 'ERRO: modulo CUDA nao existe (ml spider CUDA)'; exit 1; }
OUT=res-gpu-l2-${SLURM_JOB_ID}; B=build-gpu-l2-${SLURM_JOB_ID}; mkdir -p $OUT $B
NFAIL=0
fail() { echo "FALHOU: $1" >> $OUT/falhas.txt; echo "FALHOU: $1" >&2; NFAIL=$((NFAIL+1)); }
if [ "$QUICK" = 1 ]; then Q=quick; REPS=2; else Q=full; REPS=10; fi
NSIZES=11                                    # tamanhos do modo l2 no gpu_bench.cu

grep -q 'wall_s' gpu_bench.cu || { echo 'ERRO: gpu_bench.cu antigo (sem a versao 3 do modo l2): copiar o novo'; exit 1; }

# ---- 1) modelo do nó GPU (1.1 i) e ligações entre GPUs ----
{
  echo "== dmi (fabricante e modelo do no)"
  for f in sys_vendor product_name product_version board_vendor board_name; do
      printf '%-16s ' $f; cat /sys/class/dmi/id/$f 2>&1
  done
  echo "== nvidia-smi -L";            nvidia-smi -L 2>&1
  echo "== nvidia-smi topo -m";       nvidia-smi topo -m 2>&1
  echo "== nvidia-smi nvlink -s";     nvidia-smi nvlink -s 2>&1
  echo "== Slurm (GPUs do no)";       scontrol show node $(hostname -s) 2>&1 | grep -i 'gres\|NodeName'
} > $OUT/node.txt

# ---- 2) banda da L2 ----
echo "$(nvcc --version | tail -1)" > $OUT/build.txt
nvidia-smi --query-gpu=name,clocks.sm,clocks.max.sm,clocks.mem --format=csv >> $OUT/build.txt 2>&1
nvcc -O3 -arch=sm_80 -o $B/gpu_bench gpu_bench.cu 2>>$OUT/build.txt || { fail "nvcc nao compilou (ver build.txt)"; echo "RESUMO: $NFAIL FALHOU"; exit 1; }

echo ">> banda da L2 (triad .cg, 3 a 96 MiB no total + 384/1536 MiB de controlo)"
nvidia-smi --query-gpu=timestamp,clocks.sm,clocks.mem,power.draw --format=csv -lms 200 > $OUT/clock.csv 2>&1 &
SMI=$!
out=$($B/gpu_bench l2 $REPS $Q 2>&1); rc=$?
kill $SMI 2>/dev/null; wait $SMI 2>/dev/null
echo "$out" > $OUT/l2.csv
n=$(echo "$out" | grep -c '^CSV,l2,')
need=$(( NSIZES * (REPS + 1) ))
[ $rc -eq 0 ] && [ "$n" -eq "$need" ] || fail "l2 (exit $rc, $n de $need linhas): $(echo "$out" | tail -1)"

# ---- 3) resumo: mediana por tamanho (sem a repeticao 0 = aquecimento) ----
echo "== L2: mediana GB/s por tamanho total (MiB)"
grep '^CSV,l2,' $OUT/l2.csv | awk -F, '$4>0 {print $3, $7}' | sort -k1,1n -k2,2n | awk '
  { v[$1]=v[$1]" "$2; c[$1]++ }
  END { for (m in c) { split(substr(v[m],2), a, " "); k=int((c[m]+1)/2); printf "  %4s MiB: %8.1f GB/s  (%d reps)\n", m, a[k], c[m] } }' | sort -k1,1n
# controlo: com 1536 MiB os dados vêm da HBM, cujo máximo é 1555 GB/s.
# Se der mais, a medição está errada (foi o que aconteceu na versão 1).
hbm=$(grep '^CSV,l2,1536,' $OUT/l2.csv | awk -F, '$4>0 {print $7}' | sort -n | awk '{v[NR]=$1} END{print v[int((NR+1)/2)]}')
echo "== controlo HBM (1536 MiB): $hbm GB/s (tem de ser <= 1555)"
awk -v h="$hbm" 'BEGIN{exit !(h+0 > 0 && h+0 <= 1555)}' || fail "controlo HBM: $hbm GB/s impossivel ou em falta"
echo "== clock do SM durante a medicao (MHz, min/max)"
awk -F', ' 'NR>1 && $2+0>0 {v=$2+0; if(!mn||v<mn)mn=v; if(v>mx)mx=v} END{print mn" / "mx}' $OUT/clock.csv
echo "== modelo do no"
grep -E '^(sys_vendor|product_name|board_name) ' $OUT/node.txt
echo "== NVLink (linhas com GB/s = ligacoes ativas)"
grep -c 'GB/s' $OUT/node.txt
echo "RESUMO: $NFAIL FALHOU   (resultados em $OUT/)"

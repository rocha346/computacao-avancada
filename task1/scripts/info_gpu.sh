#!/bin/bash
# Task 1.1 - informação do nó GPU (4x NVIDIA A100 40GB + 2x AMD EPYC 7742).  Submeter: sbatch info_gpu.sh
#SBATCH --job-name=t1-info-gpu
#SBATCH --account=CHANGE_ME_g          # contas GPU acabam em 'g'
#SBATCH --partition=dev-a100-40
#SBATCH --nodes=1
#SBATCH --gpus=1
#SBATCH --time=00:05:00
#SBATCH --output=t1-info-gpu-%j.out
ml hwloc 2>/dev/null
ml CUDA 2>/dev/null                    # ver versões com `ml spider CUDA`
bash "${SLURM_SUBMIT_DIR}/info_common.sh"
OUT=info-gpu-${SLURM_JOB_ID}.txt
{
echo "================ nvidia-smi -q ================"; nvidia-smi -q
echo "================ nvidia-smi topo -m ================"; nvidia-smi topo -m
echo "================ nvidia-smi clocks ================"; nvidia-smi --query-gpu=name,clocks.max.sm,clocks.max.mem,memory.total,power.limit --format=csv
echo "================ deviceQuery (se existir) ================"
DQ=$(command -v deviceQuery || ls ${EBROOTCUDA:-/nonexistent}/extras/demo_suite/deviceQuery 2>/dev/null)
[ -n "$DQ" ] && "$DQ" || echo "deviceQuery não encontrado"
} > "$OUT" 2>&1
echo "Escrito $OUT"

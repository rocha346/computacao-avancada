#!/bin/bash
# ACA WA2 - Task 1.1 - Propriedades da A100 (substitui o deviceQuery).
#SBATCH --job-name=t1-gpu-props
#SBATCH --account=f202500010hpcvlabuminhog
#SBATCH --partition=dev-a100-40
#SBATCH --nodes=1
#SBATCH --gpus=1
#SBATCH --time=00:10:00
#SBATCH --output=t1-gpu-props-%j.out
cd "${SLURM_SUBMIT_DIR}"
ml CUDA                       # versões: ml spider CUDA
nvcc -O2 -o gpu_props gpu_props.cu && ./gpu_props

#!/bin/bash
# Task 1.1 - informação do nó x86 (2x AMD EPYC 7742).  Submeter: sbatch info_x86.sh
#SBATCH --job-name=t1-info-x86
#SBATCH --account=CHANGE_ME_x          # contas x86 acabam em 'x' (ver `billing`)
#SBATCH --partition=dev-x86
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --time=00:05:00
#SBATCH --output=t1-info-x86-%j.out
ml hwloc 2>/dev/null
bash "${SLURM_SUBMIT_DIR}/info_common.sh"

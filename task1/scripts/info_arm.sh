#!/bin/bash
# Task 1.1 - informação do nó ARM (Fujitsu A64FX).  Submeter: sbatch info_arm.sh
#SBATCH --job-name=t1-info-arm
#SBATCH --account=CHANGE_ME_a          # contas ARM acabam em 'a'
#SBATCH --partition=dev-arm
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --time=00:05:00
#SBATCH --output=t1-info-arm-%j.out
ml hwloc 2>/dev/null
bash "${SLURM_SUBMIT_DIR}/info_common.sh"

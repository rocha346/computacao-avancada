#!/bin/bash
# ACA WA2 - Task 1.1: recolha de informação do nó (comum às 3 partições).
# Usado pelos scripts info_x86.sh, info_arm.sh e info_gpu.sh. Não submeter diretamente.
OUT=info-${SLURM_JOB_PARTITION:-local}-${SLURM_JOB_ID:-0}.txt
sec() { echo; echo "================ $* ================"; }
{
sec "data / nó";            date; hostname; uname -a
sec "slurm";                scontrol show node "$(hostname -s)" 2>/dev/null
sec "lscpu";                lscpu
sec "lscpu -C (caches)";    lscpu -C 2>/dev/null
sec "caches em /sys (cpu0)"
for d in /sys/devices/system/cpu/cpu0/cache/index*; do
  echo "$(cat $d/level) $(cat $d/type) size=$(cat $d/size) ways=$(cat $d/ways_of_associativity 2>/dev/null) line=$(cat $d/coherency_line_size) shared_with=$(cat $d/shared_cpu_list)"
done
sec "numactl -H";           numactl -H 2>/dev/null
sec "lstopo";               lstopo-no-graphics --no-io 2>/dev/null || echo "lstopo não disponível (tentar: ml hwloc)"
sec "meminfo";              head -5 /proc/meminfo
sec "cpuinfo (1º core)";    awk '/^$/{exit} {print}' /proc/cpuinfo
sec "frequências";          cat /sys/devices/system/cpu/cpu0/cpufreq/{cpuinfo_min_freq,cpuinfo_max_freq,scaling_cur_freq,scaling_governor} 2>/dev/null
sec "módulos carregados";   module list 2>&1
} > "$OUT" 2>&1
echo "Escrito $OUT"

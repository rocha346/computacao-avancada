/*
 * ACA WA2 - Task 1.1 - Propriedades da A100 lidas pelo runtime CUDA.
 * Substitui o deviceQuery, que não existe no Deucalion. Confirma #SMs, clocks,
 * caches e memória, e calcula os picos teóricos a partir desses valores.
 * Compilar: nvcc -O2 -o gpu_props gpu_props.cu
 */
#include <cstdio>
#include <cuda_runtime.h>

int main()
{
    int dev = 0, v;
    cudaDeviceProp p;
    cudaGetDeviceProperties(&p, dev);
    int sm_clock_khz, mem_clock_khz, bus_bits;
    cudaDeviceGetAttribute(&sm_clock_khz,  cudaDevAttrClockRate, dev);
    cudaDeviceGetAttribute(&mem_clock_khz, cudaDevAttrMemoryClockRate, dev);
    cudaDeviceGetAttribute(&bus_bits,      cudaDevAttrGlobalMemoryBusWidth, dev);

    printf("Nome                      : %s (compute capability %d.%d)\n", p.name, p.major, p.minor);
    printf("SMs                       : %d\n", p.multiProcessorCount);
    printf("Clock SM (max)            : %.0f MHz\n", sm_clock_khz / 1e3);
    printf("Memoria global            : %.1f GiB\n", p.totalGlobalMem / 1073741824.0);
    printf("Clock memoria             : %.0f MHz, bus %d bits\n", mem_clock_khz / 1e3, bus_bits);
    printf("L2                        : %.1f MiB\n", p.l2CacheSize / 1048576.0);
    cudaDeviceGetAttribute(&v, cudaDevAttrMaxSharedMemoryPerMultiprocessor, dev);
    printf("Shared memory por SM      : %d KiB\n", v / 1024);
    printf("Registos por SM           : %d\n", p.regsPerMultiprocessor);
    printf("Max threads por SM        : %d\n", p.maxThreadsPerMultiProcessor);
    printf("Warp                      : %d\n", p.warpSize);

    /* Ampere GA100: 64 cores FP32 por SM; 1 FMA = 2 FLOPs */
    double fp32 = p.multiProcessorCount * 64.0 * 2 * sm_clock_khz * 1e3 / 1e12;
    double bw   = 2.0 * mem_clock_khz * 1e3 * (bus_bits / 8.0) / 1e9;   /* HBM2: DDR */
    printf("Pico FP32 calculado       : %.1f TFLOP/s (SMs x 64 x 2 x clock)\n", fp32);
    printf("Banda calculada           : %.0f GB/s (2 x clock mem x bus/8)\n", bw);
    printf("Ridge point FP32          : %.1f FLOP/B\n", fp32 * 1e3 / bw);
    return 0;
}

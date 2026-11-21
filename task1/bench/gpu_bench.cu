/*
 * ACA WA2 - Task 1.1 - Medições na A100 (D02: teórico + medido).
 * Mede, com o mesmo espírito dos programas de CPU:
 *   peak  : pico FP32 com FMAs independentes em registos (como peak.c)
 *   triad : banda da memória global (HBM2) com o kernel Triad a = b + s*c
 *           (o mesmo do STREAM/triad.c: 12 B por elemento contados)
 *   lat   : latência com pointer chasing (1 só thread, como latency.c):
 *           mostra L1, L2 (40 MiB) e HBM
 * Tempos com cudaEvent; 1 aquecimento + REPS repetições (D10).
 * Compilar: nvcc -O3 -arch=sm_80 -o gpu_bench gpu_bench.cu
 * Uso: ./gpu_bench peak|triad|lat [reps] [quick]
 * NOTA: printf só com ASCII (problema do .base64, ver sgemm.c).
 */
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <cuda_runtime.h>

#define CK(x) do { cudaError_t e = (x); if (e != cudaSuccess) { \
    fprintf(stderr, "ERRO CUDA %s na linha %d: %s\n", #x, __LINE__, cudaGetErrorString(e)); exit(1); } } while (0)

/* ---------------- pico FP32 ----------------
 * Cada thread tem NACC acumuladores independentes (esconde a latência da FMA,
 * ~4 ciclos, e a falta de paralelismo dentro do warp). 2 FLOP por FMA. */
#define NACC 8
__global__ void k_peak(float *out, int iters, float a, float b)
{
    float x[NACC];
    #pragma unroll
    for (int k = 0; k < NACC; k++) x[k] = threadIdx.x * 1e-3f + k;
    for (int i = 0; i < iters; i++) {
        #pragma unroll
        for (int k = 0; k < NACC; k++) x[k] = fmaf(x[k], a, b);
    }
    float s = 0;
    #pragma unroll
    for (int k = 0; k < NACC; k++) s += x[k];
    if (s == -12345.f) out[0] = s;          /* nunca acontece; impede o compilador de apagar o ciclo */
}

/* ---------------- Triad ---------------- */
__global__ void k_triad(float *a, const float *b, const float *c, float s, size_t n)
{
    for (size_t i = blockIdx.x * (size_t)blockDim.x + threadIdx.x; i < n; i += (size_t)gridDim.x * blockDim.x)
        a[i] = b[i] + s * c[i];
}

/* ---------------- latência ---------------- */
__global__ void k_chase(const unsigned *next, long steps, unsigned *out)
{
    unsigned p = 0;
    for (long i = 0; i < steps; i++) p = next[p];
    out[0] = p;                              /* usa o resultado: o ciclo não pode ser apagado */
}

static float time_ms(cudaEvent_t t0, cudaEvent_t t1) { float ms; CK(cudaEventElapsedTime(&ms, t0, t1)); return ms; }

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "uso: %s peak|triad|lat [reps] [quick]\n", argv[0]); return 1; }
    const char *mode = argv[1];
    int reps = argc > 2 ? atoi(argv[2]) : 10;
    int quick = argc > 3 && !strcmp(argv[3], "quick");
    cudaDeviceProp p; CK(cudaGetDeviceProperties(&p, 0));
    cudaEvent_t t0, t1; CK(cudaEventCreate(&t0)); CK(cudaEventCreate(&t1));

    if (!strcmp(mode, "peak")) {
        /* 2048 threads por SM (ocupação máxima) em blocos de 256 */
        int threads = 256, blocks = p.multiProcessorCount * (p.maxThreadsPerMultiProcessor / threads);
        int iters = quick ? 1000 : 1000000;   /* ~0.2 s por chamada: dá tempo ao clock de subir */
        float *d; CK(cudaMalloc(&d, sizeof(float)));
        printf("CSV,mode,rep,blocks,threads,iters,ms,GFLOPs\n");
        for (int r = 0; r <= reps; r++) {            /* r=0 = aquecimento */
            CK(cudaEventRecord(t0));
            k_peak<<<blocks, threads>>>(d, iters, 0.9999999f, 1e-7f);
            CK(cudaEventRecord(t1)); CK(cudaEventSynchronize(t1)); CK(cudaGetLastError());
            double ms = time_ms(t0, t1);
            double flop = 2.0 * NACC * (double)iters * blocks * threads;
            printf("CSV,peak,%d,%d,%d,%d,%.3f,%.1f\n", r, blocks, threads, iters, ms, flop / ms / 1e6);
        }
        CK(cudaFree(d));
    } else if (!strcmp(mode, "triad")) {
        /* 3 arrays de 2^28 floats = 3 GiB: muito maior que a L2 (40 MiB) */
        size_t n = quick ? ((size_t)1 << 22) : ((size_t)1 << 28);
        float *a, *b, *c;
        CK(cudaMalloc(&a, n * 4)); CK(cudaMalloc(&b, n * 4)); CK(cudaMalloc(&c, n * 4));
        CK(cudaMemset(a, 0, n * 4)); CK(cudaMemset(b, 0, n * 4)); CK(cudaMemset(c, 0, n * 4));
        int threads = 256, blocks = p.multiProcessorCount * 32;
        printf("CSV,mode,rep,n,ms,GBps\n");
        for (int r = 0; r <= reps; r++) {
            CK(cudaEventRecord(t0));
            k_triad<<<blocks, threads>>>(a, b, c, 3.0f, n);
            CK(cudaEventRecord(t1)); CK(cudaEventSynchronize(t1)); CK(cudaGetLastError());
            double ms = time_ms(t0, t1);
            printf("CSV,triad,%d,%zu,%.3f,%.1f\n", r, n, ms, 12.0 * n / ms / 1e6);
        }
        CK(cudaFree(a)); CK(cudaFree(b)); CK(cudaFree(c));
    } else if (!strcmp(mode, "lat")) {
        /* Ciclo aleatório (Sattolo) com passo de 128 B (1 linha da L2 da A100
         * = 4 setores de 32 B), de 4 KiB até 1 GiB (64 MiB em modo quick). */
        const size_t STRIDE = 128 / sizeof(unsigned);
        size_t maxb = quick ? ((size_t)64 << 20) : ((size_t)1 << 30);
        unsigned *d, *dout; CK(cudaMalloc(&d, maxb)); CK(cudaMalloc(&dout, sizeof(unsigned)));
        printf("CSV,size_bytes,ns_per_access\n");
        srand(12345);
        for (double sz = 4096; sz <= (double)maxb; sz *= 1.189207115) {   /* 2^(1/4) */
            size_t bytes = (size_t)sz / 128 * 128, m = bytes / 128;       /* m nós da lista */
            std::vector<unsigned> h(bytes / sizeof(unsigned), 0), perm(m);
            for (size_t i = 0; i < m; i++) perm[i] = (unsigned)i;
            for (size_t i = m - 1; i > 0; i--) {                         /* Sattolo: 1 só ciclo */
                size_t j = ((size_t)rand() * RAND_MAX + rand()) % i;
                unsigned t = perm[i]; perm[i] = perm[j]; perm[j] = t;
            }
            for (size_t i = 0; i < m; i++) h[i * STRIDE] = (unsigned)(perm[i] * STRIDE);
            CK(cudaMemcpy(d, h.data(), bytes, cudaMemcpyHostToDevice));
            long steps = quick ? 20000 : 1000000;
            k_chase<<<1, 1>>>(d, m, dout);                                 /* aquecimento: 1 volta */
            CK(cudaEventRecord(t0));
            k_chase<<<1, 1>>>(d, steps, dout);
            CK(cudaEventRecord(t1)); CK(cudaEventSynchronize(t1)); CK(cudaGetLastError());
            printf("CSV,%zu,%.2f\n", bytes, time_ms(t0, t1) * 1e6 / steps);
        }
        CK(cudaFree(d)); CK(cudaFree(dout));
    } else { fprintf(stderr, "modo desconhecido: %s\n", mode); return 1; }
    return 0;
}

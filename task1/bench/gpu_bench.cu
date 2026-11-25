/*
 * ACA WA2 - Task 1.1 - Medições na A100 (D02: teórico + medido).
 * Mede, com o mesmo espírito dos programas de CPU:
 *   peak  : pico FP32 com FMAs independentes em registos (como peak.c)
 *   triad : banda da memória global (HBM2) com o kernel Triad a = b + s*c
 *           (o mesmo do STREAM/triad.c: 12 B por elemento contados)
 *   l2    : banda da L2 (LLC da A100) com o Triad em arrays pequenos (D28)
 *   lat   : latência com pointer chasing (1 só thread, como latency.c):
 *           mostra L1, L2 (40 MiB) e HBM
 * Tempos com cudaEvent; 1 aquecimento + REPS repetições (D10).
 * Compilar: nvcc -O3 -arch=sm_80 -o gpu_bench gpu_bench.cu
 * Uso: ./gpu_bench peak|triad|l2|lat [reps] [quick]
 * NOTA: printf só com ASCII (problema do .base64, ver sgemm.c).
 */
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <ctime>
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

/* ---------------- Triad na L2 (D28, versão 2) ----------------
 * Mesmo Triad, mas com os 3 arrays pequenos (cabem na L2 de 40 MiB) e INNER
 * repetições dentro do kernel: uma passagem de 12 MiB demora ~5 us, pouco mais
 * do que lançar um kernel, por isso repetimos lá dentro.
 * ld/st .cg = "cache global": usa só a L2, salta a L1 de cada SM, para medir a
 * L2 e não a L1. São asm volatile: o compilador não pode juntar nem apagar
 * repetições. Contam-se 12 B por elemento.
 * Versão 1 (job 2269989) deslocava os índices a cada repetição; sem
 * sincronização entre blocos, um bloco adiantado relia dados que outro tinha
 * acabado de trazer, e a 96 MiB deu 2423 GB/s, acima do máximo da HBM (1555):
 * medição errada. Agora cada thread trata sempre os mesmos elementos, e os
 * tamanhos de 384 e 1536 MiB servem de controlo (têm de dar <= 1555). */
/* ld/st ".cg" em PTX (o mesmo que __ldcg/__stcg do CUDA, escrito à mão para
 * não depender da versão dos headers) */
__device__ __forceinline__ float ldcg(const float *p)
{ float v; asm volatile("ld.global.cg.f32 %0, [%1];" : "=f"(v) : "l"(p)); return v; }
__device__ __forceinline__ void stcg(float *p, float v)
{ asm volatile("st.global.cg.f32 [%0], %1;" :: "l"(p), "f"(v) : "memory"); }

__global__ void k_triad_l2(float *a, const float *b, const float *c, float s, size_t n, int inner)
{
    size_t i0 = blockIdx.x * (size_t)blockDim.x + threadIdx.x, G = (size_t)gridDim.x * blockDim.x;
    for (int r = 0; r < inner; r++)
        for (size_t i = i0; i < n; i += G)
            stcg(&a[i], ldcg(&b[i]) + s * ldcg(&c[i]));
}

/* valores diferentes de zero e variados (não deixa a GPU tirar partido de
 * dados todos iguais) */
__global__ void k_init(float *a, float *b, float *c, size_t n)
{
    for (size_t i = blockIdx.x * (size_t)blockDim.x + threadIdx.x; i < n; i += (size_t)gridDim.x * blockDim.x) {
        unsigned h = (unsigned)i * 2654435761u;
        a[i] = 0.0f; b[i] = 1.0f + (h >> 8) * 1e-7f; c[i] = 2.0f - (h >> 9) * 1e-7f;
    }
}

/* ---------------- latência ---------------- */
__global__ void k_chase(const unsigned *next, long steps, unsigned *out)
{
    unsigned p = 0;
    for (long i = 0; i < steps; i++) p = next[p];
    out[0] = p;                              /* usa o resultado: o ciclo não pode ser apagado */
}

/* relógio de parede em segundos (para cruzar com o registo de clock do nvidia-smi) */
static double wall_s() { struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts); return ts.tv_sec + ts.tv_nsec * 1e-9; }

static float time_ms(cudaEvent_t t0, cudaEvent_t t1) { float ms; CK(cudaEventElapsedTime(&ms, t0, t1)); return ms; }

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "uso: %s peak|triad|l2|lat [reps] [quick]\n", argv[0]); return 1; }
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
    } else if (!strcmp(mode, "l2")) {
        /* Varrimento do tamanho TOTAL (3 arrays): 3 a 96 MiB, mais 384 e 1536
         * MiB como controlo (HBM). A L2 tem 40 MiB em 2 metades de 20 MiB:
         * espera-se um patamar alto até ~20 MiB e uma queda depois. */
        const double mib[] = {3, 6, 12, 18, 24, 30, 36, 48, 96, 384, 1536};
        int threads = 256, blocks = p.multiProcessorCount * 8;      /* 2048 threads por SM */
        /* Aquecimento (versão 3): a GPU arranca a 1095 MHz e só sobe para
         * 1410 MHz depois de algum tempo em carga. Na versão 2 o salto aos
         * 24 MiB era o clock a subir a meio do varrimento. Corremos ~3 s de
         * Triad antes de medir, para todos os tamanhos verem o mesmo clock. */
        {
            size_t n = (size_t)(12.0 * 1048576.0 / 12.0);
            float *a, *b, *c;
            CK(cudaMalloc(&a, n * 4)); CK(cudaMalloc(&b, n * 4)); CK(cudaMalloc(&c, n * 4));
            k_init<<<p.multiProcessorCount * 8, 256>>>(a, b, c, n);
            double t_end = wall_s() + (quick ? 1.0 : 3.0);
            while (wall_s() < t_end) {
                k_triad_l2<<<blocks, threads>>>(a, b, c, 3.0f, n, 200);
                CK(cudaDeviceSynchronize());
            }
            CK(cudaGetLastError());
            CK(cudaFree(a)); CK(cudaFree(b)); CK(cudaFree(c));
        }
        printf("CSV,mode,total_MiB,rep,inner,ms,GBps,t_unix\n");
        for (double m : mib) {
            size_t n = (size_t)(m * 1048576.0 / 12.0);
            /* ~24 GB movidos por chamada (~10 ms), no máximo 1000 repetições */
            int inner = (int)(24000.0 / m); if (inner > 1000) inner = 1000; if (inner < 10) inner = 10;
            if (quick) inner = inner / 20 > 2 ? inner / 20 : 2;
            float *a, *b, *c;
            CK(cudaMalloc(&a, n * 4)); CK(cudaMalloc(&b, n * 4)); CK(cudaMalloc(&c, n * 4));
            k_init<<<p.multiProcessorCount * 8, 256>>>(a, b, c, n);
            CK(cudaDeviceSynchronize()); CK(cudaGetLastError());
            for (int r = 0; r <= reps; r++) {                  /* r=0 = aquecimento */
                CK(cudaEventRecord(t0));
                k_triad_l2<<<blocks, threads>>>(a, b, c, 3.0f, n, inner);
                CK(cudaEventRecord(t1)); CK(cudaEventSynchronize(t1)); CK(cudaGetLastError());
                double ms = time_ms(t0, t1);
                printf("CSV,l2,%.0f,%d,%d,%.3f,%.1f,%.3f\n", m, r, inner, ms, 12.0 * n * inner / ms / 1e6, wall_s());
            }
            CK(cudaFree(a)); CK(cudaFree(b)); CK(cudaFree(c));
        }
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

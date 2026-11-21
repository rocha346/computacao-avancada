/*
 * ACA WA2 - Task 1.1/1.2 - Largura de banda das CACHES com o kernel Triad.
 * (complementa o STREAM, que só usamos para a RAM - ver decisão sobre STREAM)
 *
 * Problema do STREAM nas caches: arrays que cabem na L1 (poucos KiB) são
 * percorridos em microssegundos, e o STREAM cronometra CADA passagem com um
 * relógio de ~1 us de resolução -> medição sem sentido.
 * Solução: cada thread tem os SEUS arrays a, b, c (alocados e inicializados
 * por ela -> ficam na sua memória/cache local, "first touch") e repete o
 * Triad   a[i] = b[i] + s * c[i]   R vezes dentro de UMA medição de tempo.
 *
 * Bytes contados por elemento: 3 x 4 B (lê b, lê c, escreve a) = 12 B, como
 * o STREAM (não conta o write-allocate; ver D06).
 *
 * Uso: OMP_NUM_THREADS=T ./triad <KiB por thread (os 3 arrays juntos)> [seg]
 * Ex.: AMD L1 (32 KiB/core): ./triad 16      A64FX L1 (64 KiB): ./triad 32
 *
 * NOTA: as strings do código (printf) são só ASCII. No Deucalion o gcc gera a
 *       diretiva .base64 para strings com acentos e o assembler instalado não a
 *       conhece (erro 'unknown pseudo-op: .base64'). Comentários podem ter acentos.
 */
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "uso: %s KiB_por_thread [segundos]\n", argv[0]); return 1; }
    double kib = atof(argv[1]);
    double target = argc > 2 ? atof(argv[2]) : 1.0;     /* duração aproximada da medição */
    long n = (long)(kib * 1024 / (3 * sizeof(float)));  /* elementos por array */
    n = (n / 64) * 64; if (n < 64) n = 64;
    int T = omp_get_max_threads();
    long reps = 1;
    double t = 0;

    #pragma omp parallel
    {
        float *a = NULL, *b = NULL, *c = NULL;
        if (posix_memalign((void **)&a, 256, n * sizeof(float)) ||
            posix_memalign((void **)&b, 256, n * sizeof(float)) ||
            posix_memalign((void **)&c, 256, n * sizeof(float))) { perror("alloc"); exit(1); }
        for (long i = 0; i < n; i++) { a[i] = 0; b[i] = 1; c[i] = 2; }   /* first touch */
        const float s = 3.0f;

        /* calibração: aumenta R até a medição durar >= target/10 */
        for (;;) {
            #pragma omp barrier
            double t0 = omp_get_wtime();
            for (long r = 0; r < reps; r++) {
                #pragma omp simd
                for (long i = 0; i < n; i++) a[i] = b[i] + s * c[i];
                __asm__ volatile("" ::: "memory");            /* não fundir repetições */
            }
            #pragma omp barrier
            #pragma omp master
            t = omp_get_wtime() - t0;
            #pragma omp barrier
            if (t >= target / 10) break;
            #pragma omp barrier
            #pragma omp master
            reps *= 2;
            #pragma omp barrier
        }
        /* medição a sério */
        long R = (long)(reps * target / t) + 1;
        #pragma omp barrier
        double t0 = omp_get_wtime();
        for (long r = 0; r < R; r++) {
            #pragma omp simd
            for (long i = 0; i < n; i++) a[i] = b[i] + s * c[i];
            __asm__ volatile("" ::: "memory");
        }
        #pragma omp barrier
        #pragma omp master
        {
            t = omp_get_wtime() - t0;
            double bytes = 3.0 * sizeof(float) * n * R * T;
            printf("CSV,threads,KiB_per_thread,reps,seconds,GBps\n");
            printf("CSV,%d,%.1f,%ld,%.4f,%.1f\n", T, kib, R, t, bytes / t / 1e9);
        }
        if (a[n / 2] < 0) printf("impossivel\n");
        free(a); free(b); free(c);
    }
    return 0;
}

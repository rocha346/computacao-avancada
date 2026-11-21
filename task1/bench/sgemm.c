/*
 * ACA WA2 - Task 1.2 - Validação do pico FP32 com SGEMM de uma biblioteca (D05).
 *
 * C = A x B (matrizes n x n, float). Faz 2 n³ FLOPs. Uma SGEMM bem otimizada
 * (OpenBLAS no AMD, Fujitsu SSL2 no A64FX) reutiliza cada valor muitas vezes
 * em cache/registos, por isso é limitada pelo CÁLCULO e chega perto do pico.
 * Comparamos o resultado com o nosso microbenchmark (peak.c):
 *   - se SGEMM ~ peak fma  -> o pico medido é credível;
 *   - a diferença mostra o que custa ter dados "reais" (loads, stores).
 * Usa a interface Fortran sgemm_, que existe nas duas bibliotecas.
 *
 * x86: gcc -O2 -fopenmp sgemm.c -lopenblas -o sgemm
 * ARM: fcc -Kfast,openmp sgemm.c -SSL2BLAMP -o sgemm
 * Uso: ./sgemm [n] [repeticoes]
 *
 * NOTA: as strings do código (printf) são só ASCII. No Deucalion o gcc gera a
 *       diretiva .base64 para strings com acentos e o assembler instalado não a
 *       conhece (erro 'unknown pseudo-op: .base64'). Comentários podem ter acentos.
 */
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

void sgemm_(const char *ta, const char *tb, const int *m, const int *n, const int *k,
            const float *alpha, const float *A, const int *lda, const float *B, const int *ldb,
            const float *beta, float *C, const int *ldc);

int main(int argc, char **argv)
{
    int n = argc > 1 ? atoi(argv[1]) : 8192;
    int reps = argc > 2 ? atoi(argv[2]) : 5;
    float *A = malloc((size_t)n * n * sizeof(float));
    float *B = malloc((size_t)n * n * sizeof(float));
    float *C = malloc((size_t)n * n * sizeof(float));
    if (!A || !B || !C) {       /* o 1º run no A64FX deu SIGSEGV aqui: verificar a alocação */
        fprintf(stderr, "malloc falhou para n=%d (%.2f GiB por matriz)\n", n, (double)n * n * 4 / 1073741824.0);
        return 1;
    }
    fprintf(stderr, "n=%d, %.2f GiB por matriz, %d threads\n", n, (double)n * n * 4 / 1073741824.0, omp_get_max_threads());
    #pragma omp parallel for
    for (long i = 0; i < (long)n * n; i++) { A[i] = 1.0f / (i % 97 + 1); B[i] = 0.5f; C[i] = 0; }
    const float one = 1.0f, zero = 0.0f;

    sgemm_("N", "N", &n, &n, &n, &one, A, &n, B, &n, &zero, C, &n);    /* aquecimento */
    printf("CSV,n,rep,seconds,GFLOPs\n");
    for (int r = 0; r < reps; r++) {
        double t0 = omp_get_wtime();
        sgemm_("N", "N", &n, &n, &n, &one, A, &n, B, &n, &zero, C, &n);
        double t = omp_get_wtime() - t0;
        printf("CSV,%d,%d,%.4f,%.1f\n", n, r, t, 2.0 * n * n * (double)n / t / 1e9);
    }
    if (C[0] < -1) printf("impossivel\n");
    free(A); free(B); free(C);
    return 0;
}

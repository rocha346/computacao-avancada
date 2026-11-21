/*
 * ACA WA2 - Task 1.2/1.3 - Microbenchmark de pico FP32 e dos tetos (D05, D16).
 *
 * Cada thread executa um ciclo com NACC acumuladores INDEPENDENTES:
 *      acc[k] = acc[k] * a + b      (modo fma)
 * Porquê vários acumuladores? Uma FMA demora L ciclos (latência) mas o core
 * pode começar P FMAs por ciclo (P = nº de pipelines). Para nunca parar,
 * precisa de L x P operações independentes "em voo":
 *      AMD Zen 2 : L = 5, P = 2  -> >= 10 acumuladores (usamos 12)
 *      A64FX     : L = 9, P = 2  -> >= 18 acumuladores (usamos 24)
 * (o modo "lat" usa 1 só acumulador e mede a latência: é o pior caso.)
 *
 * Modos (cada um corresponde a um teto da 1.3, D16):
 *   fma     SIMD + FMA                      -> C5 (pico)
 *   muladd  SIMD, mul e add separados       -> C4 (SIMD sem FMA)
 *   add     SIMD, só somas
 *   div     SIMD, só divisões               -> C1 (teto das divisões)
 *   sfma    escalar + FMA (1 float por op)  -> C2/C3 (sem SIMD)
 *   sdiv    escalar, só divisões
 *   lat     SIMD FMA com 1 acumulador       -> latência da FMA
 * FLOPs contados: fma = 2 por lane; mul, add, div = 1 por lane.
 *
 * Compilar (ver build.sh):
 *   x86 : gcc -O2 -mavx2 -mfma -fopenmp peak.c -o peak
 *   ARM : gcc -O2 -march=armv8.2-a+sve -fopenmp peak.c -o peak
 * Correr: OMP_NUM_THREADS=T ./peak <modo> [iteracoes]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <omp.h>

#if defined(__AVX2__) && defined(__FMA__)
  #include <immintrin.h>
  #define ARCH   "x86-AVX2"
  #define NACC   12
  typedef __m256 vf;
  #define LANES  8
  #define SET1(x)      _mm256_set1_ps(x)
  #define FMA(c,a,b)   _mm256_fmadd_ps(c,a,b)       /* c*a+b */
  #define MUL(x,y)     _mm256_mul_ps(x,y)
  #define ADD(x,y)     _mm256_add_ps(x,y)
  #define DIV(x,y)     _mm256_div_ps(x,y)
  static float hsum(vf v) { float t[8]; _mm256_storeu_ps(t, v); float s = 0; for (int i = 0; i < 8; i++) s += t[i]; return s; }
#elif defined(__ARM_FEATURE_SVE)
  #include <arm_sve.h>
  #define ARCH   "aarch64-SVE"
  #define NACC   24
  typedef svfloat32_t vf;
  #define LANES  ((int) svcntw())                    /* 16 no A64FX (512 bits) */
  #define PG     svptrue_b32()
  #define SET1(x)      svdup_f32(x)
  #define FMA(c,a,b)   svmad_f32_x(PG,c,a,b)         /* c*a+b */
  #define MUL(x,y)     svmul_f32_x(PG,x,y)
  #define ADD(x,y)     svadd_f32_x(PG,x,y)
  #define DIV(x,y)     svdiv_f32_x(PG,x,y)
  static float hsum(vf v) { return svaddv_f32(PG, v); }
#else
  #error "Compilar com AVX2+FMA (x86) ou SVE (ARM)"
#endif

/* Os tipos SVE não podem estar em arrays, por isso os acumuladores são
   variáveis separadas geradas por macros (A0..A23). */
#define DECL(i)   vf A##i = SET1(1.0f + (i) * 1e-3f);
#define SUMV(i)   s += hsum(A##i);
#if NACC == 12
  #define ALL(X) X(0) X(1) X(2) X(3) X(4) X(5) X(6) X(7) X(8) X(9) X(10) X(11)
#else
  #define ALL(X) X(0) X(1) X(2) X(3) X(4) X(5) X(6) X(7) X(8) X(9) X(10) X(11) \
                 X(12) X(13) X(14) X(15) X(16) X(17) X(18) X(19) X(20) X(21) X(22) X(23)
#endif
/* Impede o compilador de juntar/eliminar operações entre iterações:
   o asm vazio "diz" que o registo pode ter mudado. */
#if defined(__AVX2__)
  #define REG "+x"
#else
  #define REG "+w"
#endif
#define KEEP(i) __asm__ volatile("" : REG(A##i));

#define OP_FMA(i)    A##i = FMA(A##i, va, vb);
#define OP_MULADD(i) A##i = (((i) & 1) ? MUL(A##i, va) : ADD(A##i, vb));
#define OP_ADD(i)    A##i = ADD(A##i, vb);
#define OP_DIV(i)    A##i = DIV(A##i, va);

/* Escalar: as mesmas operações, 1 float de cada vez */
#define SDECL(i)  float S##i = 1.0f + (i) * 1e-3f;
#define SSUM(i)   s += S##i;
#define SKEEP(i)  __asm__ volatile("" : REG(S##i));
#define SOP_FMA(i) S##i = __builtin_fmaf(S##i, a, b);
#define SOP_DIV(i) S##i = S##i / a;

/* Corre o ciclo de 'iters' iterações numa thread; devolve FLOPs feitos */
static double kernel(const char *mode, long iters, double *sink)
{
    const float a = 0.9999999f, b = 1e-7f;      /* valores estáveis: sem overflow nem denormais */
    vf va = SET1(a), vb = SET1(b);
    double s = 0, flops;
    if (!strcmp(mode, "fma") || !strcmp(mode, "muladd") || !strcmp(mode, "add") || !strcmp(mode, "div")) {
        ALL(DECL)
        if (!strcmp(mode, "fma"))         for (long it = 0; it < iters; it++) { ALL(OP_FMA)    ALL(KEEP) }
        else if (!strcmp(mode, "muladd")) for (long it = 0; it < iters; it++) { ALL(OP_MULADD) ALL(KEEP) }
        else if (!strcmp(mode, "add"))    for (long it = 0; it < iters; it++) { ALL(OP_ADD)    ALL(KEEP) }
        else                              for (long it = 0; it < iters; it++) { ALL(OP_DIV)    ALL(KEEP) }
        ALL(SUMV)
        flops = (double) iters * NACC * LANES * (!strcmp(mode, "fma") ? 2 : 1);
    } else if (!strcmp(mode, "lat")) {
        vf x = SET1(1.0f);
        for (long it = 0; it < iters; it++) { x = FMA(x, va, vb); __asm__ volatile("" : REG(x)); }
        s = hsum(x);
        flops = (double) iters * LANES * 2;
    } else if (!strcmp(mode, "sfma") || !strcmp(mode, "sdiv")) {
        ALL(SDECL)
        if (!strcmp(mode, "sfma")) for (long it = 0; it < iters; it++) { ALL(SOP_FMA) ALL(SKEEP) }
        else                       for (long it = 0; it < iters; it++) { ALL(SOP_DIV) ALL(SKEEP) }
        ALL(SSUM)
        flops = (double) iters * NACC * (!strcmp(mode, "sfma") ? 2 : 1);
    } else {
        fprintf(stderr, "modo desconhecido: %s\n", mode); exit(1);
    }
    *sink += s;
    return flops;
}

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "uso: %s fma|muladd|add|div|sfma|sdiv|lat [iters]\n", argv[0]); return 1; }
    const char *mode = argv[1];
    long iters = argc > 2 ? atol(argv[2]) : 100000000L;
    int T = omp_get_max_threads();
    double sink = 0, flops_total = 0;

    /* aquecimento curto (sobe a frequência, carrega o código) */
    #pragma omp parallel reduction(+:sink)
    { double d = 0; kernel(mode, iters / 20, &d); sink += d; }

    double t0 = omp_get_wtime();
    #pragma omp parallel reduction(+:flops_total, sink)
    { double d = 0; flops_total += kernel(mode, iters, &d); sink += d; }
    double t = omp_get_wtime() - t0;

    printf("CSV,arch,mode,threads,nacc,lanes,iters,seconds,GFLOPs,checksum\n");
    printf("CSV,%s,%s,%d,%d,%d,%ld,%.4f,%.2f,%g\n", ARCH, mode, T, NACC, LANES, iters, t, flops_total / t / 1e9, sink);
    return 0;
}

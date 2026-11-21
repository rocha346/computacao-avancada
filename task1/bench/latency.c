/*
 * ACA WA2 - Task 1.1 - Latência da memória por "pointer chasing" (D07).
 *
 * Ideia: criamos uma lista ligada circular dentro de um bloco de memória de
 * tamanho S, com os nós por ORDEM ALEATÓRIA, e percorremo-la:
 *       p = *p;   p = *p;   p = *p; ...
 * Cada leitura precisa do endereço devolvido pela anterior, por isso o
 * processador não pode sobrepor acessos nem o prefetcher adivinhar o
 * próximo. O tempo por passo é a LATÊNCIA do nível onde o bloco cabe.
 * Fazendo S crescer (4 KiB ... 2 GiB) vemos "degraus": L1 -> L2 -> L3 -> RAM.
 *
 * Detalhes importantes:
 *  - cada nó ocupa uma linha de cache inteira (STRIDE = 256 B, a maior linha:
 *    A64FX); assim dois nós nunca partilham a mesma linha, nas duas máquinas.
 *  - ordem aleatória (Sattolo) para enganar o prefetcher.
 *  - páginas: com S grande o TLB também falha; isso mede-se junto. Para ver a
 *    diferença, correr também com huge pages (ver latency.sh).
 *  - 1 só thread, fixa num core (taskset/numactl no script).
 *
 * Compilar:  gcc -O2 -o latency latency.c          (x86 e ARM)
 * Correr:    ./latency [S_min_KiB] [S_max_MiB]
 * Saída CSV: size_bytes,ns_per_access
 *
 * NOTA: as strings do código (printf) são só ASCII. No Deucalion o gcc gera a
 *       diretiva .base64 para strings com acentos e o assembler instalado não a
 *       conhece (erro 'unknown pseudo-op: .base64'). Comentários podem ter acentos.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

#define STRIDE 256                 /* bytes entre nós = 1 linha do A64FX */

static double now(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + 1e-9 * t.tv_nsec;
}

static uint64_t rng = 88172645463325252ULL;      /* xorshift: rápido e reprodutível */
static uint64_t rnd(void) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng; }

int main(int argc, char **argv)
{
    size_t min_b = (argc > 1 ? atol(argv[1]) : 4) * 1024UL;
    size_t max_b = (argc > 2 ? atol(argv[2]) : 2048) * 1024UL * 1024UL;

    char *buf;
    if (posix_memalign((void **)&buf, 2 * 1024 * 1024, max_b)) { perror("alloc"); return 1; }
    size_t *order = malloc((max_b / STRIDE) * sizeof(size_t));

    printf("CSV,size_bytes,ns_per_access\n");
    /* 4 pontos por potência de 2 para a curva ter resolução */
    for (double s = min_b; s <= max_b; s *= 1.189207115) {   /* 2^(1/4) */
        size_t n = (size_t)s / STRIDE;
        if (n < 2) continue;

        /* permutação cíclica aleatória (algoritmo de Sattolo): um só ciclo
           que passa por todos os n nós */
        for (size_t i = 0; i < n; i++) order[i] = i;
        for (size_t i = n - 1; i > 0; i--) {
            size_t j = rnd() % i;
            size_t t = order[i]; order[i] = order[j]; order[j] = t;
        }
        for (size_t i = 0; i < n; i++)
            *(void **)(buf + order[i] * STRIDE) = buf + order[(i + 1) % n] * STRIDE;

        /* nº de passos: pelo menos 10 voltas e ~0.2 s de medição */
        size_t steps = n * 10 < 20000000 ? 20000000 : n * 10;
        void **p = (void **)(buf + order[0] * STRIDE);
        for (size_t i = 0; i < n; i++) p = (void **)*p;          /* aquecer */

        double t0 = now();
        for (size_t i = 0; i < steps; i += 8) {                  /* desenrolado */
            p = (void **)*p; p = (void **)*p; p = (void **)*p; p = (void **)*p;
            p = (void **)*p; p = (void **)*p; p = (void **)*p; p = (void **)*p;
        }
        double t1 = now();
        /* usar p para o compilador não apagar o ciclo */
        if (p == NULL) printf("impossivel\n");
        printf("CSV,%zu,%.2f\n", n * STRIDE, (t1 - t0) * 1e9 / steps);
        fflush(stdout);
    }
    free(order); free(buf);
    return 0;
}

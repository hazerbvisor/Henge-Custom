/*
  vmbench: what the virtual Mac's CPU does per second, for A/B of the engine's
  Performance settings (Settings > Performance: Superblocks, Grouped memory
  checks, Faster loop exits, Mac refresh rate). Run it inside the Mac, through
  Henge's JIT, not on the Mac that hosts Henge: tests/test_bench.c is that side.

  Build on the host:  make vmbench          -> build/vmbench  (arm64, macOS 12+)

  Put it where the Mac can see it (the shared folder shows up as ~/Henge in the
  guest's home folder), then in the Mac's Terminal:

      ~/Henge/vmbench                    every kernel, best of 5
      ~/Henge/vmbench --save a.txt       save the numbers
      ~/Henge/vmbench --baseline a.txt   compare with them after toggling a setting
      ~/Henge/vmbench --runs 9           more repeats (best of N is reported)

  Kernels, each a shape the translator treats differently:

      calls      recursive fib(20): call frames, stack accesses in groups
      stackmem   read-modify-write of an 8 KB stack buffer, 64 passes
      chase      dependent loads across a 1 MB table (256 pages, so TLB hits)
      loop       a tight arithmetic loop with one back branch
      dispatch   a switch interpreter loop (4 opcodes, 4096 steps)
      sieve      Eratosthenes to 256 KB: memory and nested loops together

  Each kernel is calibrated at start-up to about 0.15 s of work, warmed up, then
  timed `--runs` times and its best taken. Times are wall-clock inside the Mac,
  so they include everything the Mac was doing; toggle one setting, quit Henge
  and start the Mac again, run it again, and compare the two.

  The checksum at the end comes from a fixed one-unit run of each kernel, so it
  is the same for every run and every setting (the calibrated reps are not part
  of it): a different one means the translation produced the wrong answer, not a
  faster one, and --baseline names the kernel whose result changed.
*/
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

enum { TARGET_MS = 150, MAX_REPS = 1 << 22, MAX_RUNS = 9 };

/* Recursion deep enough to build real frames. The depths are volatile and read
   inside the loop, so the compiler cannot hoist the whole call tree out of it
   and leave a loop of adds. */
static volatile uint64_t depths[2] = {20, 21};

__attribute__((noinline)) static uint64_t fib(uint64_t n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

static uint64_t k_calls(int reps) {
    uint64_t sum = 0;
    for (int r = 0; r < reps; r++) sum += fib(depths[r & 1]);
    return sum;
}

/* Volatile, so every access stays a scalar load and store the way compiled code
   reaches a stack buffer (which is what grouped memory checks are for). */
static uint64_t k_stackmem(int reps) {
    uint64_t buf[1024], sum = 0;
    volatile uint64_t *p = buf;
    memset(buf, 0, sizeof buf);
    for (int r = 0; r < reps; r++)
        for (int pass = 0; pass < 64; pass++)
            for (int i = 0; i < 1024; i++) {
                uint64_t v = p[i];
                sum += v;
                p[i] = v ^ (uint64_t)(i + pass);
            }
    return sum;
}

/* 1 MB, one uint32 per 8 bytes read, walked with an odd stride so every slot and
   so every page is touched and each load feeds the next index. */
enum { CHASE_SLOTS = 1 << 17, CHASE_MASK = CHASE_SLOTS - 1 };
static uint32_t chase[CHASE_SLOTS];

static void chase_init(void) {
    for (uint32_t i = 0; i < CHASE_SLOTS; i++) chase[i] = (i + 1) & CHASE_MASK;
}

static uint64_t k_chase(int reps) {
    uint32_t i = 0;
    uint64_t sum = 0;
    for (int r = 0; r < reps; r++)
        for (int n = 0; n < (1 << 16); n++) {
            i = chase[(i + 64) & CHASE_MASK];
            sum += i;
        }
    return sum;
}

static uint64_t k_loop(int reps) {
    uint64_t acc = 0;
    for (int r = 0; r < reps; r++) {
        uint32_t x = (uint32_t)r;
        for (uint32_t i = 0; i < (1u << 16); i++) {
            x = x * 7 + 13;
            acc += x >> 11;
        }
    }
    return acc;
}

enum { CODE_LEN = 4096 };
static uint8_t code[CODE_LEN];

static void code_init(void) {
    uint32_t s = 12345;
    for (int i = 0; i < CODE_LEN; i++) {
        s = s * 1103515245u + 12345u;
        code[i] = (uint8_t)((s >> 16) & 3);
    }
}

static uint64_t k_dispatch(int reps) {
    uint64_t a = 1, b = 2, c = 3;
    for (int r = 0; r < reps; r++)
        for (int pc = 0; pc < CODE_LEN; pc++)
            switch (code[pc]) {
            case 0: a += b; break;
            case 1: b ^= c; break;
            case 2: c += a >> 1; break;
            default: a = a * 5 + 1; break;
            }
    return a ^ (b << 1) ^ (c << 2);
}

enum { SIEVE_BYTES = 1 << 18 };
static uint8_t flags[SIEVE_BYTES];

static uint64_t k_sieve(int reps) {
    uint64_t primes = 0;
    for (int r = 0; r < reps; r++) {
        memset(flags, 1, sizeof flags);
        for (uint32_t p = 2; p * p < SIEVE_BYTES; p++)
            if (flags[p])
                for (uint32_t m = p * p; m < SIEVE_BYTES; m += p) flags[m] = 0;
        for (uint32_t i = 2; i < SIEVE_BYTES; i++) primes += flags[i] ? 1 : 0;
    }
    return primes;
}

typedef struct {
    const char *name;
    uint64_t (*run)(int reps);
    int reps;
    double ms;
    uint64_t verify;
} Kernel;

static Kernel kernels[] = {
    {"calls", k_calls, 0, 0, 0}, {"stackmem", k_stackmem, 0, 0, 0}, {"chase", k_chase, 0, 0, 0},
    {"loop", k_loop, 0, 0, 0},   {"dispatch", k_dispatch, 0, 0, 0}, {"sieve", k_sieve, 0, 0, 0},
};

static double now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1e3 + (double)t.tv_nsec / 1e6;
}

static double measure(Kernel *k, int reps, uint64_t *sum) {
    double t0 = now_ms();
    uint64_t v = k->run(reps);
    double t1 = now_ms();
    if (sum) *sum = v;
    return t1 - t0;
}

/* Grow the reps until one run is about TARGET_MS long, then take the best of
   `runs` timed runs after a warm-up at that size (the first run pays for
   translation, as in tests/test_bench.c). */
static void run_kernel(Kernel *k, int runs) {
    double t = measure(k, 1, NULL);
    int reps = 1;
    while (t < TARGET_MS && reps < MAX_REPS) {
        reps *= 2;
        t = measure(k, reps, NULL);
    }
    k->reps = reps;
    measure(k, reps, NULL); /* warm-up: the translated code and its chains */
    k->ms = 1e9;
    for (int i = 0; i < runs; i++) {
        double ms = measure(k, reps, NULL);
        if (ms < k->ms) k->ms = ms;
    }
    k->verify = k->run(1); /* one fixed unit: a result that reps cannot change */
}

static double us_per_rep(const Kernel *k) { return k->ms * 1e3 / k->reps; }

static void usage(const char *argv0) {
    fprintf(stderr,
            "usage: %s [--runs N] [--save FILE] [--baseline FILE]\n"
            "  --runs N        timed runs per kernel (default 5, best of N is reported)\n"
            "  --save FILE     write the numbers to FILE\n"
            "  --baseline FILE compare against a file written by --save\n",
            argv0);
}

typedef struct {
    char name[32];
    int reps;
    double ms;
    unsigned long long verify;
} Saved;

static int read_saved(const char *path, Saved *out, int max) {
    FILE *f = fopen(path, "r");
    if (!f) {
        fprintf(stderr, "vmbench: cannot read %s\n", path);
        return -1;
    }
    char line[256];
    int n = 0;
    while (n < max && fgets(line, sizeof line, f)) {
        if (line[0] == '#' || line[0] == '\n') continue;
        Saved s = {0};
        if (sscanf(line, "%31s %d %lf %llx", s.name, &s.reps, &s.ms, &s.verify) == 4 && s.reps > 0) out[n++] = s;
    }
    fclose(f);
    return n;
}

static void compare(const char *path) {
    Saved base[16];
    int nbase = read_saved(path, base, 16);
    if (nbase <= 0) return;
    printf("\nvs %s (microseconds per unit of work; negative is faster now)\n", path);
    printf("%-10s %12s %12s %10s\n", "kernel", "baseline", "now", "change");
    double logsum = 0;
    int n = 0, wrong = 0;
    for (size_t i = 0; i < sizeof kernels / sizeof kernels[0]; i++) {
        const Kernel *k = &kernels[i];
        const Saved *b = NULL;
        for (int j = 0; j < nbase; j++)
            if (!strcmp(base[j].name, k->name)) b = &base[j];
        if (!b) {
            printf("%-10s %12s %12.1f %10s\n", k->name, "(not in file)", us_per_rep(k), "-");
            continue;
        }
        if (b->verify != k->verify) {
            printf("%-10s %12s %12s %10s  WRONG RESULT (baseline %llx, now %llx)\n", k->name, "", "", "", b->verify,
                   (unsigned long long)k->verify);
            wrong++;
            continue;
        }
        double was = b->ms * 1e3 / b->reps, now = us_per_rep(k);
        printf("%-10s %12.1f %12.1f %+9.1f%%\n", k->name, was, now, (now - was) / was * 100);
        logsum += log(now / was);
        n++;
    }
    if (n) printf("%-10s %12s %12s %+9.1f%%\n", "overall", "", "", (exp(logsum / n) - 1) * 100);
    if (wrong) printf("%d kernel(s) gave a different answer: that is a translation bug, not a speed difference\n", wrong);
}

int main(int argc, char **argv) {
    const char *save = NULL, *baseline = NULL;
    int runs = 5;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--runs") && i + 1 < argc) runs = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--save") && i + 1 < argc) save = argv[++i];
        else if (!strcmp(argv[i], "--baseline") && i + 1 < argc) baseline = argv[++i];
        else if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
            usage(argv[0]);
            return 0;
        } else {
            fprintf(stderr, "vmbench: unknown argument %s (try --help)\n", argv[i]);
            return 2;
        }
    }
    if (runs < 1) runs = 1;
    if (runs > MAX_RUNS) runs = MAX_RUNS;
    setvbuf(stdout, NULL, _IONBF, 0);

    chase_init();
    code_init();

    size_t nk = sizeof kernels / sizeof kernels[0];
    printf("vmbench: %zu kernels, best of %d, about %d ms each\n\n", nk, runs, TARGET_MS);
    printf("%-10s %8s %10s %12s\n", "kernel", "reps", "ms", "us/rep");
    for (size_t i = 0; i < nk; i++) {
        run_kernel(&kernels[i], runs);
        printf("%-10s %8d %10.2f %12.1f\n", kernels[i].name, kernels[i].reps, kernels[i].ms, us_per_rep(&kernels[i]));
    }
    uint64_t sum = 0;
    for (size_t i = 0; i < nk; i++) sum = sum * 1000003 + kernels[i].verify;
    printf("\nchecksum %016llx\n", (unsigned long long)sum);

    if (save) {
        FILE *f = fopen(save, "w");
        if (!f) {
            fprintf(stderr, "vmbench: cannot write %s\n", save);
            return 1;
        }
        fprintf(f, "# vmbench: name reps ms (written by vmbench --save)\n");
        for (size_t i = 0; i < nk; i++)
            fprintf(f, "%s %d %.3f %llx\n", kernels[i].name, kernels[i].reps, kernels[i].ms,
                    (unsigned long long)kernels[i].verify);
        fclose(f);
        printf("saved to %s\n", save);
    }
    if (baseline) compare(baseline);
    return 0;
}

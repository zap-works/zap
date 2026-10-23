// A homebrew written to compare the recompiler's run with an emulator's: it asks the kernel for
// no service, prints through svcOutputDebugString, and exercises integer and floating-point code,
// formatted output, threads with a mutex and a condition variable, and the counter.
#include <switch.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

void __appInit(void) {}
void __appExit(void) {}

static void say(const char *text) {
    svcOutputDebugString(text, strlen(text));
}

static Mutex lock;
static CondVar ready;
static int turns;

static void worker(void *arg) {
    int id = (int)(uintptr_t)arg;
    for (int k = 0; k < 3; k++) {
        mutexLock(&lock);
        turns += id;
        condvarWakeAll(&ready);
        mutexUnlock(&lock);
        svcSleepThread(1000000);
    }
}

int main(int argc, char **argv) {
    char line[128];
    say("hello from a homebrew\n");
    unsigned long long fib[2] = {0, 1};
    for (int i = 0; i < 90; i++) {
        unsigned long long next = fib[0] + fib[1];
        fib[0] = fib[1];
        fib[1] = next;
    }
    snprintf(line, sizeof line, "fib 91 = %llu\n", fib[1]);
    say(line);
    double x = 0.0;
    for (int i = 1; i <= 1000; i++) x += sin(i * 0.01) / i;
    snprintf(line, sizeof line, "sum = %.12f, sqrt 2 = %.15f\n", x, sqrt(2.0));
    say(line);
    float f = 1.0f;
    for (int i = 0; i < 20; i++) f = f * 1.5f - 0.25f;
    snprintf(line, sizeof line, "float %.6e\n", (double)f);
    say(line);
    mutexInit(&lock);
    condvarInit(&ready);
    Thread threads[2];
    for (int t = 0; t < 2; t++) {
        threadCreate(&threads[t], worker, (void *)(uintptr_t)(t + 1), NULL, 0x4000, 0x2C, -2);
        threadStart(&threads[t]);
    }
    mutexLock(&lock);
    while (turns < 9) condvarWait(&ready, &lock);
    mutexUnlock(&lock);
    for (int t = 0; t < 2; t++) {
        threadWaitForExit(&threads[t]);
        threadClose(&threads[t]);
    }
    snprintf(line, sizeof line, "turns %d\n", turns);
    say(line);
    u64 tick = armGetSystemTick();
    snprintf(line, sizeof line, "ticks moved %s\n", tick > 0 ? "yes" : "no");
    say(line);
    say("bye\n");
    return 0;
}

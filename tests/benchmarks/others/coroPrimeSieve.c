// coroPrimeSieve: the first n primes by a chain of threads joined by bounded channels
// (the programming-language-benchmarks suite's coro-prime-sieve): a generator sends 2, 3, 4...
// and each thread holds consecutive filters, a prime and its multiples out of what comes in;
// as many threads as processors less two, so a number meets the primes in order as in a thread per prime.
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <windows.h>
#else
#include <unistd.h>
#endif

#define CAPACITY 64

typedef struct {
    pthread_mutex_t lock;
    pthread_cond_t notEmpty, notFull;
    int *items;
    int capacity, head, count;
    bool closed;
} Channel;

static Channel *channelNew(int capacity) {
    Channel *c = calloc(1, sizeof(Channel));
    pthread_mutex_init(&c->lock, NULL);
    pthread_cond_init(&c->notEmpty, NULL);
    pthread_cond_init(&c->notFull, NULL);
    c->items = malloc(capacity * sizeof(int));
    c->capacity = capacity;
    return c;
}

static bool channelSend(Channel *c, int v) {
    pthread_mutex_lock(&c->lock);
    while (c->count == c->capacity && !c->closed) pthread_cond_wait(&c->notFull, &c->lock);
    if (c->closed) {
        pthread_mutex_unlock(&c->lock);
        return false;
    }
    c->items[(c->head + c->count++) % c->capacity] = v;
    pthread_cond_signal(&c->notEmpty);
    pthread_mutex_unlock(&c->lock);
    return true;
}

static bool channelReceive(Channel *c, int *v) {
    pthread_mutex_lock(&c->lock);
    while (c->count == 0 && !c->closed) pthread_cond_wait(&c->notEmpty, &c->lock);
    if (c->count == 0) {
        pthread_mutex_unlock(&c->lock);
        return false;
    }
    *v = c->items[c->head];
    c->head = (c->head + 1) % c->capacity;
    c->count--;
    pthread_cond_signal(&c->notFull);
    pthread_mutex_unlock(&c->lock);
    return true;
}

static void channelClose(Channel *c) {
    pthread_mutex_lock(&c->lock);
    c->closed = true;
    pthread_cond_broadcast(&c->notEmpty);
    pthread_cond_broadcast(&c->notFull);
    pthread_mutex_unlock(&c->lock);
}

typedef struct {
    Channel *in, *out, *found;
    int room;
    bool last;
} Filters;

static void *generate(void *arg) {
    Channel *out = arg;
    for (int n = 2; channelSend(out, n); n++) {}
    return NULL;
}

static void *filters(void *arg) {
    Filters *f = arg;
    int *primes = malloc(f->room * sizeof(int));
    int count = 0, v;
    while (channelReceive(f->in, &v)) {
        bool prime = true;
        for (int i = 0; i < count; i++)
            if (v % primes[i] == 0) {
                prime = false;
                break;
            }
        if (!prime) continue;
        if (count < f->room) {
            primes[count++] = v;
            channelSend(f->found, v);
            if (f->last && count == f->room) break;
        } else if (!channelSend(f->out, v)) {
            break;
        }
    }
    channelClose(f->in);
    channelClose(f->out);
    free(primes);
    return NULL;
}

static int processors(void) {
#ifdef _WIN32
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return (int)info.dwNumberOfProcessors;
#else
    return (int)sysconf(_SC_NPROCESSORS_ONLN);
#endif
}

int main(int argc, char **argv) {
#ifdef _WIN32
    _setmode(1, _O_BINARY); /* the runner compares bytes: no CRLF translation */
#endif
    int n = argc > 1 ? atoi(argv[1]) : 10;
    int tasks = processors() - 2;
    if (tasks > n) tasks = n;
    if (tasks < 1) tasks = 1;
    int share = (n + tasks - 1) / tasks;
    tasks = (n + share - 1) / share;
    pthread_t *threads = malloc((tasks + 1) * sizeof(pthread_t));
    Channel **channels = malloc((tasks + 1) * sizeof(Channel *));
    Filters *stages = malloc(tasks * sizeof(Filters));
    Channel *found = channelNew(n);
    channels[0] = channelNew(CAPACITY);
    pthread_create(&threads[0], NULL, generate, channels[0]);
    for (int k = 0; k < tasks; k++) {
        int room = n - k * share < share ? n - k * share : share;
        channels[k + 1] = channelNew(CAPACITY);
        stages[k] = (Filters){channels[k], channels[k + 1], found, room, k == tasks - 1};
        pthread_create(&threads[k + 1], NULL, filters, &stages[k]);
    }
    for (int i = 0; i < n; i++) {
        int p;
        channelReceive(found, &p);
        printf("%d\n", p);
    }
    for (int k = 0; k <= tasks; k++) pthread_join(threads[k], NULL);
    return 0;
}

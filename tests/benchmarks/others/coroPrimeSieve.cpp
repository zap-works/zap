// coroPrimeSieve: the first n primes by a chain of threads joined by bounded channels
// (the programming-language-benchmarks suite's coro-prime-sieve): a generator sends 2, 3, 4...
// and each thread holds consecutive filters, a prime and its multiples out of what comes in;
// as many threads as processors less two, so a number meets the primes in order as in a thread per prime.
#include <algorithm>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

constexpr int kCapacity = 64;

class Channel {
    std::mutex lock;
    std::condition_variable notEmpty, notFull;
    std::vector<int> items;
    int head = 0, count = 0;
    bool closed = false;

public:
    explicit Channel(int capacity) : items(capacity) {}

    bool send(int v) {
        std::unique_lock<std::mutex> l(lock);
        notFull.wait(l, [&] { return count < (int)items.size() || closed; });
        if (closed) return false;
        items[(head + count++) % items.size()] = v;
        notEmpty.notify_one();
        return true;
    }

    bool receive(int &v) {
        std::unique_lock<std::mutex> l(lock);
        notEmpty.wait(l, [&] { return count > 0 || closed; });
        if (count == 0) return false;
        v = items[head];
        head = (head + 1) % items.size();
        count--;
        notFull.notify_one();
        return true;
    }

    void close() {
        std::lock_guard<std::mutex> l(lock);
        closed = true;
        notEmpty.notify_all();
        notFull.notify_all();
    }
};

static void generate(Channel *out) {
    for (int n = 2; out->send(n); n++) {}
}

static void filters(Channel *in, Channel *out, Channel *found, int room, bool last) {
    std::vector<int> primes;
    primes.reserve(room);
    int v;
    while (in->receive(v)) {
        if (std::any_of(primes.begin(), primes.end(), [v](int p) { return v % p == 0; })) continue;
        if ((int)primes.size() < room) {
            primes.push_back(v);
            found->send(v);
            if (last && (int)primes.size() == room) break;
        } else if (!out->send(v)) {
            break;
        }
    }
    in->close();
    out->close();
}

int main(int argc, char **argv) {
#ifdef _WIN32
    _setmode(1, _O_BINARY); // the runner compares bytes: no CRLF translation
#endif
    int n = argc > 1 ? atoi(argv[1]) : 10;
    int tasks = std::min(std::max((int)std::thread::hardware_concurrency() - 2, 1), n);
    int share = (n + tasks - 1) / tasks;
    tasks = (n + share - 1) / share;
    Channel found(n);
    std::vector<std::unique_ptr<Channel>> channels;
    std::vector<std::thread> threads;
    channels.push_back(std::make_unique<Channel>(kCapacity));
    threads.emplace_back(generate, channels[0].get());
    for (int k = 0; k < tasks; k++) {
        channels.push_back(std::make_unique<Channel>(kCapacity));
        int room = std::min(share, n - k * share);
        threads.emplace_back(filters, channels[k].get(), channels[k + 1].get(), &found, room, k == tasks - 1);
    }
    for (int i = 0; i < n; i++) {
        int p;
        found.receive(p);
        printf("%d\n", p);
    }
    for (auto &t : threads) t.join();
    return 0;
}

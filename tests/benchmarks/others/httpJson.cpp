// httpJson: TechEmpower's plaintext and JSON tests in one run. An HTTP/1.1 server (Winsock or POSIX sockets, a thread per
// connection) answers 16 clients on the loopback, each with its own connection kept alive: every client
// writes its n requests in pipelined batches of 16 (a plaintext request, then a JSON one, alternating) and
// reads the responses; each JSON response is serialized anew. Prints the requests the clients made and the
// server served, the response bytes read, and the sum of the bodies' bytes.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string_view>
#include <thread>
#include <vector>
#ifdef _WIN32
#include <winsock2.h>
#include <fcntl.h>
#include <io.h>
typedef int SockLen;
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
typedef int SOCKET;
typedef socklen_t SockLen;
#define closesocket close
#endif

constexpr int CLIENTS = 16;
constexpr int DEPTH = 16;
constexpr int BUF = 65536;

constexpr std::string_view HELLO = "Hello, World!";
constexpr std::string_view PLAIN =
    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nHello, World!";

static bool send_all(SOCKET s, const char *p, size_t n) {
    while (n > 0) {
        int w = send(s, p, (int)n, 0);
        if (w <= 0) return false;
        p += w;
        n -= w;
    }
    return true;
}

// the buffer a connection reads into: bytes [start, stop) are unread
struct Input {
    std::vector<char> bytes = std::vector<char>(BUF);
    size_t start = 0, stop = 0;

    std::string_view window() const { return {bytes.data() + start, stop - start}; }

    // reads more; false when the peer closed
    bool fill(SOCKET s) {
        if (start == stop) {
            start = stop = 0;
        } else if (stop == bytes.size()) {
            memmove(bytes.data(), bytes.data() + start, stop - start);
            stop -= start;
            start = 0;
        }
        int n = recv(s, bytes.data() + stop, (int)(bytes.size() - stop), 0);
        if (n <= 0) return false;
        stop += n;
        return true;
    }
};

// the index after the blank line ending the head in text, or npos
static size_t head_end(std::string_view text) {
    for (size_t i = 0; i + 3 < text.size(); i++) {
        char c = text[i + 3];
        if (c != '\n' && c != '\r') {
            i += 3;
        } else if (c == '\n' && text[i + 2] == '\r' && text[i + 1] == '\n' && text[i] == '\r') {
            return i + 4;
        }
    }
    return std::string_view::npos;
}

static long long content_length(std::string_view head) {
    constexpr std::string_view key = "\nContent-Length: ";
    size_t at = head.find(key);
    return at == std::string_view::npos ? 0 : atoll(head.data() + at + key.size());
}

static long long serve(SOCKET s) {
    Input in;
    std::vector<char> out(BUF * 4);
    size_t olen = 0;
    long long served = 0;
    for (;;) {
        for (;;) {
            std::string_view window = in.window();
            size_t end = head_end(window);
            if (end == std::string_view::npos) break;
            if (window.substr(0, 15) == "GET /plaintext ") {
                memcpy(out.data() + olen, PLAIN.data(), PLAIN.size());
                olen += PLAIN.size();
            } else {
                long long id = atoll(window.data() + 13);   // GET /json?id=
                char body[96];
                int n = snprintf(body, sizeof body, "{\"id\":%lld,\"message\":\"%s\",\"square\":%lld}", id, HELLO.data(), id * id);
                olen += sprintf(out.data() + olen, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n", n);
                memcpy(out.data() + olen, body, n);
                olen += n;
            }
            in.start += end;
            served++;
            if (olen > out.size() - 512) {
                send_all(s, out.data(), olen);
                olen = 0;
            }
        }
        if (olen) {
            if (!send_all(s, out.data(), olen)) break;
            olen = 0;
        }
        if (!in.fill(s)) break;
    }
    closesocket(s);
    return served;
}

struct Totals {
    long long responses = 0, bytes = 0, checksum = 0;
};

static void client(int port, long long c, long long n, Totals &totals) {
    SOCKET s = socket(AF_INET, SOCK_STREAM, 0);
    sockaddr_in addr = {};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(s, (sockaddr *)&addr, sizeof addr) != 0) return;
    std::vector<char> req(DEPTH * 80);
    Input in;
    for (long long j = 0; j < n;) {
        long long batch = n - j < DEPTH ? n - j : DEPTH;
        size_t rlen = 0;
        for (long long k = j; k < j + batch; k++) {
            if (k % 2 == 0)
                rlen += sprintf(req.data() + rlen, "GET /plaintext HTTP/1.1\r\nHost: localhost\r\n\r\n");
            else
                rlen += sprintf(req.data() + rlen, "GET /json?id=%lld HTTP/1.1\r\nHost: localhost\r\n\r\n", c * n + k);
        }
        if (!send_all(s, req.data(), rlen)) return;
        for (long long got = 0; got < batch;) {
            std::string_view window = in.window();
            size_t end = head_end(window);
            if (end != std::string_view::npos) {
                size_t len = content_length(window.substr(0, end));
                if (window.size() >= end + len) {
                    long long sum = 0;
                    for (size_t b = 0; b < len; b++) sum += (unsigned char)window[end + b];
                    totals.checksum += sum;
                    totals.bytes += end + len;
                    totals.responses++;
                    in.start += end + len;
                    got++;
                    continue;
                }
            }
            if (!in.fill(s)) return;
        }
        j += batch;
    }
    closesocket(s);
}

int main(int argc, char **argv) {
#ifdef _WIN32
    _setmode(1, _O_BINARY);
#endif
    long long n = argc > 1 ? atoll(argv[1]) : 64;
#ifdef _WIN32
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
#endif
    SOCKET listener = socket(AF_INET, SOCK_STREAM, 0);
    sockaddr_in addr = {};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(listener, (sockaddr *)&addr, sizeof addr);
    listen(listener, CLIENTS);
    SockLen len = sizeof addr;
    getsockname(listener, (sockaddr *)&addr, &len);
    int port = ntohs(addr.sin_port);

    std::vector<Totals> totals(CLIENTS);
    std::vector<long long> served(CLIENTS);
    std::vector<std::thread> clients, servers;
    for (int c = 0; c < CLIENTS; c++) clients.emplace_back(client, port, c, n, std::ref(totals[c]));
    for (int c = 0; c < CLIENTS; c++) {
        SOCKET s = accept(listener, nullptr, nullptr);
        servers.emplace_back([s, &served, c] { served[c] = serve(s); });
    }
    for (auto &t : clients) t.join();
    for (auto &t : servers) t.join();
    Totals all;
    long long serves = 0;
    for (int c = 0; c < CLIENTS; c++) {
        all.responses += totals[c].responses;
        all.bytes += totals[c].bytes;
        all.checksum += totals[c].checksum;
        serves += served[c];
    }
    printf("requests %lld\nserved %lld\nbytes %lld\nchecksum %lld\n", all.responses, serves, all.bytes, all.checksum);
    return 0;
}

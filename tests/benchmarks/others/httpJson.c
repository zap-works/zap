/* httpJson: TechEmpower's plaintext and JSON tests in one run. An HTTP/1.1 server (Winsock or POSIX sockets, a thread per
 * connection) answers 16 clients on the loopback, each with its own connection kept alive: every client
 * writes its n requests in pipelined batches of 16 (a plaintext request, then a JSON one, alternating) and
 * reads the responses; each JSON response is serialized anew. Prints the requests the clients made and the
 * server served, the response bytes read, and the sum of the bodies' bytes. */
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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

#define CLIENTS 16
#define DEPTH 16
#define BUF 65536

static const char HELLO[] = "Hello, World!";
static const char PLAIN[] =
    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nHello, World!";

static int send_all(SOCKET s, const char *p, int n) {
    while (n > 0) {
        int w = send(s, p, n, 0);
        if (w <= 0) return -1;
        p += w;
        n -= w;
    }
    return 0;
}

/* the index after the blank line ending the head in p[0..n), or -1 */
static long head_end(const char *p, long n) {
    for (long i = 0; i + 3 < n; i++) {
        char c = p[i + 3];
        if (c != '\n' && c != '\r') {
            i += 3;
        } else if (c == '\n' && p[i + 2] == '\r' && p[i + 1] == '\n' && p[i] == '\r') {
            return i + 4;
        }
    }
    return -1;
}

static long long content_length(const char *p, long head) {
    static const char key[] = "Content-Length: ";
    for (long i = 0; i + 16 < head; i++) {
        if ((p[i] == '\n') && memcmp(p + i + 1, key, 16) == 0) return atoll(p + i + 17);
    }
    return 0;
}

static void *serve(void *arg) {
    SOCKET s = (SOCKET)(intptr_t)arg;
    char *in = malloc(BUF);
    char *out = malloc(BUF * 4);
    long start = 0, stop = 0, olen = 0;
    long long served = 0;
    for (;;) {
        long end;
        while ((end = head_end(in + start, stop - start)) > 0) {
            const char *line = in + start;
            if (memcmp(line, "GET /plaintext ", 15) == 0) {
                memcpy(out + olen, PLAIN, sizeof PLAIN - 1);
                olen += sizeof PLAIN - 1;
            } else {
                long long id = atoll(line + 13);   /* GET /json?id= */
                char body[96];
                int n = snprintf(body, sizeof body, "{\"id\":%lld,\"message\":\"%s\",\"square\":%lld}", id, HELLO, id * id);
                olen += sprintf(out + olen, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n", n);
                memcpy(out + olen, body, n);
                olen += n;
            }
            start += end;
            served++;
            if (olen > BUF * 4 - 512) {
                send_all(s, out, (int)olen);
                olen = 0;
            }
        }
        if (olen) {
            if (send_all(s, out, (int)olen) < 0) break;
            olen = 0;
        }
        if (start == stop) {
            start = stop = 0;
        } else if (stop == BUF) {
            memmove(in, in + start, stop - start);
            stop -= start;
            start = 0;
        }
        int n = recv(s, in + stop, BUF - (int)stop, 0);
        if (n <= 0) break;
        stop += n;
    }
    closesocket(s);
    free(in);
    free(out);
    return (void *)(intptr_t)served;
}

typedef struct {
    int port;
    long long c, n;
    long long responses, bytes, checksum;
} Client;

static void *client(void *arg) {
    Client *cl = arg;
    SOCKET s = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(cl->port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(s, (struct sockaddr *)&addr, sizeof addr) != 0) return NULL;
    char *req = malloc(DEPTH * 80);
    char *in = malloc(BUF);
    long start = 0, stop = 0;
    for (long long j = 0; j < cl->n;) {
        long long batch = cl->n - j < DEPTH ? cl->n - j : DEPTH;
        long rlen = 0;
        for (long long k = j; k < j + batch; k++) {
            if (k % 2 == 0)
                rlen += sprintf(req + rlen, "GET /plaintext HTTP/1.1\r\nHost: localhost\r\n\r\n");
            else
                rlen += sprintf(req + rlen, "GET /json?id=%lld HTTP/1.1\r\nHost: localhost\r\n\r\n", cl->c * cl->n + k);
        }
        if (send_all(s, req, (int)rlen) < 0) return NULL;
        for (long long got = 0; got < batch;) {
            long end = head_end(in + start, stop - start);
            if (end > 0) {
                long long len = content_length(in + start, end);
                if (stop - start >= end + len) {
                    const unsigned char *body = (const unsigned char *)in + start + end;
                    long long sum = 0;
                    for (long long b = 0; b < len; b++) sum += body[b];
                    cl->checksum += sum;
                    cl->bytes += end + len;
                    cl->responses++;
                    start += end + len;
                    got++;
                    continue;
                }
            }
            if (start == stop) {
                start = stop = 0;
            } else if (stop == BUF) {
                memmove(in, in + start, stop - start);
                stop -= start;
                start = 0;
            }
            int r = recv(s, in + stop, BUF - (int)stop, 0);
            if (r <= 0) return NULL;
            stop += r;
        }
        j += batch;
    }
    closesocket(s);
    free(req);
    free(in);
    return NULL;
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
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(listener, (struct sockaddr *)&addr, sizeof addr);
    listen(listener, CLIENTS);
    SockLen len = sizeof addr;
    getsockname(listener, (struct sockaddr *)&addr, &len);
    int port = ntohs(addr.sin_port);

    pthread_t clients[CLIENTS], servers[CLIENTS];
    Client totals[CLIENTS];
    for (int c = 0; c < CLIENTS; c++) {
        memset(&totals[c], 0, sizeof totals[c]);
        totals[c].port = port;
        totals[c].c = c;
        totals[c].n = n;
        pthread_create(&clients[c], NULL, client, &totals[c]);
    }
    for (int c = 0; c < CLIENTS; c++) {
        SOCKET s = accept(listener, NULL, NULL);
        pthread_create(&servers[c], NULL, serve, (void *)(intptr_t)s);
    }
    long long responses = 0, bytes = 0, checksum = 0, served = 0;
    for (int c = 0; c < CLIENTS; c++) {
        pthread_join(clients[c], NULL);
        responses += totals[c].responses;
        bytes += totals[c].bytes;
        checksum += totals[c].checksum;
    }
    for (int c = 0; c < CLIENTS; c++) {
        void *r;
        pthread_join(servers[c], &r);
        served += (long long)(intptr_t)r;
    }
    printf("requests %lld\nserved %lld\nbytes %lld\nchecksum %lld\n", responses, served, bytes, checksum);
    return 0;
}

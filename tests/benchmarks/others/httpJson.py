# httpJson: TechEmpower's plaintext and JSON tests in one run. An HTTP/1.1 server (socket, a thread per
# connection) answers 16 clients on the loopback, each with its own connection kept alive: every client
# writes its n requests in pipelined batches of 16 (a plaintext request, then a JSON one, alternating) and
# reads the responses; each JSON response is serialized anew. Prints the requests the clients made and the
# server served, the response bytes read, and the sum of the bodies' bytes.
import socket
import sys
import threading

CLIENTS = 16
DEPTH = 16
BUF = 65536
HELLO = "Hello, World!"
PLAIN = b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nHello, World!"
JSON_HEAD = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s"


def serve(conn, served, slot):
    data = b""
    count = 0
    out = []
    while True:
        start = 0
        while True:
            end = data.find(b"\r\n\r\n", start)
            if end < 0:
                break
            if data.startswith(b"GET /plaintext ", start):
                out.append(PLAIN)
            else:
                ident = int(data[start + 13 : data.index(b" ", start + 13)])  # GET /json?id=
                body = '{"id":%d,"message":"%s","square":%d}' % (ident, HELLO, ident * ident)
                out.append((JSON_HEAD % (len(body), body)).encode())
            start = end + 4
            count += 1
        if out:
            conn.sendall(b"".join(out))
            out = []
        data = data[start:]
        chunk = conn.recv(BUF)
        if not chunk:
            break
        data += chunk
    conn.close()
    served[slot] = count


def client(port, c, n, totals, slot):
    conn = socket.create_connection(("127.0.0.1", port))
    data = b""
    responses = nbytes = checksum = 0
    j = 0
    while j < n:
        batch = min(DEPTH, n - j)
        requests = []
        for k in range(j, j + batch):
            if k % 2 == 0:
                requests.append(b"GET /plaintext HTTP/1.1\r\nHost: localhost\r\n\r\n")
            else:
                requests.append(b"GET /json?id=%d HTTP/1.1\r\nHost: localhost\r\n\r\n" % (c * n + k))
        conn.sendall(b"".join(requests))
        start = 0
        got = 0
        while got < batch:
            end = data.find(b"\r\n\r\n", start)
            if end >= 0:
                head = data[start : end + 4]
                at = head.find(b"\nContent-Length: ")
                length = int(head[at + 17 :].split(b"\r", 1)[0]) if at >= 0 else 0
                if len(data) - start >= len(head) + length:
                    body = data[end + 4 : end + 4 + length]
                    checksum += sum(body)
                    nbytes += len(head) + length
                    responses += 1
                    start += len(head) + length
                    got += 1
                    continue
            data = data[start:] + conn.recv(BUF)
            start = 0
        data = data[start:]
        j += batch
    conn.close()
    totals[slot] = (responses, nbytes, checksum)


def main():
    sys.stdout.reconfigure(newline="\n")
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 64
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(CLIENTS)
    port = listener.getsockname()[1]
    totals = [(0, 0, 0)] * CLIENTS
    served = [0] * CLIENTS
    clients = [threading.Thread(target=client, args=(port, c, n, totals, c)) for c in range(CLIENTS)]
    for t in clients:
        t.start()
    servers = []
    for c in range(CLIENTS):
        conn, _ = listener.accept()
        t = threading.Thread(target=serve, args=(conn, served, c))
        t.start()
        servers.append(t)
    for t in clients + servers:
        t.join()
    print("requests %d" % sum(t[0] for t in totals))
    print("served %d" % sum(served))
    print("bytes %d" % sum(t[1] for t in totals))
    print("checksum %d" % sum(t[2] for t in totals))


main()

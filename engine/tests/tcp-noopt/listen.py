# Accepts one TCP connection on 127.0.0.1, prints the TCP options it uses (macOS's
# TCP_CONNECTION_INFO: ts, sack, wscale) and its MSS, then closes it. Prints the port first.
import socket, struct, sys
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(1); s.settimeout(60)
print(s.getsockname()[1], flush=True)
c, _ = s.accept()
info = c.getsockopt(socket.IPPROTO_TCP, 0x106, 128)
opts = struct.unpack_from("<I", info, 4)[0]
names = [n for b, n in ((1, "ts"), (2, "sack"), (4, "wscale")) if opts & b]
mss = c.getsockopt(socket.IPPROTO_TCP, socket.TCP_MAXSEG)
print(",".join(names) or "none", mss, flush=True)
c.close()

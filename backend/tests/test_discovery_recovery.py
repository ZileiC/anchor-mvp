"""A responder that finds its UDP port taken must recover on its own.

2026-11-14. The failure this guards against is the one that actually happened: a
killed PyInstaller one-file backend keeps its child process alive for a few
seconds, that child still holds UDP 8078, the freshly started backend cannot bind
and would stay invisible for the rest of the session. The demo then looks like
"it connected a minute ago, now it never does".
"""

from __future__ import annotations

import socket
import time

from app.discovery import PROBE, DiscoveryResponder


def _free_udp_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def _ask(port: int, timeout: float):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        client.settimeout(timeout)
        client.sendto(PROBE, ("127.0.0.1", port))
        try:
            answer, _address = client.recvfrom(2048)
        except (socket.timeout, ConnectionResetError):
            return None
        return answer


def test_the_port_is_retaken_once_the_squatter_goes_away():
    port = _free_udp_port()
    # Something that is NOT an Anchor backend holds the port: the responder must
    # not mistake "no Anchor answers" for "the port is mine free and clear".
    squatter = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    squatter.bind(("", port))
    responder = DiscoveryResponder(http_port=8077, discovery_port=port)
    try:
        assert responder.start() is True, "a busy port is not a reason to give up"
        # While the squatter holds it, our probe still reaches the squatter and
        # there is no Anchor reply.
        assert _ask(port, timeout=0.4) is None

        squatter.close()
        # The background retry (every 2 s) must pick the port up by itself.
        deadline = time.time() + 8
        answer = None
        while time.time() < deadline:
            answer = _ask(port, timeout=0.4)
            if answer is not None:
                break
            time.sleep(0.5)
        assert answer is not None, "the responder never recovered the UDP port"
        assert b"anchor-backend" in answer
    finally:
        responder.stop()
        try:
            squatter.close()
        except OSError:
            pass

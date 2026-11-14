"""Let the phone find this computer by itself, 2026-11-14.

The requirement, in the owner's words: *turn the phone hotspot on, connect the
computer to it, and the two ends bind automatically.* Typing an IP address is not
an acceptable step for a family setting up an appliance for an older adult, and
the computer's address changes with every network (10.4.x at home, 10.2.x on
campus, 192.168.43.x on an Android hotspot), so any "just put the address in the
build" scheme is wrong by construction.

Two independent mechanisms, because one of them will be blocked somewhere:

1. **UDP beacon (primary).** The backend listens on a fixed UDP port for the
   literal probe ``ANCHOR-DISCOVER-v1`` and answers the sender with a small JSON
   document. The phone does not even need the payload: the *source address of the
   reply* is this computer, which is exactly what it wanted to learn.
2. **HTTP sweep (fallback).** If multicast/broadcast is filtered (guest Wi-Fi,
   client isolation, an aggressive firewall), the phone can still try every host
   on its own /24 for ``GET /api/v1/health``. That lives on the phone side; this
   module only has to be answerable over HTTP, which it already is.

Nothing here trusts the network: the responder only ever answers one magic
payload, and it never exposes anything beyond the port and the app name. The
phone still verifies ``/api/v1/health`` before adopting an address.
"""

from __future__ import annotations

import json
import socket
import threading
import time
from typing import Any, Optional

#: The exact bytes a phone sends to ask "is an Anchor backend here?".
PROBE = b"ANCHOR-DISCOVER-v1"

#: Replies are tagged so a phone can ignore anything else on that port.
REPLY_TAG = "anchor-backend"

#: UDP port used only for discovery; the API itself stays on ANCHOR_PORT (TCP).
DEFAULT_DISCOVERY_PORT = 8078

#: Longest a probe reply may be. A tiny datagram cannot be used to amplify.
MAX_PROBE_SIZE = 512


class DiscoveryResponder:
    """Answers UDP probes on one port until [stop] is called.

    Runs in a daemon thread next to uvicorn: it must never keep the process alive
    and must never raise into the server loop, so every failure is swallowed and
    logged through ``debug_print``.
    """

    def __init__(
        self,
        http_port: int,
        discovery_port: int = DEFAULT_DISCOVERY_PORT,
        debug_print=print,
    ) -> None:
        self.http_port = int(http_port)
        self.discovery_port = int(discovery_port)
        self._debug = debug_print
        self._stop = threading.Event()
        self._sock: Optional[socket.socket] = None
        self._thread: Optional[threading.Thread] = None

    # -- lifecycle ---------------------------------------------------------
    def start(self) -> bool:
        """Start answering. False only when another Anchor already answers here.

        A second backend on the same machine is a normal situation (the desktop
        app already started one), so this is not an error: the first responder
        keeps answering and the copy disappears quietly.

        The port is probed *before* binding: Windows happily lets two UDP sockets
        share a port when SO_REUSEADDR is set, and then replies land on whichever
        socket the stack picked — a coin toss that produces "sometimes it works".

        Binding is retried inside the thread, 2026-11-14: a half-dead leftover
        backend (a killed PyInstaller one-file keeps its child alive) can hold the
        port for a few seconds after the app starts. Without the retry the *live*
        backend stays invisible until someone restarts it, which is exactly the
        "it worked a minute ago and now it never connects" that a demo cannot
        afford.
        """
        if self._port_answers():
            self._debug(
                f"discovery: another Anchor backend already answers on UDP {self.discovery_port}"
            )
            return False
        self._thread = threading.Thread(
            target=self._serve, name="anchor-discovery", daemon=True
        )
        self._thread.start()
        # Give the first bind attempt a moment so the common case is known here.
        deadline = 1.0
        waited = 0.0
        while waited < deadline and self._sock is None and not self._stop.is_set():
            threading.Event().wait(0.05)
            waited += 0.05
        if self._sock is None:
            self._debug(
                f"discovery: UDP {self.discovery_port} busy; will keep retrying in the background"
            )
        return True

    def _bind(self) -> Optional[socket.socket]:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.settimeout(0.5)
            sock.bind(("", self.discovery_port))
            return sock
        except OSError as error:
            self._debug(f"discovery: cannot listen on UDP {self.discovery_port}: {error}")
            return None

    def _port_answers(self) -> bool:
        """True when an Anchor backend already replies to a probe here."""
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
                client.settimeout(0.3)
                client.sendto(PROBE, ("127.0.0.1", self.discovery_port))
                client.recvfrom(MAX_PROBE_SIZE)
        except (OSError, socket.timeout):
            return False
        return True

    def stop(self) -> None:
        self._stop.set()
        thread = self._thread
        if thread is not None:
            thread.join(timeout=2.0)
        sock = self._sock
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass
        self._sock = None

    # -- serving -----------------------------------------------------------
    def _serve(self) -> None:
        retry_at = 0.0
        while not self._stop.is_set():
            sock = self._sock
            if sock is None:
                # Bind (again): the port may have been held by a dying leftover.
                now = time.monotonic()
                if now >= retry_at:
                    sock = self._bind()
                    if sock is None:
                        retry_at = now + 2.0
                        self._stop.wait(0.2)
                        continue
                    self._sock = sock
                    self._debug(
                        f"discovery: answering UDP {self.discovery_port} probes for port {self.http_port}"
                    )
                else:
                    self._stop.wait(0.2)
                    continue
            try:
                data, address = sock.recvfrom(MAX_PROBE_SIZE)
            except socket.timeout:
                continue
            except OSError:
                break
            if self._stop.is_set():
                break
            if not self._is_probe(data):
                continue
            try:
                sock.sendto(self._reply(), address)
                self._debug(f"discovery: answered {address[0]}")
            except OSError as error:
                self._debug(f"discovery: could not answer {address[0]}: {error}")

    @staticmethod
    def _is_probe(data: bytes) -> bool:
        # Accept the probe with padding or trailing noise: some stacks pad
        # datagrams, and being strict here would be a silent failure on a phone
        # that appended a newline.
        return PROBE in data

    def _reply(self) -> bytes:
        document: dict[str, Any] = {
            "app": REPLY_TAG,
            "port": self.http_port,
            "discovery_port": self.discovery_port,
            "hostname": _hostname(),
        }
        return json.dumps(document, separators=(",", ":")).encode("utf-8")


def _hostname() -> str:
    try:
        return socket.gethostname()
    except OSError:
        return ""


def local_addresses() -> list[str]:
    """Every IPv4 address a phone on the same network could reach.

    Kept for the diagnostics line the desktop prints and for tests; the phone
    learns the real one from the reply's source address, which is more reliable
    than anything this process can guess about itself.
    """
    addresses: list[str] = []
    try:
        seen = set()
        for entry in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            address = entry[4][0]
            if address in seen or address.startswith("127.") or address.startswith("169.254."):
                continue
            seen.add(address)
            addresses.append(address)
    except OSError:
        return []
    return addresses

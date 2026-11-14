"""The phone must be able to find the computer with no typing (2026-11-14).

Requirement, verbatim: turn the phone hotspot on, connect the computer to it, and
the two ends bind automatically. These tests pin the responder half of that — the
phone-side discovery is tested in ``mobile/test/backend_discovery_test.dart``.

Everything here binds a real UDP socket on a free port: a mocked responder would
prove nothing about the thing that actually has to cross a hotspot.
"""

from __future__ import annotations

import json
import socket
import time

from app.discovery import (
    DEFAULT_DISCOVERY_PORT,
    PROBE,
    REPLY_TAG,
    DiscoveryResponder,
    local_addresses,
)


def _free_udp_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def _responder(http_port: int = 8077) -> tuple[DiscoveryResponder, int]:
    port = _free_udp_port()
    responder = DiscoveryResponder(http_port=http_port, discovery_port=port)
    assert responder.start() is True
    return responder, port


def _ask(port: int, payload: bytes = PROBE, timeout: float = 2.0) -> bytes | None:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        client.settimeout(timeout)
        client.sendto(payload, ("127.0.0.1", port))
        try:
            answer, _address = client.recvfrom(2048)
        except socket.timeout:
            return None
        except ConnectionResetError:
            # Windows reports "nobody is listening on that UDP port" as an ICMP
            # port-unreachable surfaced on the next recvfrom, not as a timeout.
            # For this helper both mean the same thing: there is no responder.
            return None
        return answer


def test_a_probe_is_answered_with_the_api_port():
    responder, port = _responder(http_port=8077)
    try:
        answer = _ask(port)
    finally:
        responder.stop()
    assert answer is not None, "no reply to a discovery probe"
    document = json.loads(answer.decode("utf-8"))
    assert document["app"] == REPLY_TAG
    assert document["port"] == 8077
    assert document["discovery_port"] == port


def test_the_reply_carries_the_port_the_server_really_uses():
    responder, port = _responder(http_port=9911)
    try:
        answer = _ask(port)
    finally:
        responder.stop()
    assert json.loads(answer.decode("utf-8"))["port"] == 9911


def test_noise_is_ignored_and_never_answers():
    responder, port = _responder()
    try:
        # A proxy health check, a stray broadcast, an empty packet: none of these
        # may make the backend identify itself.
        for payload in (b"", b"GET / HTTP/1.1\r\n\r\n", b"ANCHOR-DISCOVER"):
            assert _ask(port, payload, timeout=0.4) is None, payload
    finally:
        responder.stop()


def test_the_probe_is_answered_even_with_padding():
    # A phone that appended a newline (or a stack that pads datagrams) must still
    # be understood; being strict here would be a silent failure in the field.
    responder, port = _responder()
    try:
        answer = _ask(port, PROBE + b"\r\n")
    finally:
        responder.stop()
    assert answer is not None
    assert json.loads(answer.decode("utf-8"))["app"] == REPLY_TAG


def test_a_second_responder_on_the_same_port_backs_off():
    first, port = _responder()
    second = DiscoveryResponder(http_port=8077, discovery_port=port)
    try:
        assert second.start() is False, "the second responder must not steal the port"
        # The first one still answers, and answers exactly once per probe.
        assert _ask(port) is not None
    finally:
        second.stop()
        first.stop()


def test_a_stopped_responder_can_be_started_again():
    responder, port = _responder()
    responder.stop()
    fresh = DiscoveryResponder(http_port=8077, discovery_port=port)
    try:
        assert fresh.start() is True
        assert _ask(port) is not None
    finally:
        fresh.stop()


def test_stop_actually_silences_it():
    responder, port = _responder()
    responder.stop()
    time.sleep(0.1)
    assert _ask(port, timeout=0.5) is None


def test_the_default_port_is_the_one_the_app_looks_for():
    # The phone hard-codes this; a change here without the phone changing is a
    # discovery that silently never works.
    assert DEFAULT_DISCOVERY_PORT == 8078


def test_local_addresses_never_report_loopback_or_link_local():
    for address in local_addresses():
        assert not address.startswith("127.")
        assert not address.startswith("169.254.")

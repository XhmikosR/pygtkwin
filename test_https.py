"""HTTPS smoke test for the freshly built Python/OpenSSL.

Verifies that the debloated OpenSSL build can still perform a TLS 1.2/1.3
handshake and an end-to-end HTTPS request.  Run after the vcpkg build, e.g.:

    python test_https.py --dll-directory <vcpkg_installed>/x86-windows/bin

The --dll-directory option must be processed before importing ssl so that
libcrypto-3.dll / libssl-3.dll are on the DLL search path.
"""

import getopt
import os
import sys
import time


def with_retries(func, attempts=3, delay=5):
    """Call func, retrying network errors but not TLS failures."""
    import http.client
    import ssl

    for attempt in range(1, attempts + 1):
        try:
            return func()
        except (OSError, http.client.HTTPException) as err:
            # urllib wraps the underlying error in URLError.reason
            tls_error = isinstance(err, ssl.SSLError) or isinstance(getattr(err, "reason", None), ssl.SSLError)
            if tls_error or attempt == attempts:
                raise
            print(f"Attempt {attempt} failed: {err}; retrying in {delay}s")
            time.sleep(delay)


def main():
    try:
        opts, _args = getopt.getopt(sys.argv[1:], "hd:", ["help", "dll-directory="])
    except getopt.GetoptError as err:
        print(err, file=sys.stderr)
        sys.exit(2)

    dll_directory = None
    for opt, arg in opts:
        if opt in ("-h", "--help"):
            print(f"Usage: {os.path.basename(sys.argv[0])} [--dll-directory=DIR]")
            sys.exit(0)
        elif opt in ("-d", "--dll-directory"):
            dll_directory = arg

    if dll_directory:
        dll_directory = os.path.abspath(dll_directory)
        if hasattr(os, "add_dll_directory"):
            os.add_dll_directory(dll_directory)

    # Imported after os.add_dll_directory so the OpenSSL DLLs are found.
    import hashlib
    import socket
    import ssl
    import urllib.request

    # The chaff file is a real URL fetched by BleachBit, so it exercises the
    # same TLS code path end users hit.
    host = "download.bleachbit.org"
    port = 443
    path = "/chaff/clinton_subject_model.json.bz2"
    timeout = 15
    # Pinned so the test also catches truncation/corruption, not just
    # connectivity.  Update this if BleachBit regenerates the chaff file.
    expected_sha256 = "d068ef193a55e7fb879a1455274c8be85bd5da693cb8d8c0a1bc36bb101bd9f3"

    print(f"OpenSSL: {ssl.OPENSSL_VERSION}")

    # 1. Low-level handshake: confirm TLS negotiates 1.2 or 1.3 with a valid
    #    certificate chain (create_default_context enables verification).
    ctx = ssl.create_default_context()

    def handshake():
        with socket.create_connection((host, port), timeout=timeout) as raw:
            with ctx.wrap_socket(raw, server_hostname=host) as ssock:
                return ssock.version(), ssock.cipher()

    version, cipher = with_retries(handshake)
    print(f"TLS handshake OK: {version}, cipher={cipher[0] if cipher else '?'}")
    if version not in ("TLSv1.2", "TLSv1.3"):
        print(f"FAIL: negotiated {version}, expected TLSv1.2 or TLSv1.3")
        sys.exit(1)

    # 2. End-to-end HTTPS GET with certificate verification enabled.  Read the
    #    whole file and verify its SHA-256 against a pinned value; the "BZh"
    #    bzip2 magic is a fast early sanity check for real data vs. an error
    #    page.
    url = f"https://{host}{path}"
    req = urllib.request.Request(url, headers={"User-Agent": "pygtkwin-smoke-test"})

    def fetch():
        with urllib.request.urlopen(req, context=ctx, timeout=timeout) as resp:
            return resp.status, resp.read()

    status, body = with_retries(fetch)
    print(f"HTTPS GET {url} -> {status}, {len(body)} bytes")
    if status != 200:
        print(f"FAIL: HTTP status {status}")
        sys.exit(1)
    if body[:3] != b"BZh":
        print(f"FAIL: expected bzip2 magic 'BZh', got {body[:3]!r}")
        sys.exit(1)
    digest = hashlib.sha256(body).hexdigest()
    if digest != expected_sha256:
        print(f"FAIL: sha256 {digest} != expected {expected_sha256}")
        sys.exit(1)

    print(f"PASS: HTTPS smoke test succeeded ({version})")


if __name__ == "__main__":
    main()

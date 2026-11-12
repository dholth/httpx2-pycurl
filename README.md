# httpx2-pycurl

`httpx2-pycurl` provides an `httpx2` transport that executes requests with
`pycurl`.  It combines the [goodness of curl](https://everything.curl.dev/) with
the familiar `httpx2` API, including support for `http/2` and even non-http
protocols built into `curl`. `AsyncPyCurlTransport` performs better than
`httpx2`'s default `AsyncHttpTransport` with `http2=True`, taking about 78% of
the time to issue 128 requests in parallel. Under heavier usage `httpx2-pycurl`
appears to pull further ahead of alternative libraries, without replacing all of
`httpx2`; just `httpx2`'s transport.

## Usage

`AsyncPyCurlTransport` is the focus of this package. It uses the curl
[`multi_socket`](https://everything.curl.dev/transfers/drive/multi-socket.html)
interface to integrate `curl` with the `asyncio` event loop.

```python
import httpx2
from httpx2_pycurl import AsyncPyCurlTransport

transport = AsyncPyCurlTransport(timeout=10.0)

async with httpx2.AsyncClient(transport=transport) as client:
    responses = await asyncio.gather(*(client.get(url) for url in urls))
```

`AsyncPyCurlTransport` delegates SSL/TLS handling to `curl` and does not use
Python's builtin `ssl` module. By default it calls
[`certifi.where()`](https://github.com/certifi/python-certifi) to set root
certificates. It is also possible to pass a custom path to the root certificates
with `AsyncPyCurlTransport(cainfo=ca_cert_path)`.

`PyCurlTransport` is not the focus of this project and is less likely to work.
In the future it may delegate to `AsyncPyCurlTransport`.

```python
import httpx2
from httpx2_pycurl import PyCurlTransport

transport = PyCurlTransport(timeout=10.0)

with httpx2.Client(transport=transport) as client:
    response = client.get("https://example.com")
    print(response.status_code)
    print(response.text)

debug_transport = PyCurlTransport(
    verbose=True,
    debug_callback=lambda info_type, data: print(info_type, data),
)
```

## Installation

```bash
pip install httpx2-pycurl
```

Or with conda,

```bash
conda install -n base conda-pypi
conda pypi install httpx2-pycurl
```

## Performance

Before the rename, `httpx-pycurl` was tested against `httpx`. It is in early
development but it passed most `httpx` tests and has good performance. Our
`tests/bench.py` uses `asyncio.gather()` to make many `http/2` requests to
`https://httpbingo.org/get` using `httpx`, `niquests`, and `httpx` with
`httpx-pycurl`'s transport. `httpx-pycurl` was the fastest library tested.

Running `tests/bench.py [N]` shows that the more efficient `http/2` libraries
shine when performing large numbers of parallel requests, and are closer
together when only groups of 128 parallel requests are made.

```
2 groups of 512 requests each...

Time per group:
httpx2: 0.679s ± 0.119s
niquests: 0.432s ± 0.140s
httpx2_pycurl: 0.299s ± 0.056s

Paired t-test: httpx2_pycurl vs niquests
t-stat: -2.249 (approx p < 0.05 if |t| > 2.365)
Speedup: 1.44x
```

```
4 groups of 256 requests each...

Time per group:
httpx2: 0.378s ± 0.077s
niquests: 0.259s ± 0.064s
httpx2_pycurl: 0.190s ± 0.034s

Paired t-test: httpx2_pycurl vs niquests
t-stat: -4.208 (approx p < 0.05 if |t| > 2.365)
Speedup: 1.36x
```

```
8 groups of 128 requests each...

Time per group:
httpx2: 0.215s ± 0.073s
niquests: 0.205s ± 0.038s
httpx2_pycurl: 0.162s ± 0.033s

Paired t-test: httpx2_pycurl vs niquests
t-stat: -8.949 (approx p < 0.05 if |t| > 2.365)
Speedup: 1.27x
```

## Dependencies

`httpx2-pycurl` uses curl to support `http/2` instead of the `h2`, `hpack` and
`hyperframe` dependencies used by `httpx2`.

```
$ pip install --dry-run httpx2-pycurl
...
Would install anyio-4.13.0 certifi-2026.4.22 h11-0.16.0 httpcore2-2.16.0 httpx2-2.16.0 httpx2-pycurl-0.0.5 idna-3.20 pycurl-7.45.7 truststore-0.10.5

$ pip install --dry-run httpx2[http2]
...
Would install anyio-4.13.0 certifi-2026.4.22 h2-4.3.0 h11-0.16.0 hpack-4.1.0 httpcore2-2.16.0 httpx2-2.16.0 hyperframe-6.1.0 idna-3.20 truststore-0.10.5
```

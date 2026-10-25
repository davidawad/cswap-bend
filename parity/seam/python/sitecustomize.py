"""Test seam for the Python reference cswap (claude-swap 0.27.2 + patches).

The replay script puts this directory on PYTHONPATH, so the reference picks
it up at interpreter start. It is inert unless CSWAP_TEST_HTTP_BASE is set,
and it does nothing for a non-Python implementation (which must honour the
same environment natively; see contract.md "Test seam").

What it does, and nothing more:

1. HTTP: every ``https://<host>/<path>`` request made through
   ``urllib.request.urlopen`` goes to ``$CSWAP_TEST_HTTP_BASE/<host>/<path>``
   instead (the replay's stub server). No request ever leaves the machine.
2. Backup root: forces the macOS layout ``~/.claude-swap-backup`` on every
   platform, so fixtures recorded on Linux describe the production layout.
3. Update check: disabled (PyPI self-update is out of contract).
"""

import os

_BASE = os.environ.get("CSWAP_TEST_HTTP_BASE")

if _BASE:
    import urllib.request

    _real_urlopen = urllib.request.urlopen

    def _redirect(url):
        if url.startswith("https://"):
            return _BASE.rstrip("/") + "/" + url[len("https://"):]
        return url

    def _seam_urlopen(req, *args, **kwargs):
        if isinstance(req, str):
            req = _redirect(req)
        else:
            req.full_url = _redirect(req.full_url)
        kwargs.pop("context", None)
        return _real_urlopen(req, *args, **kwargs)

    urllib.request.urlopen = _seam_urlopen

    try:
        from claude_swap import paths as _paths

        # Swap the code object, not the binding: importing paths already
        # pulled in modules that did `from claude_swap.paths import
        # get_backup_root`, and they must see the macOS root too.
        _paths.get_backup_root.__code__ = _paths.get_legacy_backup_root.__code__

        from claude_swap import update_check as _update_check

        _update_check.check_for_update = lambda *_a, **_k: None
    except ImportError:
        pass

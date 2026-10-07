#!/usr/bin/env python3
"""Minimal App Store Connect API client for Parchmatte releases.

Credentials come from the environment, never from this file:
  ASC_KEY_ID       API key ID
  ASC_ISSUER_ID    issuer ID
  ASC_KEY_PATH     path to the AuthKey_<id>.p8 private key (mode 600)

Needs PyJWT and cryptography, pinned with hashes:
  pip install --require-hashes -r scripts/requirements-release.txt

Usage (as a module):
  from asc_api import ASC
  asc = ASC()
  app = asc.get("/v1/apps", params={"filter[bundleId]": "com.galacticluddite.parchmatte"})
"""
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

BASE = "https://api.appstoreconnect.apple.com"


class ASCError(RuntimeError):
    pass


class ASC:
    def __init__(self):
        try:
            self.key_id = os.environ["ASC_KEY_ID"]
            self.issuer = os.environ["ASC_ISSUER_ID"]
            key_path = os.path.expanduser(os.environ["ASC_KEY_PATH"])
        except KeyError as missing:
            raise ASCError(f"missing environment variable {missing}") from None
        # Refuse a key other users could read: it signs as the whole team.
        mode = os.stat(key_path).st_mode
        if mode & 0o077:
            raise ASCError(f"{key_path} is readable by group or others (mode {oct(mode & 0o777)}); run chmod 600 on it")
        with open(key_path) as handle:
            self._key = handle.read()
        self._token, self._expires = None, 0

    def _auth(self):
        now = int(time.time())
        if not self._token or now > self._expires - 60:
            self._expires = now + 15 * 60
            self._token = jwt.encode(
                {"iss": self.issuer, "iat": now, "exp": self._expires, "aud": "appstoreconnect-v1"},
                self._key, algorithm="ES256", headers={"kid": self.key_id, "typ": "JWT"},
            )
        return self._token

    def request(self, method, path, params=None, body=None):
        url = BASE + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f"Bearer {self._auth()}", "Content-Type": "application/json",
        })
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as err:
            detail = err.read().decode(errors="replace")
            raise ASCError(f"{method} {path} -> {err.code}: {detail[:800]}") from None

    def get(self, path, params=None):
        return self.request("GET", path, params=params)

    def patch(self, path, body):
        return self.request("PATCH", path, body=body)

    def post(self, path, body):
        return self.request("POST", path, body=body)

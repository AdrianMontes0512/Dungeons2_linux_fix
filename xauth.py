#!/usr/bin/env python3
"""Sign in with the user's own Microsoft account and cache Xbox tokens.

The browser login uses this game's Microsoft app id. Tokens are written
for the local runtime; they are never printed.
"""
import base64
import hashlib
import json
import os
import struct
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone

CLIENT = "00000000497C1B94"
SCOPE = "service::user.auth.xboxlive.com::MBI_SSL"
PLAYFAB_RP = "http://playfab.xboxlive.com/"
HERE = os.path.dirname(os.path.abspath(__file__))
TOKEN_PATH = os.path.join(HERE, "tokens.txt")
CODE_PATH = os.path.join(HERE, "login-code.txt")


def post(url, form=None, payload=None):
    if payload is not None:
        data = json.dumps(payload).encode()
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
    else:
        data = urllib.parse.urlencode(form).encode()
        headers = {"Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"}
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError:
            parsed = {"error": body[:300]}
        parsed["_status"] = exc.code
        return parsed


def jwt_exp(token):
    try:
        if ";" in token:
            token = token.rsplit(";", 1)[1]
        part = token.split(".")[1]
        part += "=" * (-len(part) % 4)
        data = json.loads(base64.urlsafe_b64decode(part))
        return int(data.get("exp", 0))
    except Exception:
        return 0


def repair_stored_exp():
    if not os.path.isfile(TOKEN_PATH):
        return
    lines = []
    values = {}
    with open(TOKEN_PATH, "r", encoding="utf-8") as handle:
        for line in handle:
            lines.append(line.rstrip("\n"))
            if "=" in line:
                key, value = line.rstrip("\n").split("=", 1)
                values[key] = value
    if int(values.get("exp") or "0") > time.time() + 120:
        return
    exp = 0
    for key in ("xbox", "mc"):
        got = jwt_exp(values.get(key, ""))
        if got:
            exp = min(exp, got) if exp else got
    if not exp:
        return
    replaced = False
    for i, line in enumerate(lines):
        if line.startswith("exp="):
            lines[i] = "exp=%s" % exp
            replaced = True
    if not replaced:
        lines.insert(0, "exp=%s" % exp)
    write_tokens([(line.split("=", 1)[0], line.split("=", 1)[1] if "=" in line else "") for line in lines])


def cached_ok():
    if not os.path.isfile(TOKEN_PATH):
        return False
    exp = 0
    with open(TOKEN_PATH, "r", encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("exp="):
                exp = int(line[4:].strip() or "0")
    return exp > time.time() + 120


def rps_ticket(access):
    if access.startswith("t=") or access.startswith("d="):
        return access
    if access.startswith("eyJ"):
        return "d=" + access
    return "t=" + access


def _b64url(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def device_token():
    """Mint a Win32 device token through a signed proof-of-possession request.

    PlayFab rejects XSTS tokens that carry no device identity, so the
    PlayFab relying-party token has to include one. Returns None when the
    cryptography package is unavailable or the request fails.
    """
    try:
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import (
            Prehashed,
            decode_dss_signature,
        )
    except ImportError:
        return None

    key = ec.generate_private_key(ec.SECP256R1())
    point = key.public_key().public_numbers()
    proof = {
        "use": "sig", "alg": "ES256", "kty": "EC", "crv": "P-256",
        "x": _b64url(point.x.to_bytes(32, "big")),
        "y": _b64url(point.y.to_bytes(32, "big")),
    }
    body = json.dumps({
        "RelyingParty": "http://auth.xboxlive.com",
        "TokenType": "JWT",
        "Properties": {
            "AuthMethod": "ProofOfPossession",
            "Id": "{%s}" % uuid.uuid4(),
            "DeviceType": "Win32",
            "SerialNumber": "{%s}" % uuid.uuid4(),
            "Version": "10.0.19041",
            "ProofKey": proof,
        },
    }).encode()

    version = struct.pack("!I", 1)
    epoch = datetime(1601, 1, 1, tzinfo=timezone.utc)
    filetime = int((datetime.now(timezone.utc) - epoch).total_seconds() * 10_000_000)
    stamp = struct.pack("!Q", filetime)
    signed = (version + b"\x00" + stamp + b"\x00" + b"POST" + b"\x00" +
              b"/device/authenticate" + b"\x00" + b"\x00" + body[:8192] + b"\x00")
    raw = key.sign(hashlib.sha256(signed).digest(), ec.ECDSA(Prehashed(hashes.SHA256())))
    r, s = decode_dss_signature(raw)
    signature = base64.b64encode(
        version + stamp + r.to_bytes(32, "big") + s.to_bytes(32, "big")
    ).decode()

    request = urllib.request.Request(
        "https://device.auth.xboxlive.com/device/authenticate",
        data=body,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "x-xbl-contract-version": "1",
            "Signature": signature,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode()).get("Token")
    except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError):
        return None


def xbox_user(access):
    result = post("https://user.auth.xboxlive.com/user/authenticate", payload={
        "Properties": {
            "AuthMethod": "RPS",
            "SiteName": "user.auth.xboxlive.com",
            "RpsTicket": rps_ticket(access),
        },
        "RelyingParty": "http://auth.xboxlive.com",
        "TokenType": "JWT",
    })
    if "Token" not in result:
        raise SystemExit("Xbox user auth failed: %s" % result.get("XErr", result.get("error")))
    return result["Token"]


def xsts(user_token, relying, device=None):
    properties = {"SandboxId": "RETAIL", "UserTokens": [user_token]}
    if device:
        properties["DeviceToken"] = device
    result = post("https://xsts.auth.xboxlive.com/xsts/authorize", payload={
        "Properties": properties,
        "RelyingParty": relying,
        "TokenType": "JWT",
    })
    if "Token" not in result:
        return None, result.get("XErr", result.get("error"))
    return result, None


def auth_header(doc):
    claim = doc["DisplayClaims"]["xui"][0]
    return "XBL3.0 x=%s;%s" % (claim["uhs"], doc["Token"]), claim


def write_tokens(fields):
    tmp = TOKEN_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        for key, value in fields:
            handle.write("%s=%s\n" % (key, value))
    os.chmod(tmp, 0o600)
    os.replace(tmp, TOKEN_PATH)


def desktop_env():
    env = os.environ.copy()
    env.setdefault("DISPLAY", ":0")
    env.setdefault("XDG_RUNTIME_DIR", "/run/user/%s" % os.getuid())
    return env


def show_code(url, code):
    with open(CODE_PATH, "w", encoding="utf-8") as handle:
        handle.write(url + "\n" + code + "\n")
    env = desktop_env()
    subprocess.Popen(["xdg-open", url], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    text = "Sign in with your Microsoft account.\n\nOpen %s\nCode: %s" % (url, code)
    if os.path.exists("/usr/bin/zenity"):
        subprocess.Popen(
            ["zenity", "--info", "--title=Minecraft Dungeons II sign-in", "--text", text, "--width=420"],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )


def poll_msa(device_code, interval, expires_in):
    deadline = time.time() + max(30, expires_in - 5)
    while time.time() < deadline:
        time.sleep(max(int(interval), 5))
        result = post("https://login.live.com/oauth20_token.srf", form={
            "client_id": CLIENT,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "device_code": device_code,
        })
        if "access_token" in result:
            return result
        err = result.get("error", "")
        if err == "slow_down":
            interval = int(interval) + 5
            continue
        if err == "authorization_pending":
            continue
        raise SystemExit("Microsoft login failed: %s" % (result.get("error_description") or err or result.get("_status")))
    raise SystemExit("Microsoft login timed out")


def refresh_msa(refresh):
    result = post("https://login.live.com/oauth20_token.srf", form={
        "client_id": CLIENT,
        "grant_type": "refresh_token",
        "refresh_token": refresh,
        "scope": SCOPE,
    })
    if "access_token" not in result:
        return None
    return result


def load_refresh():
    if not os.path.isfile(TOKEN_PATH):
        return None
    with open(TOKEN_PATH, "r", encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("refresh="):
                return line[len("refresh="):].rstrip("\n")
    return None


def finish(msa):
    user_token = xbox_user(msa["access_token"])
    xbox, xerr = xsts(user_token, "http://xboxlive.com")
    if not xbox:
        raise SystemExit("Xbox token failed: %s" % xerr)
    minecraft, mc_err = xsts(user_token, "rp://api.minecraftservices.com/")
    playfab, pf_err = xsts(user_token, PLAYFAB_RP, device_token())
    header, claim = auth_header(xbox)
    mc_header = auth_header(minecraft)[0] if minecraft else header
    pf_header = auth_header(playfab)[0] if playfab else ""
    exp = jwt_exp(xbox["Token"])
    for extra in (minecraft, playfab):
        if extra:
            extra_exp = jwt_exp(extra["Token"])
            if extra_exp:
                exp = min(exp, extra_exp) if exp else extra_exp
    if not exp:
        exp = int(time.time()) + 4 * 3600
    write_tokens([
        ("exp", str(exp)),
        ("xuid", claim.get("xid", "0")),
        ("uhs", claim.get("uhs", "")),
        ("gamertag", claim.get("gtg", "Player")),
        ("xbox", header),
        ("mc", mc_header),
        ("playfab", pf_header),
        ("msa", msa["access_token"]),
        ("refresh", msa.get("refresh_token", "")),
        ("mc_error", "" if minecraft else str(mc_err or "")),
        ("pf_error", "" if playfab else str(pf_err or "")),
    ])


def main():
    repair_stored_exp()
    if cached_ok():
        return
    refresh = load_refresh()
    if refresh:
        refreshed = refresh_msa(refresh)
        if refreshed:
            finish(refreshed)
            return
    started = post("https://login.live.com/oauth20_connect.srf", form={
        "client_id": CLIENT,
        "scope": SCOPE,
        "response_type": "device_code",
    })
    if "device_code" not in started:
        raise SystemExit("Could not start Microsoft login: %s" % started.get("error"))
    show_code(started.get("verification_uri") or "https://www.microsoft.com/link", started["user_code"])
    finish(poll_msa(started["device_code"], started.get("interval", 5), started.get("expires_in", 900)))


if __name__ == "__main__":
    try:
        main()
    except SystemExit as exc:
        if exc.code not in (0, None):
            with open(os.path.join(HERE, "login-error.txt"), "w", encoding="utf-8") as handle:
                handle.write(str(exc.code or exc)[:400])
        raise

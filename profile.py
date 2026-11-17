"""Read only public display fields from the selected Amnezia profile."""
import codecs
import json
import os
from pathlib import Path

result = {}
try:
    path = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "AmneziaVPN.ORG/AmneziaVPN.conf"
    if path.stat().st_size > 8 * 1024 * 1024:
        raise ValueError("oversized settings")
    values = dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line)
    raw = values["serversList"].removeprefix('"@ByteArray(').removesuffix(')"')
    servers = json.loads(codecs.decode(raw, "unicode_escape"))
    for server in servers:
        if server.get("storageServerId") != values.get("defaultServerId"):
            continue
        api = server.get("api_config", {})
        def clean(value):
            value = str(value)
            try:
                value = value.encode("latin1").decode("utf8")
            except UnicodeError:
                pass
            return " ".join(value.split())[:120]
        result = {"name": clean(server.get("name", "")), "country": clean(api.get("server_country_name", "")), "code": clean(api.get("server_country_code", ""))}
        break
except (OSError, ValueError, KeyError, TypeError, AttributeError):
    pass
print(json.dumps(result, ensure_ascii=False))

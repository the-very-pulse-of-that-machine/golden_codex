import argparse
import glob
import http.server
import json
import os
import re
import threading
from pathlib import Path


CONFIG_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = CONFIG_DIR.parent
PROJECT_THEME_SETTINGS = CONFIG_DIR / "theme-settings.json"
RUNTIME_CONFIG_DIR = Path.home() / ".codex" / "reasoning-theme"
THEME_SETTINGS = RUNTIME_CONFIG_DIR / "theme-settings.json"
PACKAGE_THEME_SETTINGS = (
    Path.home()
    / "AppData"
    / "Local"
    / "Packages"
    / "OpenAI.Codex_2p2nqsd0c76g0"
    / "LocalCache"
    / "reasoning-theme"
    / "theme-settings.json"
)
DEFAULT_SETTINGS = CONFIG_DIR / "theme-settings.default.json"
FLAT_SETTINGS = CONFIG_DIR / "settings_code2config.json"
EFFORTS = ("minimal", "low", "medium", "high", "xhigh", "max", "ultra")
MATERIALS = {"polished", "brushed", "satin", "carbon"}
HEX_COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")
THEME_ID = re.compile(r"^[a-z][a-z0-9-]{0,31}$")
WRITE_LOCK = threading.Lock()


def read_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def atomic_write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    with temp_path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    os.replace(temp_path, path)


def ensure_runtime_settings():
    if not THEME_SETTINGS.exists():
        source = PROJECT_THEME_SETTINGS if PROJECT_THEME_SETTINGS.exists() else DEFAULT_SETTINGS
        atomic_write_json(THEME_SETTINGS, read_json(source))
    atomic_write_json(PACKAGE_THEME_SETTINGS, read_json(THEME_SETTINGS))


def validate_theme_settings(settings):
    if not isinstance(settings, dict) or settings.get("version") != 1:
        raise ValueError("配置版本必须为 1")
    efforts = settings.get("efforts")
    themes = settings.get("themes")
    if not isinstance(efforts, dict) or not isinstance(themes, dict) or not themes:
        raise ValueError("档位映射和主题列表不能为空")

    for effort in EFFORTS:
        theme_id = efforts.get(effort, "none")
        if theme_id != "none" and theme_id not in themes:
            raise ValueError(f"档位 {effort} 引用了不存在的主题 {theme_id}")

    for theme_id, theme in themes.items():
        if not THEME_ID.fullmatch(theme_id):
            raise ValueError(f"主题 ID 无效: {theme_id}")
        if not isinstance(theme, dict):
            raise ValueError(f"主题 {theme_id} 必须是对象")
        if theme.get("material") not in MATERIALS:
            raise ValueError(f"主题 {theme_id} 的材质无效")
        for key in ("backgroundStart", "backgroundEnd", "surface", "accent", "text", "border"):
            if not HEX_COLOR.fullmatch(str(theme.get(key, ""))):
                raise ValueError(f"主题 {theme_id} 的 {key} 必须是 #RRGGBB")
        opacity = float(theme.get("textureOpacity", -1))
        angle = int(theme.get("shineAngle", -1))
        if not 0 <= opacity <= 0.6:
            raise ValueError(f"主题 {theme_id} 的纹理强度必须在 0 到 0.6 之间")
        if not 0 <= angle <= 360:
            raise ValueError(f"主题 {theme_id} 的光泽角度必须在 0 到 360 之间")


def sync_flat_settings(settings):
    primary_id = settings["efforts"].get("xhigh", "none")
    if primary_id == "none" or primary_id not in settings["themes"]:
        primary_id = next(iter(settings["themes"]))
    theme = settings["themes"][primary_id]
    assignments = ",".join(f"{effort}={settings['efforts'].get(effort, 'none')}" for effort in EFFORTS)
    flat = {
        "Theme.EffortAssignments": assignments,
        "Theme.Material": theme["material"],
        "Theme.BackgroundStart": theme["backgroundStart"],
        "Theme.BackgroundEnd": theme["backgroundEnd"],
        "Theme.AccentColor": theme["accent"],
        "Theme.TextColor": theme["text"],
        "Theme.TextureOpacity": theme["textureOpacity"],
        "Theme.ShineAngle": theme["shineAngle"],
    }
    atomic_write_json(FLAT_SETTINGS, flat)


class UIHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(CONFIG_DIR), **kwargs)

    def send_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/favicon.ico":
            self.send_response(204)
            self.end_headers()
            return
        if self.path == "/api/data":
            maps = []
            for path in sorted(glob.glob(str(CONFIG_DIR / "mental_map_*.json"))):
                maps.append(read_json(Path(path)))
            self.send_json(200, {
                "project": PROJECT_ROOT.name,
                "maps": maps,
                "settings": read_json(FLAT_SETTINGS),
                "themeSettings": read_json(THEME_SETTINGS),
                "defaults": read_json(DEFAULT_SETTINGS),
                "runtimeConfigPath": str(THEME_SETTINGS),
                "packageConfigPath": str(PACKAGE_THEME_SETTINGS),
            })
            return
        if self.path == "/api/health":
            self.send_json(200, {"ok": True, "project": PROJECT_ROOT.name})
            return
        super().do_GET()

    def do_POST(self):
        if self.path != "/api/update":
            self.send_json(404, {"ok": False, "error": "Not found"})
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > 1024 * 1024:
                raise ValueError("请求内容大小无效")
            request = json.loads(self.rfile.read(content_length).decode("utf-8"))
            if "theme_settings" in request:
                settings = request["theme_settings"]
                validate_theme_settings(settings)
                with WRITE_LOCK:
                    atomic_write_json(THEME_SETTINGS, settings)
                    atomic_write_json(PACKAGE_THEME_SETTINGS, settings)
                    sync_flat_settings(settings)
                self.send_json(200, {"ok": True, "themeSettings": settings})
                return
            if "var_id" in request:
                with WRITE_LOCK:
                    flat = read_json(FLAT_SETTINGS)
                    flat[request["var_id"]] = request.get("value")
                    atomic_write_json(FLAT_SETTINGS, flat)
                self.send_json(200, {"ok": True})
                return
            raise ValueError("请求缺少 theme_settings 或 var_id")
        except (ValueError, TypeError, json.JSONDecodeError) as error:
            self.send_json(400, {"ok": False, "error": str(error)})

    def log_message(self, format_string, *args):
        print(f"[theme-dashboard] {self.address_string()} {format_string % args}")


def run_ui(host, port):
    ensure_runtime_settings()
    server = http.server.ThreadingHTTPServer((host, port), UIHandler)
    print(f"[Code2Config] Theme dashboard: http://{host}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Codex reasoning theme configuration dashboard")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8002)
    arguments = parser.parse_args()
    run_ui(arguments.host, arguments.port)

#!/usr/bin/env python3
"""Interactive parameter customizer for a gmlewis/cad example.

Serves a small local web page (standard library only) with sliders built from
the example's own ``--help`` output. Moving a slider re-runs

    ./run-example.sh <example> --headless --release --package <dir>

and refreshes the 3D preview plus mass, CoM, torque-margin, and BOM metrics
read from the package's ``inspect.json``.

Usage:
    ./customize.sh 08
    python3 scripts/customize.py 8 --build-once --set scale=1.3
    python3 scripts/customize.py 08 --params-json
"""

from __future__ import annotations

import argparse
import glob
import http.server
import json
import math
import re
import subprocess
import sys
import threading
import time
import webbrowser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUN_EXAMPLE = ROOT / "run-example.sh"
BUILD_ROOT = Path("/tmp/cad-customize")

# Output paths and plumbing are not useful as sliders.
SKIP_FLAGS = {
    "help",
    "out",
    "assembly",
    "assembly-instanced",
    "eval",
    "gltf",
    "bpy",
    "blender",
    "blend",
    "urdf",
    "bundle",
    "bom",
    "plan",
    "report",
    "control",
    "pins",
    "package",
    "posed-parts",
    "print-parts",
    "detail",
    "threads",
    "bedSize",
    "validate",
    "validate-meshes",
    "check",
    "analyze",
    "collisions",
    "inspect-json",
    "explode",
}

OPTION_RE = re.compile(
    r"^\s{2,}(?:-(\w),\s*)?--([A-Za-z0-9-]+)(?:\s+<([^>]+)>)?\s{2,}(.+?)\s*$"
)
DEFAULT_RE = re.compile(r"\[default:\s*([^\]]+)\]")
RANGE_RE = re.compile(r"\(\s*(-?\d+(?:\.\d+)?)\s*\.\.\s*(-?\d+(?:\.\d+)?)")
REFERENCE_RE = re.compile(r"=\s*(\d+(?:\.\d+)?)\s*\*")
NUMBER_RE = re.compile(r"-?\d+(?:\.\d+)?")


def parse_help(text: str) -> list[dict]:
    """Extract numeric and enum options from an example's ``--help`` text."""
    params: list[dict] = []
    for line in text.splitlines():
        match = OPTION_RE.match(line)
        if not match:
            continue
        _short, name, metavar, help_text = match.groups()
        if name in SKIP_FLAGS:
            continue
        default_match = DEFAULT_RE.search(help_text)
        default_text = default_match.group(1).strip() if default_match else None
        help_clean = DEFAULT_RE.sub("", help_text).strip()
        number = None
        if default_text is not None:
            try:
                number = float(default_text)
            except ValueError:
                number = None
        if number is not None and metavar is not None:
            if number <= -900.0:
                # Sentinel defaults such as hipDeg = -999 disable the option.
                continue
            integer = is_integer_name(name)
            low, high, step = numeric_range(name, number, integer, help_clean)
            params.append(
                {
                    "name": name,
                    "help": help_clean,
                    "kind": "number",
                    "default": number,
                    "min": low,
                    "max": high,
                    "step": step,
                    "integer": integer,
                }
            )
            continue
        options = enum_options(help_clean)
        if options:
            params.append(
                {
                    "name": name,
                    "help": help_clean,
                    "kind": "enum",
                    "default": default_text or options[0],
                    "options": options,
                }
            )
    return params


def is_integer_name(name: str) -> bool:
    """Count-like options use integer steps; lengths and scales stay float."""
    return bool(
        re.fullmatch(r"num[A-Z].*|.*Teeth|.*Count|stages|segments|segs", name)
    )


def numeric_range(name: str, default: float, integer: bool, help_text: str):
    """Choose slider bounds from range hints, names, and reference values."""
    if name == "scale":
        low, high = 0.65, 2.0
    elif name == "tolerance":
        low, high = 0.02, 0.5
    else:
        hint = RANGE_RE.search(help_text)
        if hint:
            low, high = float(hint.group(1)), float(hint.group(2))
        elif name.lower().endswith("deg"):
            low, high = 0.0, 360.0
        else:
            low = 0.0
            reference = REFERENCE_RE.search(help_text)
            if default == 0.0 and reference:
                high = float(reference.group(1)) * 2.5
            elif default > 0.0:
                high = default * 2.0 if default > 1.0 else max(default * 4.0, 1.0)
            else:
                numbers = [float(number) for number in NUMBER_RE.findall(help_text)]
                high = max(numbers) * 2.5 if numbers else 1.0
    if integer:
        return math.floor(low), math.ceil(high), 1
    span = high - low
    if span >= 100:
        step = 1.0
    elif span >= 10:
        step = 0.5
    elif span >= 2:
        step = 0.05
    else:
        step = 0.001
    if name == "scale":
        step = 0.01
    return low, high, step


def enum_options(help_text: str) -> list[str]:
    """Parse ``preset: standing (default), crouched, tall, or pitched`` lists."""
    tail = help_text.split(":", 1)[1] if ":" in help_text else help_text
    tail = tail.split(";", 1)[0]
    parts = [
        part.strip()
        for part in re.split(r",\s*(?:or\s+)?|\s+or\s+", tail)
        if part.strip()
    ]
    options: list[str] = []
    for part in parts:
        token = part.replace("(default)", "").split(" (", 1)[0].strip().rstrip(".")
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", token):
            return []
        options.append(token)
    return options if len(options) >= 2 else []


def discover_example(argument: str) -> Path:
    """Resolve ``8``, ``08``, or a directory name to an examples/ path."""
    examples = ROOT / "examples"
    if re.fullmatch(r"\d+", argument):
        padded = f"{int(argument):02d}"
        matches = sorted(glob.glob(str(examples / f"{padded}-*")))
        matches += sorted(glob.glob(str(examples / f"{padded}_*")))
        if matches:
            return Path(matches[0])
        raise SystemExit(f"error: no example numbered {padded}")
    candidate = examples / argument
    if candidate.is_dir():
        return candidate
    raise SystemExit(f"error: example not found: {argument}")


def example_help(example: Path) -> str:
    """Run the example's own ``--help`` and return its text."""
    proc = subprocess.run(
        [str(RUN_EXAMPLE), example.name, "--", "--help"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise SystemExit(
            "error: could not read --help for "
            f"{example.name}:\n{proc.stderr.strip()}"
        )
    return proc.stdout


def format_number(value) -> str:
    number = float(value)
    if number.is_integer():
        return str(int(number))
    return f"{number:.6g}"


def build_command(
    example: Path, params: list[dict], values: dict, build_dir: Path
) -> list[str]:
    command = [
        str(RUN_EXAMPLE),
        example.name,
        "--headless",
        "--release",
        "--package",
        str(build_dir),
    ]
    for param in params:
        name = param["name"]
        value = values.get(name, param["default"])
        if param["kind"] == "number":
            number = float(value)
            if number < param["min"] or number > param["max"]:
                raise ValueError(
                    f"--{name}={format_number(number)} is outside "
                    f"[{format_number(param['min'])}, {format_number(param['max'])}]"
                )
            command += [
                "--" + name,
                format_number(int(round(number)) if param["integer"] else number),
            ]
        elif param["kind"] == "enum":
            if str(value) not in param["options"]:
                raise ValueError(f"--{name} must be one of {param['options']}")
            command += ["--" + name, str(value)]
    return command


def read_metrics(build_dir: Path) -> dict:
    path = build_dir / "inspect.json"
    if not path.is_file():
        return {}
    return json.loads(path.read_text())


_build_lock = threading.Lock()


def run_build(example: Path, params: list[dict], values: dict) -> dict:
    build_dir = BUILD_ROOT / example.name
    build_dir.mkdir(parents=True, exist_ok=True)
    try:
        command = build_command(example, params, values, build_dir)
    except ValueError as error:
        return {"ok": False, "error": str(error)}
    started = time.time()
    proc = subprocess.run(
        command,
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=1800,
    )
    elapsed = time.time() - started
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip().splitlines()[-12:]
        return {
            "ok": False,
            "error": "\n".join(detail) or "build failed",
            "command": command,
        }
    metrics = read_metrics(build_dir)
    return {
        "ok": True,
        "elapsed_s": round(elapsed, 1),
        "metrics": metrics,
        "view": f"/artifacts/preview.html?v={int(time.time() * 1000)}",
    }


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<style>
:root { color-scheme: light dark; --bg:#fbfbfd; --fg:#1d1d1f; --muted:#6e6e73; --accent:#0066cc; --soft:#e8f0fb; --border:#d2d2d7; --card:#ffffff; }
@media (prefers-color-scheme: dark) { :root { --bg:#111113; --fg:#e8e8ed; --muted:#a1a1a6; --accent:#7ab8ff; --soft:#1a2a3d; --border:#38383d; --card:#1a1a1d; } }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--fg); font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif; font-size:15px; }
header { padding:1rem 1.25rem; border-bottom:1px solid var(--border); display:flex; align-items:baseline; gap:1rem; flex-wrap:wrap; }
header h1 { margin:0; font-size:1.15rem; }
header p { margin:0; color:var(--muted); font-size:0.85rem; }
main { display:grid; grid-template-columns:320px minmax(0,1fr); gap:1rem; padding:1rem 1.25rem 2rem; align-items:start; }
.controls { border:1px solid var(--border); border-radius:10px; background:var(--card); padding:0.9rem; max-height:calc(100vh - 7rem); overflow:auto; }
.control { margin:0 0 0.9rem; }
.control label { display:flex; justify-content:space-between; gap:0.5rem; font-size:0.82rem; color:var(--muted); margin-bottom:0.2rem; }
.control .name { color:var(--fg); font-weight:600; font-family:ui-monospace,SFMono-Regular,Menlo,monospace; }
.control input[type=range] { width:100%; accent-color:var(--accent); }
.control input[type=number], .control select { width:100%; padding:0.3rem 0.4rem; border:1px solid var(--border); border-radius:6px; background:var(--bg); color:var(--fg); }
.control .help { color:var(--muted); font-size:0.75rem; margin-top:0.2rem; }
button { width:100%; padding:0.5rem; border:0; border-radius:8px; background:var(--accent); color:#fff; font-weight:600; cursor:pointer; }
button:disabled { opacity:0.55; cursor:default; }
.preview { border:1px solid var(--border); border-radius:10px; overflow:hidden; background:var(--card); }
.preview iframe { display:block; width:100%; height:min(62vh,560px); border:0; background:var(--bg); }
.metrics { display:grid; grid-template-columns:repeat(auto-fit,minmax(130px,1fr)); gap:0.6rem; padding:0.75rem; border-top:1px solid var(--border); }
.metric { background:var(--soft); border-radius:8px; padding:0.5rem 0.6rem; }
.metric .k { color:var(--muted); font-size:0.72rem; text-transform:uppercase; letter-spacing:0.04em; }
.metric .v { font-size:1rem; font-weight:650; margin-top:0.1rem; }
table { width:100%; border-collapse:collapse; font-size:0.78rem; margin-top:0.6rem; }
th, td { text-align:left; padding:0.25rem 0.35rem; border-bottom:1px solid var(--border); }
th { color:var(--muted); font-weight:600; }
.bad { color:#c0392b; font-weight:600; }
.good { color:#1e8449; }
#status { padding:0.4rem 0.75rem; border-top:1px solid var(--border); color:var(--muted); font-size:0.8rem; min-height:1.6rem; }
@media (max-width: 820px) { main { grid-template-columns:1fr; } .controls { max-height:none; } }
</style>
</head>
<body>
<header><h1>__TITLE__</h1><p>Move a control to rebuild the package and refresh the metrics.</p></header>
<main>
<section class="controls">
__CONTROLS__
<button id="rebuild">Rebuild</button>
</section>
<section class="preview">
<iframe id="preview" src="/artifacts/preview.html" title="Interactive 3D preview"></iframe>
<div class="metrics" id="metrics"></div>
<div id="status">Ready.</div>
</section>
</main>
<script>
const params = __PARAMS__;
const initialMetrics = __METRICS__;
const metricsEl = document.getElementById("metrics");
const statusEl = document.getElementById("status");
const previewEl = document.getElementById("preview");
const buttonEl = document.getElementById("rebuild");
let busy = false;
let timer = null;
function esc(text) { const div = document.createElement("div"); div.textContent = String(text ?? ""); return div.innerHTML; }
function collect() {
  const values = {};
  for (const p of params) {
    const input = document.querySelector(`[data-name="${p.name}"]`);
    values[p.name] = p.kind === "number" ? Number(input.value) : input.value;
  }
  return values;
}
function syncNumber(input) {
  const name = input.dataset.name;
  document.querySelectorAll(`[data-name="${name}"]`).forEach((peer) => { peer.value = input.value; });
}
function metric(label, value) { return `<div class="metric"><div class="k">${esc(label)}</div><div class="v">${esc(value)}</div></div>`; }
function renderMetrics(m) {
  if (!m || !m.total_mass_kg) { metricsEl.innerHTML = ""; return; }
  const com = (m.com_m || []).map((v) => Number(v).toFixed(3)).join(", ");
  const inertia = m.inertia_kgm2 || {};
  const bom = m.bom || {};
  const interference = m.interference_summary || {};
  let html = "";
  html += metric("Mass", Number(m.total_mass_kg).toFixed(3) + " kg");
  html += metric("CoM", "(" + com + ") m");
  html += metric("Iyy", Number(inertia.iyy || 0).toFixed(4) + " kg m²");
  html += metric("BOM", (bom.lines ?? 0) + " lines · $" + Number(bom.estimated_cost_usd || 0).toFixed(2));
  html += metric("Collisions", interference.collisions ?? 0);
  const margins = m.torque_margins || [];
  if (margins.length) {
    html += `<table><thead><tr><th>Joint</th><th>Static Nm</th><th>Rated Nm</th><th>Safety</th><th></th></tr></thead><tbody>`;
    for (const row of margins) {
      if (row.joint.endsWith("_rotor_joint")) continue;
      html += `<tr><td>${esc(row.joint)}</td><td>${Number(row.tau_static_nm).toFixed(2)}</td><td>${Number(row.tau_rated_nm).toFixed(1)}</td><td>${Number(row.safety_factor).toFixed(1)}</td><td class="${row.ok ? "good" : "bad"}">${row.ok ? "OK" : "LOW"}</td></tr>`;
    }
    html += "</tbody></table>";
  }
  metricsEl.innerHTML = html;
}
async function build() {
  if (busy) return;
  busy = true;
  buttonEl.disabled = true;
  statusEl.textContent = "Building…";
  try {
    const response = await fetch("/api/build", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(collect()),
    });
    const data = await response.json();
    if (data.ok) {
      renderMetrics(data.metrics);
      previewEl.src = data.view;
      statusEl.textContent = "Built in " + data.elapsed_s + " s.";
    } else {
      statusEl.textContent = "Build failed: " + data.error;
    }
  } catch (error) {
    statusEl.textContent = "Build failed: " + error;
  } finally {
    busy = false;
    buttonEl.disabled = false;
  }
}
function queueBuild() { clearTimeout(timer); timer = setTimeout(build, 300); }
document.querySelectorAll(".control input[type=range], .control input[type=number], .control select").forEach((input) => {
  input.addEventListener("input", () => {
    syncNumber(input);
    const out = document.querySelector(`[data-out="${input.dataset.name}"]`);
    if (out) out.textContent = input.value;
  });
  input.addEventListener("change", queueBuild);
});
buttonEl.addEventListener("click", build);
renderMetrics(initialMetrics);
</script>
</body>
</html>
"""


def control_html(param: dict) -> str:
    name = param["name"]
    label = f'<span class="name">--{name}</span><span data-out="{name}">{esc_text(param["default"])}</span>'
    help_text = f'<div class="help">{esc_text(param["help"])}</div>'
    if param["kind"] == "enum":
        options = "".join(
            f'<option value="{opt}"{" selected" if opt == str(param["default"]) else ""}>{opt}</option>'
            for opt in param["options"]
        )
        return (
            f'<div class="control"><label>{label}</label>'
            f'<select data-name="{name}">{options}</select>{help_text}</div>'
        )
    low = format_number(param["min"])
    high = format_number(param["max"])
    step = format_number(param["step"])
    value = format_number(param["default"])
    return (
        f'<div class="control"><label>{label}</label>'
        f'<input type="range" data-name="{name}" min="{low}" max="{high}" step="{step}" value="{value}">'
        f'<input type="number" data-name="{name}" min="{low}" max="{high}" step="{step}" value="{value}">'
        f"{help_text}</div>"
    )


def esc_text(text) -> str:
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def page_html(example: Path, params: list[dict], metrics: dict) -> str:
    controls = "\n".join(control_html(param) for param in params)
    return (
        PAGE.replace("__TITLE__", f"Customize {example.name}")
        .replace("__CONTROLS__", controls)
        .replace("__PARAMS__", json.dumps(params))
        .replace("__METRICS__", json.dumps(metrics))
    )


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(BUILD_DIR), **kwargs)

    def log_message(self, fmt, *args):
        sys.stderr.write("customize: " + (fmt % args) + "\n")

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            body = PAGE_HTML.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path.startswith("/artifacts/"):
            # Serve the built package at /artifacts/... so preview.html's
            # relative assembly.gltf and views/ URLs resolve inside it.
            self.path = self.path[len("/artifacts") :]
        super().do_GET()

    def do_POST(self):
        if self.path != "/api/build":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0") or 0)
        try:
            values = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            values = {}
        with _build_lock:
            result = run_build(EXAMPLE, PARAMS, values)
        body = json.dumps(result).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


BUILD_DIR = BUILD_ROOT / "default"
EXAMPLE = ROOT / "examples"
PARAMS: list[dict] = []
PAGE_HTML = ""


def main() -> None:
    global BUILD_DIR, EXAMPLE, PARAMS, PAGE_HTML
    parser = argparse.ArgumentParser(
        description="Local web customizer for a gmlewis/cad example."
    )
    parser.add_argument("example", help="Example number, name, or directory")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument(
        "--no-build", action="store_true", help="Serve without rebuilding first"
    )
    parser.add_argument(
        "--params-json",
        action="store_true",
        help="Print the parsed parameter schema and exit",
    )
    parser.add_argument(
        "--build-once",
        action="store_true",
        help="Build once with the given --set values and print the metrics",
    )
    parser.add_argument(
        "--set",
        action="append",
        default=[],
        metavar="NAME=VALUE",
        help="Override a parameter for --build-once (repeatable)",
    )
    parser.add_argument(
        "--no-open", action="store_true", help="Do not open a browser"
    )
    args = parser.parse_args()

    EXAMPLE = discover_example(args.example)
    PARAMS = parse_help(example_help(EXAMPLE))
    BUILD_DIR = BUILD_ROOT / EXAMPLE.name

    if args.params_json:
        print(json.dumps(PARAMS, indent=2))
        return

    values = {param["name"]: param["default"] for param in PARAMS}
    for assignment in args.set:
        name, _, raw = assignment.partition("=")
        param = next((p for p in PARAMS if p["name"] == name), None)
        if param is None:
            raise SystemExit(f"error: unknown parameter: {name}")
        values[name] = raw if param["kind"] == "enum" else float(raw)

    if args.build_once:
        result = run_build(EXAMPLE, PARAMS, values)
        print(json.dumps(result, indent=2))
        raise SystemExit(0 if result.get("ok") else 1)

    metrics = {}
    if not args.no_build:
        print(f"customize: building {EXAMPLE.name} …", file=sys.stderr)
        result = run_build(EXAMPLE, PARAMS, values)
        if result.get("ok"):
            metrics = result.get("metrics", {})
        else:
            print(f"customize: initial build failed: {result['error']}", file=sys.stderr)
    else:
        metrics = read_metrics(BUILD_DIR)

    PAGE_HTML = page_html(EXAMPLE, PARAMS, metrics)
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{server.server_address[1]}/"
    print(f"Customizing {EXAMPLE.name} at {url}", file=sys.stderr)
    print("Press Ctrl-C to stop.", file=sys.stderr)
    if not args.no_open:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()

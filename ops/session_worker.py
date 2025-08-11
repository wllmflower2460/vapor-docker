#!/usr/bin/env python3
"""
Session Worker Script
----------------------

Watches the /home/pi/appdata/sessions directory for new sessions
(video.mp4 exists but results.json does not) and runs hailortcli benchmark
on the detected HEF model.

Writes results.json with:
  - status (ok/error)
  - session name
  - timestamp
  - HEF path + model name
  - duration_sec (benchmark runtime)
  - parsed metrics (FPS, latency)
  - raw_tail (ANSI-stripped output tail)

Now includes atomic writes for results.json to prevent partial files.
"""

import time
import json
import subprocess
import pathlib
import os
import re
import sys

# Path where session directories live
SESSIONS = pathlib.Path("/home/pi/appdata/sessions")

# Optional override from environment
HEF_ENV = os.environ.get("HEF_PATH")

# Scan interval in seconds
INTERVAL = 2

# Regex to strip ANSI escape codes from CLI output
ANSI = re.compile(r'\x1B\[[0-?]*[ -/]*[@-~]')


def find_hef():
    """Locate a .hef model file, checking env override, known paths, then searching."""
    if HEF_ENV and pathlib.Path(HEF_ENV).exists():
        return HEF_ENV

    candidates = [
        "/opt/hailo/models/sample.hef",
        "/usr/local/hailo/resources/models/hailo8/yolov5m_seg.hef",
    ]
    for c in candidates:
        if pathlib.Path(c).exists():
            return c

    try:
        out = subprocess.run(
            [
                "bash", "-lc",
                "find /usr/local/hailo/resources/models /opt/hailo "
                "-type f -name '*.hef' 2>/dev/null | head -n1"
            ],
            capture_output=True, text=True, check=False
        ).stdout.strip()
        return out or None
    except Exception:
        return None


def parse_benchmark(text: str):
    """Parse FPS and latency metrics from hailortcli output."""
    r_hw_only = re.search(r"FPS\s*\(hw_only\)\s*=\s*([0-9.]+)", text)
    r_stream  = re.search(r"\(streaming\)\s*=\s*([0-9.]+)", text)
    r_lat     = re.search(r"Latency\s*\(hw\)\s*=\s*([0-9.]+)\s*ms", text)
    return {
        "fps_hw_only": float(r_hw_only.group(1)) if r_hw_only else None,
        "fps_streaming": float(r_stream.group(1)) if r_stream else None,
        "latency_ms": float(r_lat.group(1)) if r_lat else None,
    }


def _tail(text: str, n: int) -> str:
    """Return last n lines of text, or empty string if None."""
    return "\n".join((text or "").strip().splitlines()[-n:])


def _write_json_atomic(path: pathlib.Path, data: dict):
    """
    Write JSON atomically:
      - Write to <path>.tmp
      - Rename to final path
    Ensures partial writes never overwrite a good file.
    """
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text(json.dumps(data, indent=2))
    tmp_path.replace(path)


def run_for_session(sdir: pathlib.Path):
    """Run benchmark for given session directory and write atomic results.json."""
    hef = find_hef()
    result = {
        "status": "starting",
        "session": sdir.name,
        "ts": time.time(),
        "hef": hef
    }

    if not hef:
        result.update(status="error", error="No HEF found", raw_tail="")
        _write_json_atomic(sdir / "results.json", result)
        return

    # Wait for video.mp4 to settle (size check)
    v = sdir / "video.mp4"
    try:
        s1 = v.stat().st_size
        time.sleep(1.0)
        s2 = v.stat().st_size
        if s2 != s1:
            time.sleep(1.0)
    except FileNotFoundError:
        pass

    start = time.time()
    try:
        bench = subprocess.run(
            ["hailortcli", "benchmark", "-t", "5", hef],
            capture_output=True, text=True, check=True
        )
        dur = time.time() - start
        tail = _tail(bench.stdout, 12)
        clean_tail = ANSI.sub("", tail)
        summary = parse_benchmark(bench.stdout)

        result.update(
            status="ok",
            summary=summary,
            raw_tail=clean_tail,
            model=pathlib.Path(hef).stem,
            duration_sec=round(dur, 2),
        )

    except subprocess.CalledProcessError as e:
        dur = time.time() - start
        stdout_tail = _tail(e.stdout or "", 20)
        result.update(
            status="error",
            error="benchmark failed",
            stderr=ANSI.sub("", e.stderr or ""),
            raw_tail=ANSI.sub("", stdout_tail),
            model=pathlib.Path(hef).stem,
            duration_sec=round(dur, 2),
        )

    except Exception as e:
        dur = time.time() - start
        result.update(
            status="error",
            error=str(e),
            raw_tail="",
            model=pathlib.Path(hef).stem,
            duration_sec=round(dur, 2),
        )

    _write_json_atomic(sdir / "results.json", result)


def main():
    """Main loop watching sessions dir for new work."""
    if not SESSIONS.exists():
        print(f"missing {SESSIONS}", file=sys.stderr)
        sys.exit(1)

    print("Worker watching:", SESSIONS)
    while True:
        try:
            for sdir in SESSIONS.iterdir():
                if not sdir.is_dir():
                    continue
                if (sdir / "video.mp4").exists() and not (sdir / "results.json").exists():
                    run_for_session(sdir)
        except Exception as e:
            print("loop error:", e, file=sys.stderr)

        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()

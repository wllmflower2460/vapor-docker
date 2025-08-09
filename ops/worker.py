#!/usr/bin/env python3
import time, json, subprocess, pathlib, os, re, sys

SESSIONS = pathlib.Path("/home/pi/appdata/sessions")
HEF_ENV = os.environ.get("HEF_PATH")  # optional override from systemd
INTERVAL = 2  # seconds between scans

def find_hef():
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
            ["bash","-lc","find /usr/local/hailo/resources/models /opt/hailo -type f -name '*.hef' 2>/dev/null | head -n1"],
            capture_output=True, text=True, check=False
        ).stdout.strip()
        return out or None
    except Exception:
        return None

def parse_benchmark(text: str):
    # Expect lines after "Summary"
    r_hw_only = re.search(r"FPS\s*\(hw_only\)\s*=\s*([0-9.]+)", text)
    r_stream  = re.search(r"\(streaming\)\s*=\s*([0-9.]+)", text)
    r_lat     = re.search(r"Latency\s*\(hw\)\s*=\s*([0-9.]+)\s*ms", text)
    return {
        "fps_hw_only": float(r_hw_only.group(1)) if r_hw_only else None,
        "fps_streaming": float(r_stream.group(1)) if r_stream else None,
        "latency_ms": float(r_lat.group(1)) if r_lat else None,
    }

def run_for_session(sdir: pathlib.Path):
    hef = find_hef()
    result = {"status":"starting", "session": sdir.name, "ts": time.time(), "hef": hef}
    if not hef:
        result.update(status="error", error="No HEF found")
        (sdir/"results.json").write_text(json.dumps(result, indent=2))
        return

    # Wait for video.mp4 to settle
    v = sdir/"video.mp4"
    try:
        s1 = v.stat().st_size
        time.sleep(1.0)
        s2 = v.stat().st_size
        if s2 != s1:
            time.sleep(1.0)
    except FileNotFoundError:
        pass

    try:
        bench = subprocess.run(
            ["hailortcli","benchmark","-t","5", hef],
            capture_output=True, text=True, check=True
        )
        summary = parse_benchmark(bench.stdout)
        result.update(status="ok",
                      summary=summary,
                      raw_tail="\n".join(bench.stdout.strip().splitlines()[-12:]))
    except subprocess.CalledProcessError as e:
        result.update(status="error",
                      error="benchmark failed",
                      stderr=e.stderr,
                      stdout_tail="\n".join(e.stdout.strip().splitlines()[-20:] if e.stdout else []))
    except Exception as e:
        result.update(status="error", error=str(e))

    (sdir/"results.json").write_text(json.dumps(result, indent=2))

def main():
    if not SESSIONS.exists():
        print(f"missing {SESSIONS}", file=sys.stderr); sys.exit(1)
    print("Worker watching:", SESSIONS)
    while True:
        try:
            for sdir in SESSIONS.iterdir():
                if not sdir.is_dir():
                    continue
                if (sdir/"video.mp4").exists() and not (sdir/"results.json").exists():
                    run_for_session(sdir)
        except Exception as e:
            print("loop error:", e, file=sys.stderr)
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()

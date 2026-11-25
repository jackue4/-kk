"""网页版跑 PvP 锁定描边自检（scripts/pvp_outline_selftest.gd）：无界面 Edge（独立临时配置目录、调试端口 9394），手机横屏模拟（740×360、2 倍像素比、触屏），
打开带 args 的探针页，收控制台；见到「[pvpline] shot <名字>」就用调试协议截一张屏（游戏那边会停 0.7 秒等着），见到「[pvpline] 完」结束。
用法：python -I web_pvp_probe.py <探针页地址> <输出目录>
"""
import asyncio
import base64
import json
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

import websockets

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
PORT = 9394


async def main():
    url, out = sys.argv[1], Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    prof = tempfile.mkdtemp(prefix="xian_pvpline_")
    proc = subprocess.Popen([EDGE, "--headless=new", f"--remote-debugging-port={PORT}", f"--user-data-dir={prof}", "--window-size=1280,720",
                             "--mute-audio", "--no-first-run", "--no-default-browser-check", "--use-angle=d3d11", "--ignore-gpu-blocklist",
                             "--disable-background-timer-throttling", "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows",
                             "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    lines = []
    try:
        ws_url = None
        for _ in range(80):
            try:
                tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json", timeout=1))
                pg = [t for t in tabs if t.get("type") == "page"]
                if pg:
                    ws_url = pg[0]["webSocketDebuggerUrl"]
                    break
            except Exception:
                pass
            time.sleep(0.25)
        async with websockets.connect(ws_url, max_size=None) as ws:
            mid = 0
            waiters = {}

            async def call(method, params=None):
                nonlocal mid
                mid += 1
                fut = asyncio.get_event_loop().create_future()
                waiters[mid] = fut
                await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
                return await asyncio.wait_for(fut, 60)

            queue = asyncio.Queue()

            async def pump():
                async for raw in ws:
                    m = json.loads(raw)
                    if "id" in m and m["id"] in waiters:
                        waiters.pop(m["id"]).set_result(m)
                    elif m.get("method"):
                        await queue.put(m)

            task = asyncio.create_task(pump())
            await call("Runtime.enable")
            await call("Emulation.setDeviceMetricsOverride", {"width": 740, "height": 360, "deviceScaleFactor": 2, "mobile": True,
                                                              "screenOrientation": {"type": "landscapePrimary", "angle": 90}})
            await call("Emulation.setTouchEmulationEnabled", {"enabled": True, "maxTouchPoints": 5})
            await call("Page.enable")
            await call("Page.navigate", {"url": url})
            t0 = time.time()
            done = False
            while time.time() - t0 < 600 and not done:
                try:
                    m = await asyncio.wait_for(queue.get(), 2.0)
                except asyncio.TimeoutError:
                    continue
                text = None
                if m["method"] == "Runtime.consoleAPICalled":
                    p = m["params"]
                    text = " ".join(str(a.get("value", a.get("description", ""))) for a in p.get("args", []))
                    if p.get("type") in ("error", "warning"):
                        text = f"<{p['type']}> " + text
                elif m["method"] == "Runtime.exceptionThrown":
                    text = "<exception> " + json.dumps(m["params"].get("exceptionDetails", {}), ensure_ascii=False)[:400]
                if text is None:
                    continue
                lines.append("%6.1fs %s" % (time.time() - t0, text))
                if "[pvpline] shot " in text:
                    tag = text.split("[pvpline] shot ", 1)[1].strip()
                    r = await call("Page.captureScreenshot", {"format": "jpeg", "quality": 88})
                    (out / f"web_{tag}.jpg").write_bytes(base64.b64decode(r["result"]["data"]))
                if "[pvpline] 完" in text:
                    done = True
            lines.append("[probe] %s，用时 %.0fs" % ("见到结束标记" if done else "超时", time.time() - t0))
            task.cancel()
    finally:
        (out / "web_pvp_log.txt").write_text("\n".join(lines), encoding="utf-8")
        time.sleep(1.0)
        if proc.poll() is None:
            proc.kill()
    errs = [l for l in lines if "SCRIPT ERROR" in l or "<exception>" in l]
    sys.stdout.buffer.write(("\n".join(l for l in lines if "[pvpline]" in l or "[probe]" in l) + "\nSCRIPT ERROR / 异常 %d 条\n" % len(errs)).encode("utf-8"))


asyncio.run(main())

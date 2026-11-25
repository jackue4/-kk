"""网页版滑屏转镜头的量测 + 触屏回归（2026-11-21，只读测试）。
用本机无界面 Edge（独立临时配置目录、调试端口 9393，不碰用户浏览器，也不和别的会话的 9377 / 9391 撞），
按手机横屏模拟（740×360 CSS 像素、2 倍像素比、触屏），打开本地导出的网页包（地址带 ?ttdbg：触控层每画完一帧把 yaw / 画面朝向记进 window.__gdf），
用调试协议的 Input.dispatchTouchEvent 发真实的浏览器触摸事件（走浏览器 → 引擎网页层 → touch_controls.gd 的完整链路）。
同一个页面里 window.__ttraw = true / false 交替跑同一套滑动（改之前 / 现在），再做几项触屏回归（双指缩放、抬指续转、摇杆并用）。
用法：python -I web_touch_probe.py <页面地址> <输出目录>
输出：web_frames.csv（逐帧）、web_touch_log.txt（控制台 + 回归结果）
"""
import asyncio
import json
import math
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

import websockets

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
PORT = 9393
W, H, DPR = 740, 360, 2.0


def wrapd(a):
    """两个角度差：换算到 -π~π（画面朝向是欧拉角，会绕圈；yaw 是一直累加的）"""
    return (a + math.pi) % (2 * math.pi) - math.pi


class Cdp:
    def __init__(self, ws):
        self.ws = ws
        self.mid = 0
        self.waiters = {}
        self.events = []

    async def pump(self):
        async for raw in self.ws:
            msg = json.loads(raw)
            if "id" in msg and msg["id"] in self.waiters:
                self.waiters.pop(msg["id"]).set_result(msg)
            elif "method" in msg:
                self.events.append(msg)

    async def call(self, method, params=None):
        self.mid += 1
        fut = asyncio.get_event_loop().create_future()
        self.waiters[self.mid] = fut
        await self.ws.send(json.dumps({"id": self.mid, "method": method, "params": params or {}}))
        return await asyncio.wait_for(fut, 30)

    async def js(self, expr):
        r = await self.call("Runtime.evaluate", {"expression": expr, "returnByValue": True})
        return r.get("result", {}).get("result", {}).get("value")

    async def touch(self, kind, pts, wait=True):
        params = {"type": kind, "touchPoints": [
            {"x": float(x), "y": float(y), "id": int(i), "radiusX": 4, "radiusY": 4, "force": 1} for i, x, y in pts]}
        if wait:
            await self.call("Input.dispatchTouchEvent", params)
            return
        # 不等页面确认：按时刻直接发（等确认的话发送节奏会被页面帧率拖住，变成十几赫兹）
        self.mid += 1
        await self.ws.send(json.dumps({"id": self.mid, "method": "Input.dispatchTouchEvent", "params": params}))


def console_lines(cdp):
    out = []
    for m in cdp.events:
        if m.get("method") == "Runtime.consoleAPICalled":
            p = m["params"]
            out.append(" ".join(str(a.get("value", a.get("description", ""))) for a in p.get("args", [])))
        elif m.get("method") == "Runtime.exceptionThrown":
            out.append("<exception> " + json.dumps(m["params"].get("exceptionDetails", {}), ensure_ascii=False)[:400])
    return out


async def swipe(cdp, name, vx, rate, dur, quant=False, y=180.0, x0=470.0):
    """一根手指在镜头区（右半屏）按 vx CSS 像素/秒 滑 dur 秒，rate Hz 发 touchMove；返回发送记录（页面时间, x）"""
    log = []
    t_page0 = await cdp.js("performance.now()")
    t0 = time.perf_counter()
    await cdp.touch("touchStart", [(1, x0, y)])
    log.append((t_page0, x0))
    await asyncio.sleep(0.15)
    tm0 = time.perf_counter()
    n = 1
    while True:
        target = tm0 + n / rate
        now = time.perf_counter()
        if target > now:
            await asyncio.sleep(target - now)
        t = time.perf_counter() - tm0
        if t > dur:
            t = dur
        x = x0 + vx * t
        if quant:
            x = math.floor(x)
        await cdp.touch("touchMove", [(1, x, y)], wait=False)
        log.append((t_page0 + (time.perf_counter() - t0) * 1000.0, x))
        if t >= dur:
            break
        n += 1
    await asyncio.sleep(0.45)
    await cdp.touch("touchEnd", [])
    await asyncio.sleep(0.3)
    return log


async def main():
    url, outdir = sys.argv[1], Path(sys.argv[2])
    outdir.mkdir(parents=True, exist_ok=True)
    prof = tempfile.mkdtemp(prefix="xian_touchcam_")
    args = [EDGE, "--headless=new", f"--remote-debugging-port={PORT}", f"--user-data-dir={prof}", "--window-size=1280,720",
            "--mute-audio", "--no-first-run", "--no-default-browser-check", "--use-angle=d3d11", "--ignore-gpu-blocklist",
            "--disable-background-timer-throttling", "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows", "about:blank"]
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    report = []
    frames = []
    try:
        ws_url = None
        for _ in range(80):
            try:
                tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json", timeout=1))
                page = [t for t in tabs if t.get("type") == "page"]
                if page:
                    ws_url = page[0]["webSocketDebuggerUrl"]
                    break
            except Exception:
                pass
            time.sleep(0.25)
        if ws_url is None:
            print("浏览器没起来")
            return
        async with websockets.connect(ws_url, max_size=None) as ws:
            cdp = Cdp(ws)
            pump = asyncio.create_task(cdp.pump())
            await cdp.call("Runtime.enable")
            await cdp.call("Emulation.setDeviceMetricsOverride", {"width": W, "height": H, "deviceScaleFactor": DPR, "mobile": True,
                                                                  "screenOrientation": {"type": "landscapePrimary", "angle": 90}})
            await cdp.call("Emulation.setTouchEmulationEnabled", {"enabled": True, "maxTouchPoints": 5})
            await cdp.call("Page.enable")
            await cdp.call("Page.navigate", {"url": url})
            t0 = time.time()
            ready = False
            while time.time() - t0 < 300:
                await asyncio.sleep(1.0)
                g = await cdp.js("window.__gds||''")
                n = await cdp.js("(window.__gdf||[]).length")
                if g and n and n > 200:
                    ready = True
                    break
            report.append("[web] 载入 %s，用时 %.0fs，ontouchstart=%s" % ("完成" if ready else "超时", time.time() - t0, await cdp.js("'ontouchstart' in window")))
            if not ready:
                return
            await asyncio.sleep(8.0)      # 等预热 / 幕布退完
            # 帧率
            fr = await cdp.js("(()=>{const a=window.__gdf||[];const b=a.slice(-120);let d=[];for(let i=1;i<b.length;i++)d.push(b[i][0]-b[i-1][0]);d.sort((x,y)=>x-y);return d.length?[d[Math.floor(d.length/2)],d[d.length-1]]:null})()")
            report.append("[web] 最近 120 帧帧长 中位 %.1fms 最长 %.1fms" % (fr[0], fr[1]) if fr else "[web] 没有帧数据")
            scen = [("mid60", 200.0, 60.0, 0.9, False), ("slow60q", 40.0, 60.0, 1.2, True), ("fast60", 450.0, 60.0, 0.6, False),
                    ("mid30", 200.0, 30.0, 0.9, False)]
            sent_log = {}
            for name, vx, rate, dur, q in scen:
                for mode in ("raw", "new"):
                    await cdp.js("window.__ttraw=%s" % ("true" if mode == "raw" else "false"))
                    await asyncio.sleep(0.4)
                    await cdp.js("window.__gdf=[]")
                    log = await swipe(cdp, name, vx, rate, dur, q)
                    rows = await cdp.js("window.__gdf")
                    sent_log[(name, mode)] = log
                    for r in rows:
                        frames.append([name, mode] + r)
                    yaw0 = rows[0][1] if rows else 0.0
                    yaw1 = rows[-1][1] if rows else 0.0
                    report.append("[web] %s %s：发了 %d 次 touchMove，%d 帧，yaw 转 %.4f，最后画面和 yaw 差 %.6f" % (name, mode, len(log) - 1, len(rows),
                                  yaw1 - yaw0, wrapd(rows[-1][2] - rows[-1][1]) if rows else 0.0))
            await cdp.js("window.__ttraw=false")
            # 回归：双指缩放 → 先抬转镜头那根 → 留下那根接着转；摇杆 + 转镜头
            await cdp.js("window.__gdf=[]")
            await cdp.touch("touchStart", [(1, 470, 170)])
            await asyncio.sleep(0.1)
            await cdp.touch("touchStart", [(1, 470, 170), (2, 560, 170)])
            await asyncio.sleep(0.1)
            g0 = await cdp.js("window.__gdf.slice(-1)[0]")
            for k in range(10):
                await cdp.touch("touchMove", [(1, 470, 170), (2, 560 + 8 * (k + 1), 170)])
                await asyncio.sleep(1 / 60)
            await asyncio.sleep(0.6)
            g1 = await cdp.js("window.__gdf.slice(-1)[0]")
            ok_pinch = g1[6] < g0[6] - 0.5 and abs(g1[1] - g0[1]) < 1e-4
            if abs(g1[6] - g0[6]) < 1e-3:
                report.append("[web] 说明 这一版没有双指缩放（第二根手指接管转镜头，是测试专项 BUG-08 之前的行为）：zoom %.2f → %.2f，yaw 变 %.4f，画面和 yaw 差 %.6f" % (
                    g0[6], g1[6], g1[1] - g0[1], wrapd(g1[2] - g1[1])))
            else:
                report.append("[web] %s 双指张开拉近、期间不转：zoom %.2f → %.2f，yaw 变 %.5f" % ("通过" if ok_pinch else "不通过", g0[6], g1[6], g1[1] - g0[1]))
            await cdp.touch("touchEnd", [(2, 640, 170)])        # 抬起转镜头那根（1），留下 2
            await asyncio.sleep(0.1)
            g2 = await cdp.js("window.__gdf.slice(-1)[0]")
            n2 = await cdp.js("window.__gdf.length")
            for k in range(12):
                await cdp.touch("touchMove", [(2, 640 - 5 * (k + 1), 170)])
                await asyncio.sleep(1 / 60)
            await asyncio.sleep(0.3)
            seg = await cdp.js("window.__gdf.slice(%d)" % n2)
            g3 = seg[-1]
            steps = [abs(wrapd(seg[i][2] - seg[i - 1][2])) for i in range(1, len(seg))]
            mv = [s for s in steps if s > 1e-6]
            avg = sum(mv) / len(mv) if mv else 0.0
            ok_lift = abs(g3[1] - g2[1]) > 0.05 and abs(wrapd(g3[2] - g3[1])) < 1e-4 and g3[5] == 1 and (max(steps) if steps else 0) < 2.5 * max(avg, 1e-6)
            report.append("[web] %s 抬起转镜头那根、留下那根接着转：yaw 转 %.4f，画面最后和 yaw 差 %.6f，画面每帧最大一步 %.4f（平均 %.4f）" % (
                "通过" if ok_lift else "不通过", g3[1] - g2[1], wrapd(g3[2] - g3[1]), max(steps) if steps else 0, avg))
            await cdp.touch("touchEnd", [])
            await asyncio.sleep(0.3)
            # 摇杆（左半屏下方）+ 镜头同时
            st0 = await cdp.js("window.__gds")
            await cdp.touch("touchStart", [(3, 120, 270)])
            await asyncio.sleep(0.1)
            await cdp.touch("touchMove", [(3, 170, 270)])
            await asyncio.sleep(0.1)
            await cdp.touch("touchStart", [(3, 170, 270), (4, 500, 170)])
            await asyncio.sleep(0.1)
            g4 = await cdp.js("window.__gdf.slice(-1)[0]")
            for k in range(12):
                await cdp.touch("touchMove", [(3, 170, 270 + (k % 3)), (4, 500 + 6 * (k + 1), 170)])
                await asyncio.sleep(1 / 60)
            await asyncio.sleep(0.3)
            st1 = await cdp.js("window.__gds")
            g5 = await cdp.js("window.__gdf.slice(-1)[0]")
            sp = st1.split("|")
            ok_stick = sp[0] == "1" and float(sp[2]) > 0.3 and abs(g5[1] - g4[1]) > 0.05 and abs(wrapd(g5[2] - g5[1])) < 1e-4
            report.append("[web] %s 摇杆和转镜头同时动：摇杆 %s 横向 %s，yaw 转 %.4f，画面和 yaw 差 %.6f" % ("通过" if ok_stick else "不通过", sp[0], sp[2], g5[1] - g4[1], wrapd(g5[2] - g5[1])))
            await cdp.touch("touchEnd", [])
            await asyncio.sleep(0.4)
            st2 = await cdp.js("window.__gds")
            ok_rel = st2.split("|")[0] == "0" and st2.split("|")[1] == "0"
            report.append("[web] %s 全部抬起后摇杆 / 镜头都松开：%s" % ("通过" if ok_rel else "不通过", st2))
            cons = console_lines(cdp)
            errs = [c for c in cons if "SCRIPT ERROR" in c or "<exception>" in c]
            report.append("[web] 控制台 %d 行，SCRIPT ERROR / 异常 %d 条" % (len(cons), len(errs)))
            report += ["  " + c for c in errs[:20]]
            (outdir / "web_console.txt").write_text("\n".join(cons), encoding="utf-8")
            with open(outdir / "web_sent.json", "w", encoding="utf-8") as f:
                json.dump({"%s|%s" % k: v for k, v in sent_log.items()}, f)
            pump.cancel()
            try:
                await cdp.call("Browser.close")
            except Exception:
                pass
    finally:
        with open(outdir / "web_frames.csv", "w", encoding="utf-8") as f:
            f.write("scene,mode,t_ms,yaw,view_yaw,pitch,view_pitch,look_on,zoom,pinch,eng_dt\n")
            for r in frames:
                f.write(",".join(str(x) for x in r) + "\n")
        (outdir / "web_touch_log.txt").write_text("\n".join(report), encoding="utf-8")
        time.sleep(1.0)
        if proc.poll() is None:
            proc.kill()
    print("\n".join(report))


asyncio.run(main())

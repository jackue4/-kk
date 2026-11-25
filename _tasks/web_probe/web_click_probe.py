# -*- coding: utf-8 -*-
"""无界面 Edge 里开本地网页版，等到某行控制台输出后按一张步骤表点画面 / 截图，把控制台输出收下来。
用法：python web_click_probe.py <url> <日志文件> <开始标记> <步骤表.json> <截图目录> [超时秒] [mobile]
步骤表：[["sleep", 秒], ["shot", "名字"], ["click", x, y], ["drag", x0, y0, x1, y1], ["key", "Escape"]]（坐标是页面像素）
带 mobile：按 844×390 的手机横屏 + 触屏模拟开页（点击走触摸事件）。独立临时用户目录，只访问给定的本地地址，跑完就关。"""
import asyncio, base64, json, os, subprocess, sys, tempfile, time, urllib.request

import websockets

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
PORT = 9433


async def main() -> None:
    url, log_path, start_mark, steps_path, shot_dir = sys.argv[1:6]
    timeout = float(sys.argv[6]) if len(sys.argv) > 6 else 300.0
    mobile = len(sys.argv) > 7 and sys.argv[7] == "mobile"
    steps = json.load(open(steps_path, encoding="utf-8"))
    os.makedirs(shot_dir, exist_ok=True)
    prof = tempfile.mkdtemp(prefix="xian_click_")
    size = "844,390" if mobile else "1280,720"
    args = [EDGE, "--headless=new", f"--remote-debugging-port={PORT}", f"--user-data-dir={prof}", f"--window-size={size}",
            "--mute-audio", "--autoplay-policy=no-user-gesture-required", "--no-first-run", "--no-default-browser-check",
            "--use-angle=d3d11", "--ignore-gpu-blocklist", "--disable-background-timer-throttling",
            "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows", "about:blank"]
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    lines: list[str] = []
    try:
        ws_url = None
        for _ in range(60):
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
            mid = 0
            shots: dict[int, str] = {}
            evals: dict = {}
            vp = [0.0, 0.0]          # 页面可视区（CSS 像素）

            async def view_size() -> None:
                evals[mid + 1] = None
                k = await send("Runtime.evaluate", {"returnByValue": True, "expression": "[window.innerWidth, window.innerHeight]"})
                for _ in range(40):
                    await pump(0.25)
                    if evals.get(k) is not None:
                        break
                v = evals.get(k) or [1280, 720]
                vp[0], vp[1] = float(v[0]), float(v[1])

            def vpos(x: float, y: float, anchor: str) -> tuple:
                """游戏画布坐标（基准高 900，宽按比例放开）→ 页面像素；anchor R = x 从右边量"""
                k = vp[1] / 900.0
                return ((vp[0] - x * k) if anchor == "R" else x * k, y * k)

            async def send(method: str, params: dict | None = None) -> int:
                nonlocal mid
                mid += 1
                await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
                return mid

            t0 = time.time()

            def note(s: str) -> None:
                lines.append("%7.1fs %s" % (time.time() - t0, s))

            async def pump(sec: float) -> bool:
                """收 sec 秒的消息；见到开始标记返回 True"""
                hit = False
                end = time.time() + sec
                while time.time() < end:
                    try:
                        raw = await asyncio.wait_for(ws.recv(), timeout=max(0.05, min(1.0, end - time.time())))
                    except asyncio.TimeoutError:
                        continue
                    msg = json.loads(raw)
                    if "error" in msg:
                        note("[probe] 调试口报错 #%s：%s" % (msg.get("id"), json.dumps(msg["error"], ensure_ascii=False)[:300]))
                        continue
                    if msg.get("id") in evals:
                        evals[msg["id"]] = msg.get("result", {}).get("result", {}).get("value")
                        continue
                    if msg.get("id") in shots:
                        data = msg.get("result", {}).get("data")
                        if data:
                            open(shots[msg["id"]], "wb").write(base64.b64decode(data))
                            note("[probe] 存了 " + os.path.basename(shots[msg["id"]]))
                        else:
                            note("[probe] 截图没有数据：" + json.dumps(msg, ensure_ascii=False)[:200])
                        continue
                    m = msg.get("method")
                    text = None
                    if m == "Runtime.consoleAPICalled":
                        p = msg["params"]
                        text = " ".join(str(a.get("value", a.get("description", ""))) for a in p.get("args", []))
                        if p.get("type") in ("error", "warning"):
                            text = f"<{p['type']}> " + text
                    elif m == "Log.entryAdded":
                        e = msg["params"]["entry"]
                        text = f"<log:{e.get('level')}> {e.get('text')}"
                    elif m == "Runtime.exceptionThrown":
                        text = "<exception> " + json.dumps(msg["params"].get("exceptionDetails", {}), ensure_ascii=False)[:600]
                    if text is None:
                        continue
                    note(text)
                    if start_mark and start_mark in text:
                        hit = True
                return hit

            async def tap(x: float, y: float) -> None:
                if mobile:
                    await send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": x, "y": y, "id": 1}]})
                    await pump(0.12)
                    await send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
                else:
                    await send("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x, "y": y})
                    await pump(0.1)
                    await send("Input.dispatchMouseEvent", {"type": "mousePressed", "x": x, "y": y, "button": "left", "buttons": 1, "clickCount": 1})
                    await pump(0.12)
                    await send("Input.dispatchMouseEvent", {"type": "mouseReleased", "x": x, "y": y, "button": "left", "buttons": 0, "clickCount": 1})

            async def drag(x0: float, y0: float, x1: float, y1: float) -> None:
                n = 10
                if mobile:
                    await send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [{"x": x0, "y": y0, "id": 1}]})
                    for i in range(1, n + 1):
                        await pump(0.03)
                        await send("Input.dispatchTouchEvent", {"type": "touchMove", "touchPoints": [
                            {"x": x0 + (x1 - x0) * i / n, "y": y0 + (y1 - y0) * i / n, "id": 1}]})
                    await pump(0.03)
                    await send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
                else:
                    await send("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x0, "y": y0})
                    await send("Input.dispatchMouseEvent", {"type": "mousePressed", "x": x0, "y": y0, "button": "left", "buttons": 1, "clickCount": 1})
                    for i in range(1, n + 1):
                        await pump(0.03)
                        await send("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x0 + (x1 - x0) * i / n,
                                                                "y": y0 + (y1 - y0) * i / n, "button": "left", "buttons": 1})
                    await pump(0.03)
                    await send("Input.dispatchMouseEvent", {"type": "mouseReleased", "x": x1, "y": y1, "button": "left", "buttons": 0, "clickCount": 1})

            await send("Runtime.enable")
            await send("Log.enable")
            await send("Page.enable")
            if mobile:
                await send("Emulation.setDeviceMetricsOverride", {"width": 844, "height": 390, "deviceScaleFactor": 2, "mobile": True,
                                                                 "screenOrientation": {"type": "landscapePrimary", "angle": 90}})
                await send("Emulation.setTouchEmulationEnabled", {"enabled": True, "maxTouchPoints": 5})
            await send("Page.navigate", {"url": url})
            started = False
            while time.time() - t0 < timeout and not started:
                started = await pump(1.0)
            if not started:
                note("[probe] 超时：没等到开始标记 " + start_mark)
            else:
                note("[probe] 见到开始标记，开始走步骤")
                for st in steps:
                    kind = st[0]
                    if kind == "sleep":
                        await pump(float(st[1]))
                    elif kind == "shot":
                        shots[mid + 1] = os.path.join(shot_dir, str(st[1]) + ".jpg")      # 先登记再发：回包可能在 send 返回前就到了
                        await send("Page.captureScreenshot", {"format": "jpeg", "quality": 80})
                        await pump(1.5)
                        note("[probe] 截图 " + str(st[1]))
                    elif kind == "click":
                        note("[probe] 点 (%s, %s)" % (st[1], st[2]))
                        await tap(float(st[1]), float(st[2]))
                    elif kind == "drag":
                        note("[probe] 拖 %s" % (st[1:],))
                        await drag(float(st[1]), float(st[2]), float(st[3]), float(st[4]))
                    elif kind == "vclick":
                        await view_size()
                        px, py = vpos(float(st[1]), float(st[2]), str(st[3]) if len(st) > 3 else "L")
                        note("[probe] 点 画布 (%s, %s, %s) → 页面 (%.0f, %.0f) / %.0f×%.0f" % (st[1], st[2], st[3] if len(st) > 3 else "L", px, py, vp[0], vp[1]))
                        await tap(px, py)
                    elif kind == "fdrag":
                        await view_size()
                        note("[probe] 拖 %s" % (st[1:],))
                        await drag(float(st[1]) * vp[0], float(st[2]) * vp[1], float(st[3]) * vp[0], float(st[4]) * vp[1])
                    elif kind == "key":
                        await send("Input.dispatchKeyEvent", {"type": "keyDown", "key": st[1], "code": st[1]})
                        await pump(0.08)
                        await send("Input.dispatchKeyEvent", {"type": "keyUp", "key": st[1], "code": st[1]})
                await pump(1.0)
            lines.append("[probe] 结束，用时 %.0fs" % (time.time() - t0))
            try:
                await send("Browser.close")
            except Exception:
                pass
    finally:
        with open(log_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        try:
            proc.terminate()
        except Exception:
            pass
        print("lines", len(lines))


asyncio.run(main())

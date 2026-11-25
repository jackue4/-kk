"""网页版内存探针（2026-11-24，查「手机上玩着玩着突然回到 Godot 加载页、之后一直进不去」）。
用法：python -I _tasks/web_probe/mem_probe.py <url> <日志文件> [秒数，默认 180] [调试端口，默认 9421] [play|idle，默认 play] [设备像素比，默认 1]
无界面 Edge、模拟手机（触屏、960×432 横屏）。页面加载前注入探针，每 5 秒记一行：
  · wasm 堆多大（引擎自己的内存；只涨不缩）—— 钩 WebAssembly.instantiate / instantiateStreaming 拿到导出的 memory
  · JS 堆（performance.memory）
  · Web Audio 的 AudioBuffer：建了几个、共多少兆（网页版「采样播放」把每条音频整段解成浮点波形放在这里）
  · WebGL：活着的贴图 / 缓冲各几个、估算占多少兆（按 texImage2D / texStorage2D / compressedTexImage2D / bufferData 的尺寸累加，删掉的减回去）
  · 浏览器渲染进程和显卡进程的实际内存（Windows 进程的专用内存，Get-Process 读）
另外记：页面有没有重新加载（Page.frameNavigated 次数）、渲染进程崩没崩（Inspector.targetCrashed）、控制台报错（内存不足之类）。
play：第 PLAY_AT 秒起模拟手指——每 2 秒推一下摇杆、点一下「攻」（正常开机是在主城里走动挥剑；配探针页的自检参数时由游戏自己跑）。
"""
import asyncio, json, subprocess, sys, tempfile, time, urllib.request

import websockets

HOOK = r"""
(() => {
  const M = window.__mem = {wasm: null, ab_n: 0, ab_bytes: 0, tex: 0, tex_bytes: 0, buf: 0, buf_bytes: 0, rb_bytes: 0, tex_made: 0, tex_del: 0,
                            ctx_lost: 0, big_ab: []};
  // ---- wasm 内存 ----
  const grab = (res) => { try { const inst = res.instance || res; const e = inst.exports; for (const k in e) { if (e[k] instanceof WebAssembly.Memory) M.wasm = e[k]; } } catch (err) {} return res; };
  const i0 = WebAssembly.instantiate;
  WebAssembly.instantiate = function () { return i0.apply(this, arguments).then(grab); };
  if (WebAssembly.instantiateStreaming) {
    const s0 = WebAssembly.instantiateStreaming;
    WebAssembly.instantiateStreaming = function () { return s0.apply(this, arguments).then(grab); };
  }
  // ---- AudioBuffer ----
  const AC = window.AudioContext || window.webkitAudioContext;
  if (AC) {
    const cb = AC.prototype.createBuffer;
    AC.prototype.createBuffer = function (ch, len, rate) {
      M.ab_n++; const b = ch * len * 4; M.ab_bytes += b;
      if (b > 4e6) M.big_ab.push((b / 1048576).toFixed(1) + 'MB(' + ch + 'ch,' + (len / rate).toFixed(1) + 's)');
      return cb.apply(this, arguments);
    };
  }
  // ---- WebGL ----
  const P = WebGL2RenderingContext.prototype;
  const texB = new WeakMap(), bufB = new WeakMap(), rbB = new WeakMap();
  const bufInfo = new Map();      // 缓冲 → [字节, 建的时刻, 种类]
  const texInfo = new Map();      // 贴图 → [宽, 高, 内部格式, 字节, 建的时刻]（删掉时移除）
  M.texInfo = texInfo;
  const curT = {}, curB = {}; let curR = null;
  const wrap = (name, fn) => { const o = P[name]; if (!o) return; P[name] = function () { const r = o.apply(this, arguments); try { fn.apply(this, [arguments, r]); } catch (e) {} return r; }; };
  wrap('createTexture', (a, r) => { M.tex++; M.tex_made++; texB.set(r, 0); });
  wrap('deleteTexture', (a) => { if (a[0] && texB.has(a[0])) { M.tex--; M.tex_del++; M.tex_bytes -= texB.get(a[0]); texB.delete(a[0]); texInfo.delete(a[0]); } });
  wrap('bindTexture', (a) => { curT[a[0]] = a[1]; });
  const tgt = (t) => (t >= 0x8515 && t <= 0x851A) ? 0x8513 : t;       // 立方体的六个面记在 CUBE_MAP 上
  const addTex = (target, bytes, level, w, h, f, comp) => { const t = curT[tgt(target)]; if (!t || !texB.has(t)) return; if (level === 0 && tgt(target) !== 0x8513) { M.tex_bytes -= texB.get(t); texB.set(t, 0); }
    texB.set(t, texB.get(t) + bytes); M.tex_bytes += bytes;
    if (level === 0) texInfo.set(t, [w | 0, h | 0, (comp ? 'c' : '') + '0x' + (f | 0).toString(16), texB.get(t), (performance.now() / 1000) | 0, tgt(target) === 0x8513 ? 'cube' : (tgt(target) === 0x8C1A ? 'array' : '2d')]);
    else { const r = texInfo.get(t); if (r) r[3] = texB.get(t); } };
  const bpp = (ifmt) => { switch (ifmt) { case 0x1903: case 0x8229: case 0x1909: case 0x1906: return 1; case 0x822B: case 0x822D: return 2; case 0x881A: case 0x8814: return ifmt === 0x8814 ? 16 : 8; case 0x8C3A: case 0x822F: return 4; default: return 4; } };
  wrap('texImage2D', (a) => { addTex(a[0], (a[3] | 0) * (a[4] | 0) * bpp(a[2]), a[1], a[3], a[4], a[2], false); });
  wrap('texStorage2D', (a) => { let b = 0, w = a[3], h = a[4]; for (let i = 0; i < a[1]; i++) { b += w * h * bpp(a[2]); w = Math.max(1, w >> 1); h = Math.max(1, h >> 1); } addTex(a[0], b, 0, a[3], a[4], a[2], false); });
  wrap('texImage3D', (a) => { addTex(a[0], (a[3] | 0) * (a[4] | 0) * (a[5] | 0) * bpp(a[2]), a[1], a[3], a[4], a[2], false); });
  wrap('texStorage3D', (a) => { addTex(a[0], (a[3] | 0) * (a[4] | 0) * (a[5] | 0) * bpp(a[2]) * 1.33, 0, a[3], a[4], a[2], false); });
  // WebGL2 的 compressedTexImage2D(target, level, ifmt, w, h, border, 数据视图, 偏移, 长度) / (…, 字节数, 偏移)：引擎传的是整块堆的视图 + 长度
  wrap('compressedTexImage2D', (a) => { const d = a[6]; let n = 0; if (typeof d === 'number') n = d; else if (a.length >= 9 && a[8]) n = a[8]; else n = (d && d.byteLength) || 0; addTex(a[0], n, a[1], a[3], a[4], a[2], true); });
  wrap('generateMipmap', (a) => { const t = curT[tgt(a[0])]; if (t && texB.has(t)) { const e = texB.get(t) * 0.33; texB.set(t, texB.get(t) + e); M.tex_bytes += e; const r = texInfo.get(t); if (r) r[3] = texB.get(t); } });
  wrap('createBuffer', (a, r) => { M.buf++; bufB.set(r, 0); });
  wrap('deleteBuffer', (a) => { if (a[0] && bufB.has(a[0])) { M.buf--; M.buf_bytes -= bufB.get(a[0]); bufB.delete(a[0]); bufInfo.delete(a[0]); } });
  wrap('bindBuffer', (a) => { curB[a[0]] = a[1]; });
  // bufferData(target, 大小 | 数据, usage) 或 WebGL2 的 (target, 数据视图, usage, 偏移, 长度)：后一种 a[1] 是整块 wasm 堆的视图，要按长度算
  wrap('bufferData', (a) => { const b = curB[a[0]]; if (!b || !bufB.has(b)) return; let n = 0; if (typeof a[1] === 'number') n = a[1]; else if (a.length >= 5 && a[4]) n = a[4] * ((a[1] && a[1].BYTES_PER_ELEMENT) || 1);
    else if (a.length >= 4 && a[1]) n = a[1].byteLength - (a[3] | 0) * (a[1].BYTES_PER_ELEMENT || 1); else n = (a[1] && a[1].byteLength) || 0; M.buf_bytes += n - bufB.get(b); bufB.set(b, n);
    bufInfo.set(b, [n, (performance.now() / 1000) | 0, a[0] === 0x8893 ? 'idx' : (a[0] === 0x8892 ? 'vtx' : 'other')]); });
  wrap('createRenderbuffer', (a, r) => { rbB.set(r, 0); });
  wrap('bindRenderbuffer', (a) => { curR = a[1]; });
  wrap('renderbufferStorage', (a) => { if (curR && rbB.has(curR)) { const n = a[2] * a[3] * 4; M.rb_bytes += n - rbB.get(curR); rbB.set(curR, n); } });
  wrap('renderbufferStorageMultisample', (a) => { if (curR && rbB.has(curR)) { const n = a[3] * a[4] * 4 * Math.max(a[1], 1); M.rb_bytes += n - rbB.get(curR); rbB.set(curR, n); } });
  wrap('deleteRenderbuffer', (a) => { if (a[0] && rbB.has(a[0])) { M.rb_bytes -= rbB.get(a[0]); rbB.delete(a[0]); } });
  addEventListener('webglcontextlost', () => { M.ctx_lost++; }, true);
  window.__mem_report = () => {
    const mb = (v) => (v / 1048576).toFixed(0);
    const js = performance.memory ? mb(performance.memory.usedJSHeapSize) + '/' + mb(performance.memory.totalJSHeapSize) : '?';
    return 'wasm ' + (M.wasm ? mb(M.wasm.buffer.byteLength) : '?') + ' MB | JS 堆 ' + js + ' MB | AudioBuffer ' + M.ab_n + ' 个 ' + mb(M.ab_bytes) + ' MB | GL 贴图 ' + M.tex +
      ' 张 ~' + mb(M.tex_bytes) + ' MB（累计建 ' + M.tex_made + ' 删 ' + M.tex_del + '） 缓冲 ' + M.buf + ' 个 ' + mb(M.buf_bytes) + ' MB 渲染缓冲 ' + mb(M.rb_bytes) + ' MB' +
      (M.ctx_lost ? ' | WebGL 上下文丢失 ' + M.ctx_lost + ' 次' : '');
  };
  window.__mem_big = () => M.big_ab.join(' ');
  window.__mem_bigbuf = () => { const all = Array.from(bufInfo.values()); const a = all.slice().sort((x, y) => y[0] - x[0]).slice(0, 24);
    const hist = {}; for (const r of all) { const k = r[0] > 4e6 ? '>4MB' : r[0] > 1e6 ? '1-4MB' : r[0] > 2e5 ? '0.2-1MB' : r[0] > 2e4 ? '20-200KB' : '<20KB'; hist[k] = hist[k] || [0, 0]; hist[k][0]++; hist[k][1] += r[0]; }
    const bytime = {}; for (const r of all) { const k = Math.floor(r[1] / 10) * 10; bytime[k] = (bytime[k] || 0) + r[0]; }
    return a.map(r => (r[0] / 1048576).toFixed(1) + 'MB ' + r[2] + ' @' + r[1] + 's').join(' ; ') + ' || 按大小：' +
      Object.entries(hist).map(e => e[0] + ' ' + e[1][0] + ' 个 ' + (e[1][1] / 1048576).toFixed(0) + 'MB').join('，') + ' || 按建的时刻（每 10 秒）：' +
      Object.entries(bytime).filter(e => e[1] > 2e6).map(e => e[0] + 's ' + (e[1] / 1048576).toFixed(0) + 'MB').join('，'); };
  window.__mem_top = () => { const a = Array.from(texInfo.values()).sort((x, y) => y[3] - x[3]).slice(0, 26);
    const by = {}; for (const r of texInfo.values()) { const k = r[2]; by[k] = (by[k] || 0) + r[3]; }
    return a.map(r => r[0] + 'x' + r[1] + ' ' + r[5] + ' ' + r[2] + ' ' + (r[3] / 1048576).toFixed(1) + 'MB @' + r[4] + 's').join(' ; ') +
      ' || 按格式：' + Object.entries(by).sort((x, y) => y[1] - x[1]).map(e => e[0] + '=' + (e[1] / 1048576).toFixed(0) + 'MB').join(' ') +
      ' || 字库贴图（0x190a，尺寸@建的时刻×张数）：' + (() => { const g = {}; for (const r of texInfo.values()) { if (r[2] !== '0x190a') continue; const k = r[0] + 'x' + r[1] + '@' + Math.floor(r[4] / 10) * 10 + 's'; g[k] = (g[k] || 0) + 1; }
        return Object.entries(g).map(e => e[0] + '×' + e[1]).join(' '); })(); };
})();
"""

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
PLAY_AT = 75.0


def proc_mem(root_pid: int) -> str:
    """Edge 主进程的子进程里，渲染进程和显卡进程各占多少（专用内存，MB）。"""
    ps = ("$c = Get-CimInstance Win32_Process -Filter \"ParentProcessId=%d\"; foreach ($p in $c) { $t = 'other'; "
          "if ($p.CommandLine -match '--type=renderer') { $t = 'renderer' } elseif ($p.CommandLine -match '--type=gpu-process') { $t = 'gpu' } "
          "else { continue }; $g = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue; if ($g) { '{0}:{1}' -f $t, [int]($g.PrivateMemorySize64 / 1MB) } }") % root_pid
    try:
        out = subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True, text=True, timeout=20).stdout.split()
    except Exception:
        return "?"
    r = max([int(x.split(":")[1]) for x in out if x.startswith("renderer:")] or [0])
    g = sum(int(x.split(":")[1]) for x in out if x.startswith("gpu:"))
    return "渲染进程 %d MB、显卡进程 %d MB" % (r, g)


async def main() -> None:
    url, log_path = sys.argv[1], sys.argv[2]
    secs = float(sys.argv[3]) if len(sys.argv) > 3 else 180.0
    port = int(sys.argv[4]) if len(sys.argv) > 4 else 9421
    mode = sys.argv[5] if len(sys.argv) > 5 else "play"
    dpr = float(sys.argv[6]) if len(sys.argv) > 6 else 1.0      # 设备像素比：真机一般 2.5 ~ 3（960×432 的页面 = 2400×1080 的画布），文字贴图和帧缓冲跟着变大
    prof = tempfile.mkdtemp(prefix="xian_mem_")
    args = [EDGE, "--headless=new", f"--remote-debugging-port={port}", f"--user-data-dir={prof}", "--window-size=960,432", "--mute-audio",
            "--autoplay-policy=no-user-gesture-required", "--no-first-run", "--no-default-browser-check", "--use-angle=d3d11", "--ignore-gpu-blocklist",
            "--enable-precise-memory-info", "--disable-background-timer-throttling", "--disable-renderer-backgrounding",
            "--disable-backgrounding-occluded-windows", "about:blank"]
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    lines: list[str] = []
    try:
        ws_url = None
        for _ in range(60):
            try:
                tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json", timeout=1))
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
            pending: dict[int, str] = {}

            async def send(method: str, params: dict | None = None, tag: str = "") -> int:
                nonlocal mid
                mid += 1
                if tag:
                    pending[mid] = tag
                await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
                return mid

            async def touch(kind: str, x: float, y: float) -> None:
                pts = [] if kind == "touchEnd" else [{"x": x, "y": y, "radiusX": 6, "radiusY": 6, "force": 1, "id": 1}]
                await send("Input.dispatchTouchEvent", {"type": kind, "touchPoints": pts})

            await send("Runtime.enable")
            await send("Page.enable")
            await send("Inspector.enable")
            await send("Emulation.setTouchEmulationEnabled", {"enabled": True, "maxTouchPoints": 5})
            await send("Emulation.setDeviceMetricsOverride", {"width": 960, "height": 432, "deviceScaleFactor": dpr, "mobile": True})
            await send("Page.addScriptToEvaluateOnNewDocument", {"source": HOOK})
            await send("Page.navigate", {"url": url})
            t0 = time.time()
            next_rep = 5.0
            next_play = PLAY_AT
            navs = 0
            k = 0
            while time.time() - t0 < secs:
                now = time.time() - t0
                if now >= next_rep:
                    next_rep += 5.0
                    await send("Runtime.evaluate", {"returnByValue": True, "expression": "window.__mem_report ? __mem_report() : 'no hook'"}, "rep")
                if mode == "play" and now >= next_play:
                    next_play += 2.0
                    k += 1
                    s = min(960 / 1600, 432 / 900)
                    # 摇杆：左下角按住往一个方向拖一秒（方向每次换）；再点一下「攻」
                    ox, oy = 960 * 0.16, 432 * 0.72
                    dx, dy = [(0, -60), (60, 0), (0, 60), (-60, 0)][k % 4]
                    await touch("touchStart", ox, oy)
                    await asyncio.sleep(0.05)
                    await touch("touchMove", ox + dx, oy + dy)
                    await asyncio.sleep(0.9)
                    await touch("touchEnd", 0, 0)
                    await touch("touchStart", 960 - 165 * s, 432 - 165 * s)
                    await asyncio.sleep(0.06)
                    await touch("touchEnd", 0, 0)
                try:
                    raw = await asyncio.wait_for(ws.recv(), timeout=0.5)
                except asyncio.TimeoutError:
                    continue
                msg = json.loads(raw)
                if msg.get("id") in pending:
                    pending.pop(msg["id"])
                    v = msg.get("result", {}).get("result", {}).get("value")
                    lines.append("%6.0fs [mem] %s | %s" % (now, v, proc_mem(proc.pid)))
                    continue
                m = msg.get("method")
                if m == "Page.frameNavigated" and not msg["params"]["frame"].get("parentId"):
                    navs += 1
                    lines.append("%6.0fs [nav] 页面加载第 %d 次：%s" % (now, navs, msg["params"]["frame"].get("url", "")[:80]))
                elif m == "Inspector.targetCrashed":
                    lines.append("%6.0fs [crash] 渲染进程崩了" % now)
                elif m == "Runtime.consoleAPICalled":
                    p = msg["params"]
                    text = " ".join(str(a.get("value", a.get("description", ""))) for a in p.get("args", []))
                    if (p.get("type") == "error" or "ERROR" in text or "memory" in text.lower() or "[pace]" in text or "[warm]" in text or "[meadow]" in text
                            or "[audio]" in text or "[hub]" in text or "[mem" in text):
                        lines.append("%6.0fs %s" % (now, text[:260]))
                elif m == "Runtime.exceptionThrown":
                    lines.append("%6.0fs <exception> %s" % (now, json.dumps(msg["params"].get("exceptionDetails", {}), ensure_ascii=False)[:300]))
            await send("Runtime.evaluate", {"returnByValue": True, "expression": "window.__mem_big ? __mem_big() : ''"}, "big")
            await send("Runtime.evaluate", {"returnByValue": True, "expression": "window.__mem_top ? __mem_top() : ''"}, "top")
            await send("Runtime.evaluate", {"returnByValue": True, "expression": "window.__mem_bigbuf ? __mem_bigbuf() : ''"}, "bigbuf")
            t_end = time.time() + 2.0
            while time.time() < t_end:
                try:
                    raw = await asyncio.wait_for(ws.recv(), timeout=0.5)
                except asyncio.TimeoutError:
                    continue
                msg = json.loads(raw)
                if msg.get("id") in pending:
                    tag = pending.pop(msg["id"])
                    lines.append("[%s] %s" % ({"big": "大的 AudioBuffer", "top": "最大的贴图", "bigbuf": "最大的缓冲"}.get(tag, tag), msg.get("result", {}).get("result", {}).get("value")))
            try:
                await send("Browser.close")
            except Exception:
                pass
    finally:
        with open(log_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        time.sleep(1.0)
        if proc.poll() is None:
            proc.kill()
    print("lines", len(lines))


asyncio.run(main())

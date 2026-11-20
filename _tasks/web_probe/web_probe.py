"""用本机的无界面 Edge 跑本地导出的网页版探针页，把控制台输出收下来。
用法：python web_probe.py <url> <日志文件> <结束标记> [超时秒数]
独立的临时用户目录（不碰用户自己的浏览器），只访问给定的本地地址；跑完 / 超时就关掉这个浏览器进程。
"""
import asyncio, json, os, subprocess, sys, tempfile, time, urllib.request

import websockets


HOOK = """
(() => {
  const P = WebGL2RenderingContext.prototype;
  const src0 = P.shaderSource, link0 = P.linkProgram;
  let sig = '', n = 0;
  P.shaderSource = function (sh, src) {
    try {
      if (this.getShaderParameter(sh, this.SHADER_TYPE) === this.FRAGMENT_SHADER) {
        const head = src.slice(0, 3000);
        const defs = [...new Set((head.match(/#define +[A-Za-z0-9_]+/g) || []).map(s => s.replace(/#define +/, '')))];
        const i = src.indexOf('MaterialUniforms');
        const blk = i >= 0 ? src.slice(i, i + 200).replace(/[\\n\\t ]+/g, ' ') : 'no-ubo';
        sig = 'len=' + src.length + ' defs=' + defs.slice(0, 40).join(' ') + ' | ' + blk;
      }
    } catch (e) { sig = 'err ' + e; }
    return src0.call(this, sh, src);
  };
  P.linkProgram = function (p) {
    n++;
    const r = link0.call(this, p);
    console.log('[gl] link #' + n + ' ' + sig);
    return r;
  };
})();
"""

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
PORT = 9377


async def main() -> None:
    url, log_path, done_mark = sys.argv[1], sys.argv[2], sys.argv[3]
    timeout = float(sys.argv[4]) if len(sys.argv) > 4 else 420.0
    prof = tempfile.mkdtemp(prefix="xian_probe_")
    args = [EDGE, "--headless=new", f"--remote-debugging-port={PORT}", f"--user-data-dir={prof}", "--window-size=1280,720",
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

            async def send(method: str, params: dict | None = None) -> int:
                nonlocal mid
                mid += 1
                await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
                return mid

            await send("Runtime.enable")
            await send("Log.enable")
            await send("Page.enable")
            await send("Page.addScriptToEvaluateOnNewDocument", {"source": HOOK})
            await send("Page.navigate", {"url": url})
            t0 = time.time()
            gpu_id = -1
            asked_gpu = False
            done = False
            while time.time() - t0 < timeout and not done:
                if not asked_gpu and time.time() - t0 > 8.0:
                    asked_gpu = True
                    gpu_id = await send("Runtime.evaluate", {"returnByValue": True, "expression":
                        "(()=>{const c=document.createElement('canvas');const g=c.getContext('webgl2');if(!g)return 'no webgl2';"
                        "const e=g.getExtension('WEBGL_debug_renderer_info');return e?g.getParameter(e.UNMASKED_RENDERER_WEBGL):'unknown';})()"})
                try:
                    raw = await asyncio.wait_for(ws.recv(), timeout=2.0)
                except asyncio.TimeoutError:
                    continue
                msg = json.loads(raw)
                if msg.get("id") == gpu_id and gpu_id > 0:
                    lines.append("[probe] WebGL 渲染器：" + str(msg.get("result", {}).get("result", {}).get("value")))
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
                lines.append("%7.1fs %s" % (time.time() - t0, text))
                if done_mark in text:
                    done = True
            lines.append("[probe] 结束：%s，用时 %.0fs" % ("见到结束标记" if done else "超时", time.time() - t0))
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

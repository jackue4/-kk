"""网页版到底有没有出声：用无界面 Edge 打开本地导出的网页包，在页面里给 Web Audio 套一层探针，量「真正送到扬声器那一路」的音量。
用法：python -I _tasks/web_probe/audio_probe.py <url> <日志文件> [秒数，默认 90] [gesture|autoplay，默认 gesture] [端口，默认 9393] [第几秒点屏幕，默认 30]
  gesture  = 按手机浏览器的默认规矩：没有用户手势不许出声（和真机一样），脚本在第 TAP_AT 秒模拟一次触屏点击
  autoplay = 允许无手势自动出声（对照）
探针（页面加载前注入）：
  · 包一层 AudioContext：记下创建了几个、采样率、状态变化（suspended / running）、resume() 被调了几次
  · 所有连到 destination（扬声器）的节点改成先过一个 AnalyserNode 再到 destination：每秒读一次它的均方根 / 峰值 = 实际输出的音量
  · 数 createBufferSource / AudioBufferSourceNode.start（Godot 网页版「采样播放」模式下每放一个音就是一次）、AudioWorkletNode 创建
  · 也看 HTMLAudioElement 的 play()，以及 navigator.audioSession 设成了什么
模拟手机：开触屏模拟（ontouchstart 存在、5 个触点），视口 960×432 横屏；点击用 Input.dispatchTouchEvent（真机上的手势就是触摸）。
第 TAP_AT 秒点一下屏幕中间偏左（摇杆区，只当作「手势」），之后每 3 秒点一下右下角的「攻」键（地面挥剑 → 应该有挥砍音效）。
不出声：启动参数带 --mute-audio（探针在混音图里量，不经过本机扬声器）。
"""
import asyncio, json, os, subprocess, sys, tempfile, time, urllib.request

import websockets

HOOK = r"""
(() => {
  const S = window.__aud = {ctx: 0, states: [], resumes: 0, starts: 0, srcs: 0, worklets: 0, html_play: 0, max_rms: 0, max_peak: 0, rate: 0,
                            bufs: [], links: {}, ctxs: [], gains: [],
                            loud_s: 0, an: [], sess: (navigator.audioSession ? 'has:' + navigator.audioSession.type : 'none')};
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) return;
  const proto = AC.prototype;
  const r0 = proto.resume;
  proto.resume = function () { S.resumes++; return r0.apply(this, arguments); };
  const cbs = proto.createBufferSource;
  proto.createBufferSource = function () { S.srcs++; return cbs.apply(this, arguments); };
  const st0 = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function () {
    S.starts++;
    try {
      const b = this.buffer;
      let m = 0;
      if (b) { for (let c = 0; c < b.numberOfChannels; c++) { const d = b.getChannelData(c); for (let i = 0; i < d.length; i += 5) m = Math.max(m, Math.abs(d[i])); } }
      S.bufs.push((b ? b.duration.toFixed(2) + 's/' + b.numberOfChannels + 'ch/' + b.sampleRate : 'nobuf') + ' max=' + m.toFixed(3) + ' rate=' + this.playbackRate.value.toFixed(2));
      if (S.bufs.length > 40) S.bufs.shift();
    } catch (e) { S.bufs.push('err ' + e); }
    return st0.apply(this, arguments);
  };
  const cg = proto.createGain;
  proto.createGain = function () { const g = cg.apply(this, arguments); S.gains.push(g); return g; };
  if (window.AudioWorkletNode) {
    const W = window.AudioWorkletNode;
    window.AudioWorkletNode = function (c, n, o) { S.worklets++; return new W(c, n, o); };
    window.AudioWorkletNode.prototype = W.prototype;
  }
  const hp = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function () { S.html_play++; return hp.apply(this, arguments); };
  const taps = new WeakMap();
  const tapOf = (ctx) => {
    let a = taps.get(ctx);
    if (!a) {
      a = ctx.createAnalyser();
      a.fftSize = 2048;
      a.__real_connect(ctx.destination);
      taps.set(ctx, a);
      S.an.push(a);
      S.ctx++;
      S.ctxs.push(ctx);
      S.rate = ctx.sampleRate;
      S.states.push(ctx.state);
      ctx.addEventListener('statechange', () => S.states.push(ctx.state));
    }
    return a;
  };
  const c0 = AudioNode.prototype.connect;
  AudioNode.prototype.__real_connect = c0;
  AudioNode.prototype.connect = function (dst) {
    const k = this.constructor.name + '>' + (dst && dst.constructor ? dst.constructor.name : String(dst));
    S.links[k] = (S.links[k] || 0) + 1;
    if (dst && dst instanceof AudioDestinationNode && !(this instanceof AnalyserNode)) {
      return c0.call(this, tapOf(this.context));
    }
    return c0.apply(this, arguments);
  };
  const buf = new Float32Array(2048);
  setInterval(() => {
    let rms = 0, pk = 0;
    for (const a of S.an) {
      a.getFloatTimeDomainData(buf);
      let s = 0;
      for (let i = 0; i < buf.length; i++) { s += buf[i] * buf[i]; pk = Math.max(pk, Math.abs(buf[i])); }
      rms = Math.max(rms, Math.sqrt(s / buf.length));
    }
    S.cur_rms = rms; S.cur_peak = pk;
    S.max_rms = Math.max(S.max_rms, rms); S.max_peak = Math.max(S.max_peak, pk);
    if (rms > 0.001) S.loud_s += 0.25;
  }, 250);
  // 断音：出过声之后，每 50 毫秒看一眼，输出完全是零的窗口数 / 最长连续多少毫秒（流式播放的音乐被卡顿帧饿到时就是这样）
  S.gaps = 0; S.gap_run = 0; S.gap_max = 0; S.heard = false; S.win = 0;
  const gbuf = new Float32Array(1024);
  setInterval(() => {
    let pk = 0;
    for (const a of S.an) { a.getFloatTimeDomainData(gbuf); for (let i = 0; i < gbuf.length; i += 4) pk = Math.max(pk, Math.abs(gbuf[i])); }
    if (pk > 1e-4) { S.heard = true; S.gap_run = 0; S.win++; }
    else if (S.heard) { S.win++; S.gaps++; S.gap_run += 50; S.gap_max = Math.max(S.gap_max, S.gap_run); }
  }, 50);
  window.__aud_gaps = () => '出声后 ' + S.win + ' 个 50 毫秒窗口里，完全无声的 ' + S.gaps + ' 个，最长连续 ' + S.gap_max + ' 毫秒';
  window.__aud_detail = () => {
    const gs = S.gains.map(g => g.gain.value.toFixed(3));
    return '连接 ' + JSON.stringify(S.links) + ' | 增益节点 ' + gs.length + ' 个，值 ' + gs.slice(0, 40).join(',') + ' | 最近的 buffer：' + S.bufs.slice(-12).join(' ; ');
  };
  window.__aud_tone = () => {
    const c = S.ctxs[0]; if (!c) return 'no ctx';
    const o = c.createOscillator(); const g = c.createGain(); g.gain.value = 0.3; o.connect(g); g.connect(c.destination); o.start(); o.stop(c.currentTime + 1.0);
    return 'tone at ' + c.currentTime.toFixed(2);
  };
  window.__aud_report = () => {
    const db = (v) => v > 1e-6 ? (20 * Math.log10(v)).toFixed(1) : '-inf';
    return 'ctx ' + S.ctx + ' state ' + S.states.join('>') + ' resume() ' + S.resumes + ' | 输出 当前 ' + db(S.cur_rms || 0) + ' dB 峰 ' + db(S.cur_peak || 0) +
      ' dB，至今最大 ' + db(S.max_rms) + ' dB，有声 ' + S.loud_s.toFixed(1) + ' 秒 | buffer source 建 ' + S.srcs + ' 播 ' + S.starts +
      ' | worklet ' + S.worklets + ' | <audio>.play ' + S.html_play + ' | audioSession ' + (navigator.audioSession ? navigator.audioSession.type : 'none') +
      ' | 采样率 ' + S.rate;
  };
})();
"""

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
TAP_AT = 30.0


async def main() -> None:
    url, log_path = sys.argv[1], sys.argv[2]
    secs = float(sys.argv[3]) if len(sys.argv) > 3 else 90.0
    mode = sys.argv[4] if len(sys.argv) > 4 else "gesture"
    port = int(sys.argv[5]) if len(sys.argv) > 5 else 9393
    tap_at = float(sys.argv[6]) if len(sys.argv) > 6 else TAP_AT
    prof = tempfile.mkdtemp(prefix="xian_aud_")
    args = [EDGE, "--headless=new", f"--remote-debugging-port={port}", f"--user-data-dir={prof}", "--window-size=960,432",
            "--mute-audio", "--no-first-run", "--no-default-browser-check", "--use-angle=d3d11", "--ignore-gpu-blocklist",
            "--disable-background-timer-throttling", "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows"]
    if mode == "autoplay":
        args.append("--autoplay-policy=no-user-gesture-required")
    args.append("about:blank")
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

            async def tap(x: float, y: float) -> None:
                pt = [{"x": x, "y": y, "radiusX": 6, "radiusY": 6, "force": 1, "id": 1}]
                await send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": pt})
                await asyncio.sleep(0.08)
                await send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})

            await send("Runtime.enable")
            await send("Page.enable")
            await send("Emulation.setTouchEmulationEnabled", {"enabled": True, "maxTouchPoints": 5})
            await send("Emulation.setDeviceMetricsOverride", {"width": 960, "height": 432, "deviceScaleFactor": 1, "mobile": True})
            await send("Page.addScriptToEvaluateOnNewDocument", {"source": HOOK})
            await send("Page.navigate", {"url": url})
            t0 = time.time()
            next_rep = 2.0
            tapped = False
            next_atk = tap_at + 4.0
            atk_n = 0
            while time.time() - t0 < secs:
                now = time.time() - t0
                if now >= next_rep:
                    next_rep += 3.0
                    await send("Runtime.evaluate", {"returnByValue": True, "expression": "window.__aud_report ? __aud_report() : 'no hook'"}, "rep")
                if not tapped and now >= tap_at:
                    tapped = True
                    lines.append("%7.1fs [probe] 点一下屏幕（摇杆区，只当作手势）" % now)
                    await tap(960 * 0.2, 432 * 0.7)
                if tapped and now >= next_atk:
                    next_atk += 3.0
                    atk_n += 1
                    # 「攻」键：逻辑坐标（右下角往里 165, 165），画面按 canvas_items 等比缩放（基准 1600×900，aspect expand）
                    s = min(960 / 1600, 432 / 900)
                    await tap(960 - 165 * s, 432 - 165 * s)
                try:
                    raw = await asyncio.wait_for(ws.recv(), timeout=0.5)
                except asyncio.TimeoutError:
                    continue
                msg = json.loads(raw)
                if msg.get("id") in pending:
                    pending.pop(msg["id"])
                    v = msg.get("result", {}).get("result", {}).get("value")
                    lines.append("%7.1fs [aud] %s%s" % (now, v, "（已点「攻」%d 次）" % atk_n if atk_n else ""))
                    continue
                if msg.get("method") == "Runtime.consoleAPICalled":
                    p = msg["params"]
                    text = " ".join(str(a.get("value", a.get("description", ""))) for a in p.get("args", []))
                    if p.get("type") == "error" or "ERROR" in text or "[aud" in text or "[warm]" in text or "audio" in text.lower():
                        lines.append("%7.1fs %s" % (now, text[:300]))
                elif msg.get("method") == "Runtime.exceptionThrown":
                    lines.append("%7.1fs <exception> %s" % (now, json.dumps(msg["params"].get("exceptionDetails", {}), ensure_ascii=False)[:400]))
            await send("Runtime.evaluate", {"returnByValue": True, "expression": "window.__aud_gaps ? __aud_gaps() : 'no hook'"}, "gaps")
            await send("Runtime.evaluate", {"returnByValue": True, "expression": "window.__aud_detail ? __aud_detail() : 'no hook'"}, "detail")
            await send("Runtime.evaluate", {"returnByValue": True, "expression": "window.__aud_tone ? __aud_tone() : 'no hook'"}, "tone")
            t_end = time.time() + 2.5
            while time.time() < t_end:
                try:
                    raw = await asyncio.wait_for(ws.recv(), timeout=0.5)
                except asyncio.TimeoutError:
                    continue
                msg = json.loads(raw)
                if msg.get("id") in pending:
                    tag = pending.pop(msg["id"])
                    lines.append("[%s] %s" % (tag, msg.get("result", {}).get("result", {}).get("value")))
            await send("Runtime.evaluate", {"returnByValue": True, "expression": "window.__aud_report ? __aud_report() : 'no hook'"}, "after-tone")
            t_end = time.time() + 1.5
            while time.time() < t_end:
                try:
                    raw = await asyncio.wait_for(ws.recv(), timeout=0.5)
                except asyncio.TimeoutError:
                    continue
                msg = json.loads(raw)
                if msg.get("id") in pending:
                    tag = pending.pop(msg["id"])
                    lines.append("[%s] %s" % (tag, msg.get("result", {}).get("result", {}).get("value")))
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

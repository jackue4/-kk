"""同 run_probe.py（跑项目里的 web_probe.py、调试端口换成 9391），另外给每个着色器程序计时：
从 linkProgram 到第一次查 LINK_STATUS 返回（浏览器在这一步等编译做完），打成 `[gl] linked #序号 毫秒`。"""
import pathlib, sys
src = pathlib.Path(r"D:\GodotProjects\修仙游戏\_tasks\web_probe\web_probe.py").read_text(encoding="utf-8")
assert "PORT = 9377" in src
src = src.replace("PORT = 9377", "PORT = 9391")
old = """  P.linkProgram = function (p) {
    n++;
    const r = link0.call(this, p);
    console.log('[gl] link #' + n + ' ' + sig);
    return r;
  };
"""
new = """  const gpp0 = P.getProgramParameter;
  P.linkProgram = function (p) {
    n++;
    const r = link0.call(this, p);
    console.log('[gl] link #' + n + ' ' + sig);
    try { p.__t = performance.now(); p.__n = n; } catch (e) {}
    return r;
  };
  P.getProgramParameter = function (p, pn) {
    const r = gpp0.call(this, p, pn);
    try {
      if (pn === this.LINK_STATUS && p && p.__t) {
        console.log('[gl] linked #' + p.__n + ' ' + (performance.now() - p.__t).toFixed(0));
        p.__t = 0;
      }
    } catch (e) {}
    return r;
  };
"""
assert old in src
src = src.replace(old, new)
exec(compile(src, "web_probe.py", "exec"), {"__name__": "__main__"})

"""跑项目里的 _tasks/web_probe/web_probe.py，只把调试端口换成 9391（免得和别的会话同时跑时撞端口）。参数原样传。"""
import pathlib, sys
src = pathlib.Path(r"D:\GodotProjects\修仙游戏\_tasks\web_probe\web_probe.py").read_text(encoding="utf-8")
assert "PORT = 9377" in src
src = src.replace("PORT = 9377", "PORT = 9391")
exec(compile(src, "web_probe.py", "exec"), {"__name__": "__main__"})

"""以隐藏窗口启动 Godot（不弹出可见窗口、不抢焦点），用于无界面渲染截图 / 录像。
headless 显示驱动只有 dummy 渲染器拿不到画面，所以这里仍创建真窗口，但：
STARTUPINFO 要求首次 ShowWindow 用 SW_HIDE，并把窗口放到屏幕外；运行中再每隔一会儿把该进程的顶层窗口隐藏一遍兜底。
用法：python run_hidden.py <project_dir> <log_prefix> [godot 参数...]
"""
import ctypes, ctypes.wintypes as wt, subprocess, sys, time, threading

GODOT = r"D:\ugc-ai\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
user32 = ctypes.windll.user32
EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)


def windows_of(pid):
    out = []
    def cb(hwnd, _):
        p = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value == pid:
            out.append(hwnd)
        return True
    user32.EnumWindows(EnumWindowsProc(cb), 0)
    return out


def main():
    proj, log = sys.argv[1], sys.argv[2]
    args = [GODOT, "--path", proj, "--position", "-30000,-30000"] + sys.argv[3:]
    si = subprocess.STARTUPINFO()
    si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    si.wShowWindow = 0  # SW_HIDE
    with open(log + "_out.txt", "w", encoding="utf-8") as fo, open(log + "_err.txt", "w", encoding="utf-8") as fe:
        p = subprocess.Popen(args, stdout=fo, stderr=fe, startupinfo=si,
                             creationflags=subprocess.CREATE_NO_WINDOW)
        seen_visible = False
        t0 = time.time()
        while p.poll() is None:
            if time.time() - t0 > 1200:
                p.kill()  # 脚本出错卡住（演示协程没跑起来、不会 quit）时兜底结束隐藏进程
                print("timeout: killed")
                break
            for h in windows_of(p.pid):
                if user32.IsWindowVisible(h):
                    seen_visible = True
                    user32.ShowWindow(h, 0)
            time.sleep(0.05)
    print("exit", p.wait(), "window was visible at some point:", seen_visible)


main()

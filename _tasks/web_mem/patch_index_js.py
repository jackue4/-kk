"""给网页版的引擎 JS（index.js）打一个小补丁（2026-11-24 手机内存）。用法：python -I _tasks/web_mem/patch_index_js.py <index.js> [--check]
Godot 4.7 网页版「采样播放」每放一次音效，Sample.getAudioBuffer() 都把那条音效的波形整段复制一份（先拷成 Float32Array、再建一个新的 AudioBuffer），
复制品只是赋给播放节点的 buffer、用完就丢——打起来每秒四五次，几分钟就是几百兆等着浏览器回收的临时内存。
Web Audio 本来就允许多个 AudioBufferSourceNode 共用一个 AudioBuffer，所以改成直接返回原来那个。
整包导出（换导出模板生成的 index.js）以后这个补丁会丢，要重新打一遍；已经打过的再跑不会重复改。
"""
import io, sys

OLD = "getAudioBuffer(){return this._duplicateAudioBuffer()}"
NEW = "getAudioBuffer(){return this._audioBuffer}"

p = sys.argv[1]
s = io.open(p, encoding="utf-8", newline="").read()
if "--check" in sys.argv:
    print("已打补丁" if NEW in s and OLD not in s else ("没打" if OLD in s else "认不出（引擎版本变了？）"))
    sys.exit(0)
if NEW in s and OLD not in s:
    print("已经打过了")
    sys.exit(0)
assert s.count(OLD) == 1, "没找到要改的那一处（引擎版本变了？）"
# 只有两处调用，都是「播放节点.buffer = 采样.getAudioBuffer()」
assert s.count(".getAudioBuffer()") == 2, "getAudioBuffer 的调用处和预想的不一样，先看一眼再改"
io.open(p, "w", encoding="utf-8", newline="").write(s.replace(OLD, NEW))
print("打好了：", p)

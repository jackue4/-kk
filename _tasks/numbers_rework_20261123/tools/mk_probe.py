"""拷一份导出目录里的 index.html 成探针页，把 "args":[] 换成给定参数。用法：python -I mk_probe.py <导出目录> <探针页名> 参数..."""
import json, sys, os
d, name, args = sys.argv[1], sys.argv[2], sys.argv[3:]
s = open(os.path.join(d, "index.html"), encoding="utf-8").read()
assert s.count('"args":[]') == 1
s = s.replace('"args":[]', '"args":' + json.dumps(["--"] + args))
open(os.path.join(d, name), "w", encoding="utf-8").write(s)
print("wrote", name, args)

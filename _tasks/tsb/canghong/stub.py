"""二分查「退出时报资源没释放」用：把 kit_canghong2.gd 里指定的函数体换成空壳。
用法：python stub.py <原文件> <输出文件> 名字1,名字2,...   （名字 ALL = 全部；前面带 - 表示「除了这些」）"""
import io, re, sys
src, dst, names = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(src, encoding='utf-8', newline='').read()
parts = re.split(r'(?m)^(?=(?:static )?func )', s)
head, funcs = parts[0], parts[1:]
inv = names.startswith('-')
want = set(names.lstrip('-').split(','))
out = [head]
RET = {'void': '\tpass\n', 'bool': '\treturn false\n', 'int': '\treturn 0\n', 'float': '\treturn 0.0\n', 'Vector3': '\treturn Vector3.ZERO\n'}
n = 0
for f in funcs:
    m = re.match(r'(static )?func (\w+)\((.*?)\)(?: -> (\w+))?:\n', f, re.S)
    name = m.group(2)
    hit = ('ALL' in want) or ((name in want) != inv)
    if not hit:
        out.append(f); continue
    n += 1
    params = [p.split(':')[0].split('=')[0].strip() for p in m.group(3).split(',') if p.strip()]
    # 函数后面跟着的注释 / 空行留着
    body_end = len(f)
    tail = re.search(r'\n\n\n(?:#|$)', f)
    rest = f[tail.start():] if tail else '\n\n\n'
    ret = RET.get(m.group(4) or 'void', '\treturn null\n')
    use = ('\tif OS.has_feature("never_x"):\n\t\tprint(%s)\n' % ', '.join(params)) if params else ''
    out.append(f[:m.end()] + use + ret + rest.lstrip('\n').join(['\n\n\n', '']) if False else f[:m.end()] + use + ret + rest)
io.open(dst, 'w', encoding='utf-8', newline='').write(''.join(out))
print('stubbed', n, 'of', len(funcs))

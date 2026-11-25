import io, time, sys
def patch(p, pairs):
    s = io.open(p, encoding='utf-8', newline='').read()
    crlf = '\r\n' in s
    for a, b, n in pairs:
        if crlf:
            a = a.replace('\n', '\r\n'); b = b.replace('\n', '\r\n')
        c = s.count(a)
        if c != n:
            raise SystemExit('MISMATCH %s: want %d got %d :: %r' % (p, n, c, a[:90]))
        s = s.replace(a, b)
    for i in range(6):
        try:
            io.open(p, 'w', encoding='utf-8', newline='').write(s); return
        except OSError as e:
            time.sleep(0.8)
    raise SystemExit('WRITE FAIL ' + p)

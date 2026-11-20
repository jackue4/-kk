// 飞剑对波几个着色器共用的噪声（整数哈希的格点噪声：相邻格子算同一个格点不会差出一点，放大了不碎成块）。
// 传进来的坐标要保持为正（调用处都加了偏移，脚本里的流动量也是取模过的）。

float clash_hash(ivec2 c) {
	uint n = uint(c.x) * 1597334677u ^ uint(c.y) * 3812015801u;
	n = (n ^ (n >> 15u)) * 2246822519u;
	n ^= n >> 13u;
	return float(n & 65535u) / 65535.0;
}

float clash_noise(vec2 p) {
	ivec2 i = ivec2(floor(p));
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = clash_hash(i);
	float b = clash_hash(i + ivec2(1, 0));
	float c = clash_hash(i + ivec2(0, 1));
	float d = clash_hash(i + ivec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

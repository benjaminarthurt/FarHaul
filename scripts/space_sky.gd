class_name SpaceSky
extends RefCounted
## A procedural night sky: two layers of stars and a faint two-colour nebula. One small sky shader,
## no textures. Cheap enough for integrated GPUs because it only runs where the sky is visible.

const CODE := """
shader_type sky;

uniform vec3 nebula_a : source_color = vec3(0.30, 0.10, 0.50);
uniform vec3 nebula_b : source_color = vec3(0.05, 0.32, 0.42);
uniform float nebula_strength = 0.75;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1,0,0)), f.x), mix(hash13(i + vec3(0,1,0)), hash13(i + vec3(1,1,0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0,0,1)), hash13(i + vec3(1,0,1)), f.x), mix(hash13(i + vec3(0,1,1)), hash13(i + vec3(1,1,1)), f.x), f.y);
	return mix(a, b, f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

float stars(vec3 dir, float scale, float density) {
	vec3 p = dir * scale;
	vec3 c = floor(p);
	vec3 f = fract(p);
	float h = hash13(c);
	vec3 off = vec3(hash13(c + 1.7), hash13(c + 5.3), hash13(c + 9.1));
	float d = length(f - (0.25 + 0.5 * off));
	float star = step(density, h) * smoothstep(0.18, 0.0, d);
	return star * (0.45 + hash13(c + 3.1));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float s = stars(d, 70.0, 0.965) + 0.7 * stars(d, 150.0, 0.98);
	float cloud = smoothstep(0.42, 0.85, fbm(d * 2.2 + 3.0));
	vec3 tint = mix(nebula_b, nebula_a, fbm(d * 1.3 + 9.0));
	vec3 col = vec3(0.010, 0.012, 0.026) + tint * cloud * nebula_strength;
	col += vec3(s) * mix(vec3(1.0, 0.85, 0.7), vec3(0.75, 0.88, 1.0), hash13(floor(d * 70.0) + 11.0));
	COLOR = col;
}
"""


static func make() -> Sky:
	var shader := Shader.new()
	shader.code = CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var sky := Sky.new()
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32  # we only need the backdrop, not reflections
	return sky

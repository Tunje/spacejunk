shader_type sky;
// Dark, uncluttered sky: sparse stars and one faint band, all procedural.

uniform vec3 band_normal = vec3(0.3, 0.86, 0.41);
uniform vec3 band_colour : source_color = vec3(0.10, 0.12, 0.19);
uniform float band_strength = 0.05;

float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float low = mix(
		mix(hash(cell), hash(cell + vec3(1, 0, 0)), f.x),
		mix(hash(cell + vec3(0, 1, 0)), hash(cell + vec3(1, 1, 0)), f.x), f.y);
	float high = mix(
		mix(hash(cell + vec3(0, 0, 1)), hash(cell + vec3(1, 0, 1)), f.x),
		mix(hash(cell + vec3(0, 1, 1)), hash(cell + vec3(1, 1, 1)), f.x), f.y);
	return mix(low, high, f.z);
}

vec3 star_layer(vec3 dir, float density, float threshold, float size) {
	vec3 p = dir * density;
	vec3 cell = floor(p);
	float chance = hash(cell);
	if (chance < threshold) {
		return vec3(0.0);
	}
	vec3 offset = vec3(hash(cell + 11.0), hash(cell + 23.0), hash(cell + 37.0)) * 0.6 - 0.3;
	float dist = length(fract(p) - 0.5 - offset);
	float brightness = smoothstep(size, 0.0, dist) * (0.4 + 0.6 * hash(cell + 5.0));
	float warmth = hash(cell + 17.0);
	return mix(vec3(0.72, 0.82, 1.0), vec3(1.0, 0.86, 0.68), warmth) * brightness;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 stars = star_layer(dir, 160.0, 0.965, 0.09) * 0.7;
	stars += star_layer(dir, 90.0, 0.985, 0.07);
	float height = dot(dir, normalize(band_normal));
	float haze = value_noise(dir * 3.0) * 0.6 + value_noise(dir * 7.0) * 0.4;
	float band = exp(-height * height * 26.0) * haze;
	COLOR = vec3(0.004, 0.005, 0.010) + stars + band_colour * band * band_strength * 6.0;
}

## The zombie palette shader and its limits, split from [ZzZombieViewBase].
extends RefCounted

## The palette shader: up to [constant SWAPS] atlas colours swapped within a tolerance, then dirt and blood
## from the vertex-colour noise, then the kind's glow. Compatibility renderer: no per-instance
## uniforms (a material per look) and no arrays with hints.
const SWAPS := 6
## How much of a kind's `glow` the whole body gives off (the throat is its own mesh): at full
## strength the spitter was a flat green silhouette with no face. And the share of its own
## colour every zombie emits, which keeps a dark body readable in the dark.
const GLOW_BODY := 0.25
const BODY_LIFT := 0.22
const SHADER := """
shader_type spatial;
render_mode cull_back, specular_disabled;
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform vec4 from_colour[6];
uniform vec4 to_colour[6];
uniform vec4 from_linear[6];
uniform vec4 to_linear[6];
uniform int swaps = 0;
uniform float tolerance = 0.004;
uniform float dirt = 0.5;
uniform float blood_cut = 0.6;
uniform vec3 blood_colour : source_color = vec3(0.45, 0.06, 0.05);
uniform vec3 glow = vec3(0.0);
uniform vec3 mark_colour : source_color = vec3(0.0);
uniform float mark_amount = 0.0;
uniform vec3 vein_colour : source_color = vec3(0.0);
uniform float vein_amount = 0.0;
uniform float flash = 0.0;
uniform float lift = 0.0;

void fragment() {
	// Sampled exactly as a StandardMaterial3D samples its albedo (source_color), so a zombie is
	// lit like everything else on the street. Which space that hands back differs by renderer
	// (the compatibility one gave the stored sRGB values here), so a swap is matched in both and
	// answered in the space it matched: a shader that converted by hand drew every zombie a
	// shade from black at night.
	vec3 c = texture(atlas, UV).rgb;
	for (int i = 0; i < swaps; i++) {
		vec3 d = c - from_colour[i].rgb;
		if (dot(d, d) < tolerance) {
			c = to_colour[i].rgb;
			break;
		}
		vec3 e = c - from_linear[i].rgb;
		if (dot(e, e) < tolerance * 0.25) {
			c = to_linear[i].rgb;
			break;
		}
	}
	c *= mix(1.0, 0.6, smoothstep(0.45, 0.85, COLOR.r) * dirt);
	c *= mix(0.88, 1.05, COLOR.b);
	// Blood where two noises agree: splashes rather than a coat.
	float blood = smoothstep(blood_cut, blood_cut + 0.05, COLOR.g) * smoothstep(0.52, 0.6, COLOR.r);
	c = mix(c, blood_colour, blood * 0.85);
	// Bruises and sores: where the noises disagree with the blood, so the two never overlap.
	float mark = smoothstep(0.48, 0.56, COLOR.g) * (1.0 - smoothstep(0.45, 0.52, COLOR.r));
	c = mix(c, mark_colour, mark * mark_amount);
	// Veins, cracks and scars: the contour lines of a smooth field built from the skin-fixed
	// noises, so a flat-coloured body carries a pattern that moves with it and costs no texture.
	float field = COLOR.b * 11.0 + COLOR.r * 6.0 - COLOR.g * 5.0;
	float vein_d = abs(fract(field) - 0.5);
	float vein = (1.0 - smoothstep(0.012, 0.012 + 0.02 + fwidth(field), vein_d)) * smoothstep(0.5, 0.62, COLOR.b) * smoothstep(0.35, 0.5, COLOR.g) * (1.0 - blood);
	c = mix(c, vein_colour, vein * vein_amount);
	ALBEDO = c;
	ROUGHNESS = mix(0.9, 0.3, blood);
	// A little self-light so a dark skin on a night map keeps its legs, head and face: lit by
	// the moon alone the specials' charcoal bodies drew as black cones.
	EMISSION = c * lift + glow + vec3(flash * 0.35, flash * 0.05, flash * 0.03);
}
"""

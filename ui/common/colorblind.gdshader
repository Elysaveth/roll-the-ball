shader_type canvas_item;
// Daltonisation filter drawn over the whole screen.
//
// This does not merely SIMULATE colour blindness — it corrects for it. The
// simulation matrix says what a given eye cannot distinguish; the difference
// between the original colour and that simulation is the information being lost,
// and that error is pushed back into channels the eye can still see. The result is
// that colours which would have looked identical are pulled apart.
//
// Matrices are the Viénot/Brettel approximations, applied in linear space because
// they are defined for linear light; doing this on sRGB values skews the hues.

// 0 = off, 1 = protanopia, 2 = deuteranopia, 3 = tritanopia.
uniform int mode : hint_range(0, 3) = 0;
// 0 keeps the original image, 1 is the full correction.
uniform float strength : hint_range(0.0, 1.0) = 1.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

const mat3 PROTANOPIA = mat3(
	vec3(0.170556, 0.170556, -0.004517),
	vec3(0.829443, 0.829443, 0.004517),
	vec3(0.0, 0.0, 1.0)
);
const mat3 DEUTERANOPIA = mat3(
	vec3(0.330660, 0.330660, -0.027855),
	vec3(0.669339, 0.669339, 0.027855),
	vec3(0.0, 0.0, 1.0)
);
const mat3 TRITANOPIA = mat3(
	vec3(1.0, 0.0, 0.0),
	vec3(0.127398, 0.873909, 0.873909),
	vec3(-0.127398, 0.126090, 0.126090)
);

// Redistributes the lost information into the channels that still work.
const mat3 ERROR_SHIFT = mat3(
	vec3(0.0, 0.7, 0.7),
	vec3(0.0, 1.0, 0.0),
	vec3(0.0, 0.0, 1.0)
);

void fragment() {
	vec3 original = texture(screen_texture, SCREEN_UV).rgb;
	if (mode == 0) {
		COLOR = vec4(original, 1.0);
	} else {
		// sRGB -> linear, approximated; a full transfer curve is not worth the
		// branch cost here and the difference is imperceptible after clamping.
		vec3 linear_rgb = original * original;

		mat3 simulation = DEUTERANOPIA;
		if (mode == 1) {
			simulation = PROTANOPIA;
		} else if (mode == 3) {
			simulation = TRITANOPIA;
		}

		vec3 simulated = simulation * linear_rgb;
		vec3 corrected = linear_rgb + ERROR_SHIFT * (linear_rgb - simulated);
		corrected = sqrt(clamp(corrected, vec3(0.0), vec3(1.0)));
		COLOR = vec4(mix(original, corrected, strength), 1.0);
	}
}

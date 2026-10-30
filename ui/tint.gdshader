// Перекраска серой иконки в цвет материала: яркость формы × цвет, блики остаются светлыми.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float g = t.r;
	vec3 base = tint.rgb * g * 1.15;
	vec3 lit = mix(base, vec3(1.0), smoothstep(0.92, 1.0, g) * 0.55);
	COLOR = vec4(lit, t.a * tint.a);
}

@header const za = @import("zalgebra")
@ctype mat4 za.Mat4

@vs vs
layout(binding = 0) uniform vs_params {
    mat4 mvp;
};

in vec4 position;
in vec4 color0;

out vec4 color;
out vec3 frag_pos;

void main() {
    gl_Position = mvp * position;
    frag_pos = position.xyz;
    color = color0;
}
@end

@fs fs
in vec4 color;
in vec3 frag_pos;
out vec4 frag_color;

void main() {
    // Calculate normal from screen-space derivatives for flat shading
    vec3 dx = dFdx(frag_pos);
    vec3 dy = dFdy(frag_pos);
    vec3 n = normalize(cross(dx, dy));

    // Simple directional lighting (classic Quake style)
    vec3 light_dir = normalize(vec3(0.5, 1.0, 0.3));
    float diff = max(dot(n, light_dir), 0.0);

    // Ambient + diffuse (Quake had strong ambient)
    float ambient = 0.4;
    float lighting = ambient + diff * 0.6;

    frag_color = vec4(color.rgb * lighting, color.a);
}
@end

@program cube vs fs

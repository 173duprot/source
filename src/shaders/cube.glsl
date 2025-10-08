@header const za = @import("zalgebra")
@ctype mat4 za.Mat4

@vs vs
layout(binding = 0) uniform vs_params { mat4 mvp; };
in vec4 position; in vec4 color0;
out vec4 color; out vec3 frag_pos;
void main() { gl_Position = mvp * position; frag_pos = position.xyz; color = color0; }
@end

@fs fs
in vec4 color; in vec3 frag_pos; out vec4 frag_color;
void main() {
    vec3 n = normalize(cross(dFdx(frag_pos), dFdy(frag_pos)));
    float h = fract(sin(dot(n, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
    frag_color = vec4(color.rgb * (h * 0.8 + 0.2), color.a);
}
@end

@program cube vs fs

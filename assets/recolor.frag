// Recolor shader - maps grayscale emoji to target color
// Gray background becomes target color, white text stays white
in vec2 TexCoord;
out vec4 FragColor;
uniform sampler2D u_texture;
uniform vec4 u_target_color;  // target color (0-1 range, alpha ignored)

void main() {
    vec4 tex = texture(u_texture, TexCoord);

    // Grayscale value
    float gray = tex.r;

    // Background is 120/255 (~0.471), text is 1.0
    // Normalize: 0.471 -> 0, 1.0 -> 1
    float t = (gray - 0.471) / (1.0 - 0.471);
    t = clamp(t, 0.0, 1.0);

    // Mix target color -> white
    vec3 color = mix(u_target_color.rgb, vec3(1.0), t);

    FragColor = vec4(color, tex.a);
}

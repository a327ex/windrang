// Grayscale shader — luminance-based desaturation of the input texture.
// Preserves alpha. Used for the unaffordable shop-tile emoji so it reads
// as "off-limits" with no color, regardless of the source emoji's palette.
in vec2 TexCoord;
out vec4 FragColor;
uniform sampler2D u_texture;

void main() {
    vec4 tex = texture(u_texture, TexCoord);
    float lum = 0.299*tex.r + 0.587*tex.g + 0.114*tex.b;
    FragColor = vec4(lum, lum, lum, tex.a);
}

// Outline shader - samples neighbors to detect alpha edges
// Outputs black where any neighbor has alpha, creating silhouette outline
in vec2 TexCoord;
out vec4 FragColor;
uniform sampler2D u_texture;
uniform vec2 u_pixel_size;

void main() {
    // Sample center pixel
    vec4 center = texture(u_texture, TexCoord);

    // Sample 24 neighbors in 5x5 grid (excluding center)
    float x = u_pixel_size.x;
    float y = u_pixel_size.y;

    float a = 0.0;
    // Row -2
    a += texture(u_texture, TexCoord + vec2(-2.0*x, -2.0*y)).a;
    a += texture(u_texture, TexCoord + vec2(-1.0*x, -2.0*y)).a;
    a += texture(u_texture, TexCoord + vec2( 0.0,   -2.0*y)).a;
    a += texture(u_texture, TexCoord + vec2( 1.0*x, -2.0*y)).a;
    a += texture(u_texture, TexCoord + vec2( 2.0*x, -2.0*y)).a;
    // Row -1
    a += texture(u_texture, TexCoord + vec2(-2.0*x, -1.0*y)).a;
    a += texture(u_texture, TexCoord + vec2(-1.0*x, -1.0*y)).a;
    a += texture(u_texture, TexCoord + vec2( 0.0,   -1.0*y)).a;
    a += texture(u_texture, TexCoord + vec2( 1.0*x, -1.0*y)).a;
    a += texture(u_texture, TexCoord + vec2( 2.0*x, -1.0*y)).a;
    // Row 0 (skip center)
    a += texture(u_texture, TexCoord + vec2(-2.0*x,  0.0)).a;
    a += texture(u_texture, TexCoord + vec2(-1.0*x,  0.0)).a;
    // center skipped
    a += texture(u_texture, TexCoord + vec2( 1.0*x,  0.0)).a;
    a += texture(u_texture, TexCoord + vec2( 2.0*x,  0.0)).a;
    // Row +1
    a += texture(u_texture, TexCoord + vec2(-2.0*x,  1.0*y)).a;
    a += texture(u_texture, TexCoord + vec2(-1.0*x,  1.0*y)).a;
    a += texture(u_texture, TexCoord + vec2( 0.0,    1.0*y)).a;
    a += texture(u_texture, TexCoord + vec2( 1.0*x,  1.0*y)).a;
    a += texture(u_texture, TexCoord + vec2( 2.0*x,  1.0*y)).a;
    // Row +2
    a += texture(u_texture, TexCoord + vec2(-2.0*x,  2.0*y)).a;
    a += texture(u_texture, TexCoord + vec2(-1.0*x,  2.0*y)).a;
    a += texture(u_texture, TexCoord + vec2( 0.0,    2.0*y)).a;
    a += texture(u_texture, TexCoord + vec2( 1.0*x,  2.0*y)).a;
    a += texture(u_texture, TexCoord + vec2( 2.0*x,  2.0*y)).a;

    // Clamp to 0-1
    a = min(a, 1.0);

    // Output black outline where neighbors have alpha (but center doesn't)
    // This creates the silhouette effect
    FragColor = vec4(0.0, 0.0, 0.0, a);
}

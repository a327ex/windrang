// Outline-only shader - draws black only at edges (transparent pixels next to non-transparent)
// Unlike regular outline shader, this doesn't fill the interior
in vec2 TexCoord;
out vec4 FragColor;
uniform sampler2D u_texture;
uniform vec2 u_pixel_size;

void main() {
    // Sample center pixel
    vec4 center = texture(u_texture, TexCoord);

    // If center pixel is not transparent, output nothing (don't fill interior)
    if (center.a > 0.1) {
        FragColor = vec4(0.0, 0.0, 0.0, 0.0);
        return;
    }

    // Center is transparent - check if any neighbor is non-transparent
    float x = u_pixel_size.x;
    float y = u_pixel_size.y;

    float a = 0.0;

    // Sample 24 neighbors in 5x5 grid (excluding center) - matches outline.frag
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

    // If any neighbor has alpha, this is an edge pixel - draw black
    if (a > 0.1) {
        FragColor = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        FragColor = vec4(0.0, 0.0, 0.0, 0.0);
    }
}

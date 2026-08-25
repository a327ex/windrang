// Shadow shader - creates a dark, semi-transparent silhouette
// Draw this layer at an offset to create drop shadow effect

in vec2 TexCoord;
out vec4 FragColor;
uniform sampler2D u_texture;

void main() {
    float a = texture(u_texture, TexCoord).a;
    FragColor = vec4(0.5, 0.5, 0.5, a * 0.5);
}

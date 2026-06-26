#include "OverviewRoundedClip.hpp"

#include <hyprland/src/helpers/memory/Memory.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>

#include <GLES2/gl2ext.h>
#include <GLES3/gl32.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <optional>
#include <string>
#include <vector>

#ifndef GL_TEXTURE_EXTERNAL_OES
#define GL_TEXTURE_EXTERNAL_OES 0x8D65
#endif

#ifndef GL_TEXTURE_BINDING_EXTERNAL_OES
#define GL_TEXTURE_BINDING_EXTERNAL_OES 0x8D67
#endif

namespace {

class COverviewRoundedClipPassElement : public IPassElement {
  public:
    struct SData {
        SP<Render::ITexture> texture;
        CBox                 textureBox;
        CBox                 clipRoundedBox;
        CBox                 contentRoundedBox;
        float                opacity = 1.F;
        float                clipRadius = 0.F;
        float                contentRadius = 0.F;
    };

    COverviewRoundedClipPassElement(const SData& data) : m_data(data) {}

    std::vector<UP<IPassElement>> draw() override {
        render();
        return {};
    }

    bool needsLiveBlur() override {
        return false;
    }

    bool needsPrecomputeBlur() override {
        return false;
    }

    const char* passName() override {
        return "COverviewRoundedClipPassElement";
    }

    ePassElementType type() override {
        return EK_CUSTOM;
    }

    bool undiscardable() override {
        return true;
    }

    bool disableSimplification() override {
        return true;
    }

    std::optional<CBox> boundingBox() override {
        return m_data.textureBox;
    }

  private:
    struct SGLState {
        GLint program = 0;
        GLint arrayBuffer = 0;
        GLint vertexArray = 0;
        GLint activeTexture = 0;
        GLint texture2D = 0;
        GLint textureExternal = 0;
        GLboolean blend = GL_FALSE;
        GLboolean scissor = GL_FALSE;
        std::array<GLint, 4> scissorBox = {};
        std::array<GLint, 4> viewport = {};
        bool savedExternalTexture = false;
    };

    struct SProgramState {
        GLuint program = 0;
        GLint tex = -1;
        GLint proj = -1;
        GLint textureBox = -1;
        GLint clipRoundedBox = -1;
        GLint contentRoundedBox = -1;
        GLint clipRadius = -1;
        GLint contentRadius = -1;
        GLint opacity = -1;
    };

    struct SGeometryState {
        GLuint vao = 0;
        GLuint vbo = 0;
    };

    static GLuint compileShader(GLenum type, const char* source) {
        const GLuint shader = glCreateShader(type);
        glShaderSource(shader, 1, &source, nullptr);
        glCompileShader(shader);

        GLint ok = GL_FALSE;
        glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
        if (ok != GL_TRUE) {
            glDeleteShader(shader);
            return 0;
        }

        return shader;
    }

    static SProgramState createProgram(bool externalTexture) {
        constexpr const char* vertexSource = R"(#version 300 es
precision highp float;
layout(location = 0) in vec2 pos;
uniform mat3 proj;
uniform vec4 textureBox;
out vec2 screenPos;

void main() {
    screenPos = textureBox.xy + pos * textureBox.zw;
    gl_Position = vec4(proj * vec3(pos, 1.0), 1.0);
}
)";

        const std::string fragmentSource = std::string("#version 300 es\n") + (externalTexture ? "#extension GL_OES_EGL_image_external_essl3 : require\n" : "") + R"(
precision highp float;
in vec2 screenPos;
uniform )" + (externalTexture ? "samplerExternalOES" : "sampler2D") + R"( tex;
uniform vec4 textureBox;
uniform vec4 clipRoundedBox;
uniform vec4 contentRoundedBox;
uniform float clipRadius;
uniform float contentRadius;
uniform float opacity;
layout(location = 0) out vec4 fragColor;

float roundedDistance(vec2 point, vec4 box, float radius) {
    if (radius <= 1.0)
        return -1.0;

    vec2 halfSize = box.zw * 0.5;
    vec2 center = box.xy + halfSize;
    vec2 q = abs(point - center) - (halfSize - vec2(radius));
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void main() {
    float clipDist = roundedDistance(screenPos, clipRoundedBox, clipRadius);
    if (clipDist > 0.0)
        discard;

    float contentDist = roundedDistance(screenPos, contentRoundedBox, contentRadius);
    if (contentDist > 0.0)
        discard;

    vec2 uv = (screenPos - textureBox.xy) / textureBox.zw;
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0)
        discard;

    vec4 color = texture(tex, uv);
    float clipEdgeAlpha = 1.0 - smoothstep(-1.0, 0.0, clipDist);
    float contentEdgeAlpha = 1.0 - smoothstep(-1.0, 0.0, contentDist);
    float edgeAlpha = min(clipEdgeAlpha, contentEdgeAlpha);
    float alphaScale = opacity * edgeAlpha;
    float outAlpha = color.a * alphaScale;
    if (outAlpha <= 0.001)
        discard;

    fragColor = vec4(color.rgb * alphaScale, outAlpha);
}
)";

        const GLuint vertex = compileShader(GL_VERTEX_SHADER, vertexSource);
        if (!vertex)
            return {};

        const GLuint fragment = compileShader(GL_FRAGMENT_SHADER, fragmentSource.c_str());
        if (!fragment) {
            glDeleteShader(vertex);
            return {};
        }

        const GLuint program = glCreateProgram();
        glAttachShader(program, vertex);
        glAttachShader(program, fragment);
        glLinkProgram(program);
        glDeleteShader(vertex);
        glDeleteShader(fragment);

        GLint ok = GL_FALSE;
        glGetProgramiv(program, GL_LINK_STATUS, &ok);
        if (ok != GL_TRUE) {
            glDeleteProgram(program);
            return {};
        }

        return SProgramState{
            .program = program,
            .tex = glGetUniformLocation(program, "tex"),
            .proj = glGetUniformLocation(program, "proj"),
            .textureBox = glGetUniformLocation(program, "textureBox"),
            .clipRoundedBox = glGetUniformLocation(program, "clipRoundedBox"),
            .contentRoundedBox = glGetUniformLocation(program, "contentRoundedBox"),
            .clipRadius = glGetUniformLocation(program, "clipRadius"),
            .contentRadius = glGetUniformLocation(program, "contentRadius"),
            .opacity = glGetUniformLocation(program, "opacity"),
        };
    }

    static const SProgramState& programForTexture(Render::eTextureType textureType) {
        static SProgramState texture2DProgram;
        static SProgramState externalTextureProgram;

        if (textureType == Render::TEXTURE_EXTERNAL) {
            if (!externalTextureProgram.program)
                externalTextureProgram = createProgram(true);
            return externalTextureProgram;
        }

        if (!texture2DProgram.program)
            texture2DProgram = createProgram(false);
        return texture2DProgram;
    }

    static SGeometryState& geometryState() {
        static SGeometryState state;

        if (!state.vao)
            glGenVertexArrays(1, &state.vao);
        if (!state.vbo)
            glGenBuffers(1, &state.vbo);

        return state;
    }

    static void saveState(SGLState& state, GLenum textureTarget) {
        glGetIntegerv(GL_CURRENT_PROGRAM, &state.program);
        glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &state.arrayBuffer);
        glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &state.vertexArray);
        glGetIntegerv(GL_ACTIVE_TEXTURE, &state.activeTexture);
        glGetIntegerv(GL_VIEWPORT, state.viewport.data());
        glActiveTexture(GL_TEXTURE0);
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &state.texture2D);
        if (textureTarget == GL_TEXTURE_EXTERNAL_OES) {
            glGetIntegerv(GL_TEXTURE_BINDING_EXTERNAL_OES, &state.textureExternal);
            state.savedExternalTexture = true;
        }
        state.blend = glIsEnabled(GL_BLEND);
        state.scissor = glIsEnabled(GL_SCISSOR_TEST);
        glGetIntegerv(GL_SCISSOR_BOX, state.scissorBox.data());
        glDisable(GL_SCISSOR_TEST);
    }

    static void restoreState(const SGLState& state) {
        if (state.blend)
            glEnable(GL_BLEND);
        else
            glDisable(GL_BLEND);
        if (state.scissor)
            glEnable(GL_SCISSOR_TEST);
        else
            glDisable(GL_SCISSOR_TEST);

        glScissor(state.scissorBox[0], state.scissorBox[1], state.scissorBox[2], state.scissorBox[3]);
        glViewport(state.viewport[0], state.viewport[1], state.viewport[2], state.viewport[3]);
        glUseProgram(state.program);
        glBindBuffer(GL_ARRAY_BUFFER, state.arrayBuffer);
        glBindVertexArray(state.vertexArray);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, state.texture2D);
        if (state.savedExternalTexture)
            glBindTexture(GL_TEXTURE_EXTERNAL_OES, state.textureExternal);
        glActiveTexture(state.activeTexture);
    }

    void render() {
        if (!m_data.texture || !(m_data.opacity > 0.F) || !(m_data.clipRadius > 0.F || m_data.contentRadius > 0.F))
            return;
        if (!(m_data.textureBox.w > 0.5 && m_data.textureBox.h > 0.5 && m_data.clipRoundedBox.w > 0.5 && m_data.clipRoundedBox.h > 0.5 && m_data.contentRoundedBox.w > 0.5 && m_data.contentRoundedBox.h > 0.5))
            return;

        const SProgramState& program = programForTexture(m_data.texture->m_type);
        if (!program.program)
            return;

        const GLenum textureTarget = m_data.texture->m_type == Render::TEXTURE_EXTERNAL ? GL_TEXTURE_EXTERNAL_OES : GL_TEXTURE_2D;
        SGLState state;
        saveState(state, textureTarget);

        constexpr std::array<float, 12> vertices = {
            0.F, 0.F,
            0.F, 1.F,
            1.F, 0.F,
            1.F, 0.F,
            0.F, 1.F,
            1.F, 1.F,
        };

        SGeometryState& geometry = geometryState();
        glBindVertexArray(geometry.vao);
        glBindBuffer(GL_ARRAY_BUFFER, geometry.vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.size() * sizeof(float), vertices.data(), GL_STREAM_DRAW);

        glUseProgram(program.program);
        glEnable(GL_BLEND);
        m_data.texture->bind();

        const auto projection = g_pHyprRenderer->projectBoxToTarget(m_data.textureBox).getMatrix();
        glUniform1i(program.tex, 0);
        glUniformMatrix3fv(program.proj, 1, GL_TRUE, projection.data());
        glUniform4f(program.textureBox, m_data.textureBox.x, m_data.textureBox.y, m_data.textureBox.w, m_data.textureBox.h);
        glUniform4f(program.clipRoundedBox, m_data.clipRoundedBox.x, m_data.clipRoundedBox.y, m_data.clipRoundedBox.w, m_data.clipRoundedBox.h);
        glUniform4f(program.contentRoundedBox, m_data.contentRoundedBox.x, m_data.contentRoundedBox.y, m_data.contentRoundedBox.w, m_data.contentRoundedBox.h);
        glUniform1f(program.clipRadius, m_data.clipRadius);
        glUniform1f(program.contentRadius, m_data.contentRadius);
        glUniform1f(program.opacity, std::clamp(m_data.opacity, 0.F, 1.F));

        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), nullptr);
        glDrawArrays(GL_TRIANGLES, 0, vertices.size() / 2);
        glDisableVertexAttribArray(0);

        restoreState(state);
    }

    SData m_data;
};

} // namespace

bool renderRoundedClippedTexture(
    SP<Render::ITexture> texture,
    const CBox& textureBox,
    const CBox& clipRoundedBox,
    int clipRounding,
    const CBox& contentRoundedBox,
    int contentRounding,
    float opacity) {
    if (!texture || opacity <= 0.F)
        return false;

    const double clipRadius = std::min<double>(std::max(0, clipRounding), std::floor(std::min(clipRoundedBox.w, clipRoundedBox.h) * 0.5));
    const double contentRadius = std::min<double>(std::max(0, contentRounding), std::floor(std::min(contentRoundedBox.w, contentRoundedBox.h) * 0.5));
    if (clipRadius <= 1.0 && contentRadius <= 1.0)
        return false;

    COverviewRoundedClipPassElement::SData data;
    data.texture = texture;
    data.textureBox = textureBox;
    data.clipRoundedBox = clipRoundedBox;
    data.contentRoundedBox = contentRoundedBox;
    data.opacity = std::clamp(opacity, 0.F, 1.F);
    data.clipRadius = static_cast<float>(clipRadius);
    data.contentRadius = static_cast<float>(contentRadius);
    g_pHyprRenderer->m_renderPass.add(makeUnique<COverviewRoundedClipPassElement>(data));
    return true;
}

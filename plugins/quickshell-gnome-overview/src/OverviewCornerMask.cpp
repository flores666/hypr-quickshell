#include "OverviewCornerMask.hpp"

#include <hyprland/src/helpers/memory/Memory.hpp>
#include <hyprland/src/render/Texture.hpp>
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

class COverviewCornerMaskPassElement : public IPassElement {
  public:
    struct SData {
        SP<Render::ITexture> texture;
        CBox                 workspaceBox;
        CBox                 layerBox;
        float                radius = 0.F;
        float                opacity = 1.F;
        float                dimAlpha = 0.F;
    };

    COverviewCornerMaskPassElement(const SData& data) : m_data(data) {}

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
        return "COverviewCornerMaskPassElement";
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
        return m_data.workspaceBox;
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
        bool savedExternalTexture = false;
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

    static GLuint createProgram(bool externalTexture) {
        constexpr const char* vertexSource = R"(#version 300 es
precision highp float;
layout(location = 0) in vec2 pos;
uniform mat3 proj;
uniform vec4 workspaceBox;
out vec2 screenPos;

void main() {
    screenPos = workspaceBox.xy + pos * workspaceBox.zw;
    gl_Position = vec4(proj * vec3(pos, 1.0), 1.0);
}
)";

        const std::string fragmentSource = std::string("#version 300 es\n") + (externalTexture ? "#extension GL_OES_EGL_image_external_essl3 : require\n" : "") + R"(
precision highp float;
in vec2 screenPos;
uniform )" + (externalTexture ? "samplerExternalOES" : "sampler2D") + R"( tex;
uniform vec4 workspaceBox;
uniform vec4 layerBox;
uniform float radius;
uniform float opacity;
uniform float dimAlpha;
layout(location = 0) out vec4 fragColor;

float roundedRectOutsideAlpha(vec2 point) {
    vec2 halfSize = workspaceBox.zw * 0.5;
    vec2 center = workspaceBox.xy + halfSize;
    vec2 q = abs(point - center) - (halfSize - vec2(radius));
    float dist = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    return smoothstep(-1.0, 1.0, dist);
}

void main() {
    vec2 uv = (screenPos - layerBox.xy) / layerBox.zw;
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0)
        discard;

    float mask = roundedRectOutsideAlpha(screenPos) * opacity;
    if (mask <= 0.001)
        discard;

    vec4 color = texture(tex, uv);
    color.rgb *= 1.0 - dimAlpha;
    fragColor = vec4(color.rgb * mask, mask);
}
)";

        const GLuint vertex = compileShader(GL_VERTEX_SHADER, vertexSource);
        if (!vertex)
            return 0;

        const GLuint fragment = compileShader(GL_FRAGMENT_SHADER, fragmentSource.c_str());
        if (!fragment) {
            glDeleteShader(vertex);
            return 0;
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
            return 0;
        }

        return program;
    }

    static GLuint programForTexture(Render::eTextureType textureType) {
        static GLuint texture2DProgram = 0;
        static GLuint externalTextureProgram = 0;

        if (textureType == Render::TEXTURE_EXTERNAL) {
            if (!externalTextureProgram)
                externalTextureProgram = createProgram(true);
            return externalTextureProgram;
        }

        if (!texture2DProgram)
            texture2DProgram = createProgram(false);
        return texture2DProgram;
    }

    static void saveState(SGLState& state, GLenum textureTarget) {
        glGetIntegerv(GL_CURRENT_PROGRAM, &state.program);
        glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &state.arrayBuffer);
        glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &state.vertexArray);
        glGetIntegerv(GL_ACTIVE_TEXTURE, &state.activeTexture);
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
        if (!m_data.texture || !(m_data.radius > 0.F) || !(m_data.opacity > 0.F))
            return;
        if (!(m_data.workspaceBox.w > 0.0 && m_data.workspaceBox.h > 0.0 && m_data.layerBox.w > 0.0 && m_data.layerBox.h > 0.0))
            return;

        const GLuint program = programForTexture(m_data.texture->m_type);
        if (!program)
            return;

        const GLenum textureTarget = m_data.texture->m_type == Render::TEXTURE_EXTERNAL ? GL_TEXTURE_EXTERNAL_OES : GL_TEXTURE_2D;
        SGLState state;
        saveState(state, textureTarget);

        std::array<float, 48> vertices;
        size_t offset = 0;
        const float radius = m_data.radius;
        const auto addQuad = [&](float x, float y, float w, float h) {
            const float left = (x - m_data.workspaceBox.x) / m_data.workspaceBox.w;
            const float top = (y - m_data.workspaceBox.y) / m_data.workspaceBox.h;
            const float right = (x + w - m_data.workspaceBox.x) / m_data.workspaceBox.w;
            const float bottom = (y + h - m_data.workspaceBox.y) / m_data.workspaceBox.h;
            const std::array<float, 12> quad = {
                left, top,
                left, bottom,
                right, top,
                right, top,
                left, bottom,
                right, bottom,
            };

            std::copy(quad.begin(), quad.end(), vertices.begin() + offset);
            offset += quad.size();
        };

        addQuad(m_data.workspaceBox.x, m_data.workspaceBox.y, radius, radius);
        addQuad(m_data.workspaceBox.x + m_data.workspaceBox.w - radius, m_data.workspaceBox.y, radius, radius);
        addQuad(m_data.workspaceBox.x, m_data.workspaceBox.y + m_data.workspaceBox.h - radius, radius, radius);
        addQuad(m_data.workspaceBox.x + m_data.workspaceBox.w - radius, m_data.workspaceBox.y + m_data.workspaceBox.h - radius, radius, radius);

        GLuint vao = 0;
        GLuint vbo = 0;
        glGenVertexArrays(1, &vao);
        glGenBuffers(1, &vbo);
        glBindVertexArray(vao);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.size() * sizeof(float), vertices.data(), GL_STREAM_DRAW);

        glUseProgram(program);
        glEnable(GL_BLEND);
        m_data.texture->bind();
        const auto projection = g_pHyprRenderer->projectBoxToTarget(m_data.workspaceBox).getMatrix();
        glUniform1i(glGetUniformLocation(program, "tex"), 0);
        glUniformMatrix3fv(glGetUniformLocation(program, "proj"), 1, GL_TRUE, projection.data());
        glUniform4f(glGetUniformLocation(program, "workspaceBox"), m_data.workspaceBox.x, m_data.workspaceBox.y, m_data.workspaceBox.w, m_data.workspaceBox.h);
        glUniform4f(glGetUniformLocation(program, "layerBox"), m_data.layerBox.x, m_data.layerBox.y, m_data.layerBox.w, m_data.layerBox.h);
        glUniform1f(glGetUniformLocation(program, "radius"), m_data.radius);
        glUniform1f(glGetUniformLocation(program, "opacity"), std::clamp(m_data.opacity, 0.F, 1.F));
        glUniform1f(glGetUniformLocation(program, "dimAlpha"), std::clamp(m_data.dimAlpha, 0.F, 1.F));

        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), nullptr);
        glDrawArrays(GL_TRIANGLES, 0, vertices.size() / 2);
        glDisableVertexAttribArray(0);

        glDeleteBuffers(1, &vbo);
        glDeleteVertexArrays(1, &vao);
        restoreState(state);
    }

    SData m_data;
};

} // namespace

bool renderOverviewCornerMask(PHLMONITOR pMonitor, const CBox& workspaceBox, float opacity, int rounding, double dimAlpha) {
    if (!pMonitor || opacity < 0.98F)
        return true;

    const double radius = std::min<double>(std::max(0, rounding), std::floor(std::min(workspaceBox.w, workspaceBox.h) * 0.5));
    if (radius <= 1.0)
        return true;

    for (auto& ls : pMonitor->m_layerSurfaceLayers[0]) {
        if (!ls)
            continue;

        const auto layer = ls.lock();
        if (!layer)
            continue;
        if (!layer->m_mapped || layer->m_readyToDelete || !layer->m_layerSurface || !layer->wlSurface() || !layer->wlSurface()->resource())
            continue;

        const auto surface = layer->wlSurface()->resource();
        if (!surface->m_current.texture)
            continue;

        const Vector2D layerPos = (layer->m_realPosition->value() - pMonitor->m_position) * pMonitor->m_scale;
        const Vector2D layerSize = layer->m_realSize->value() * pMonitor->m_scale;
        if (!(layerSize.x > 1.0 && layerSize.y > 1.0))
            continue;

        COverviewCornerMaskPassElement::SData data;
        data.texture = surface->m_current.texture;
        data.workspaceBox = workspaceBox;
        data.layerBox = CBox{layerPos, layerSize};
        data.radius = static_cast<float>(radius);
        data.opacity = std::clamp(opacity, 0.F, 1.F);
        data.dimAlpha = std::clamp(static_cast<float>(dimAlpha), 0.F, 1.F);
        g_pHyprRenderer->m_renderPass.add(makeUnique<COverviewCornerMaskPassElement>(data));
        return true;
    }

    return false;
}

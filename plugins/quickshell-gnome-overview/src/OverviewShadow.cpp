#include "OverviewShadow.hpp"

#include <hyprland/src/helpers/memory/Memory.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>

#include <GLES3/gl32.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <optional>
#include <string>
#include <vector>

namespace {

class COverviewShadowPassElement : public IPassElement {
  public:
    struct SData {
        CBox  workspaceBox;
        CBox  shadowBox;
        float radius = 0.F;
        float range = 0.F;
        float alpha = 1.F;
    };

    COverviewShadowPassElement(const SData& data) : m_data(data) {}

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
        return "COverviewShadowPassElement";
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
        return m_data.shadowBox;
    }

  private:
    struct SGLState {
        GLint program = 0;
        GLint arrayBuffer = 0;
        GLint vertexArray = 0;
        GLint activeTexture = 0;
        GLboolean blend = GL_FALSE;
        GLboolean scissor = GL_FALSE;
        std::array<GLint, 4> scissorBox = {};
    };

    struct SProgramState {
        GLuint program = 0;
        GLint proj = -1;
        GLint shadowBox = -1;
        GLint workspaceBox = -1;
        GLint radius = -1;
        GLint range = -1;
        GLint alpha = -1;
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

    static SProgramState createProgram() {
        constexpr const char* vertexSource = R"(#version 300 es
precision highp float;
layout(location = 0) in vec2 pos;
uniform mat3 proj;
uniform vec4 shadowBox;
out vec2 screenPos;

void main() {
    screenPos = shadowBox.xy + pos * shadowBox.zw;
    gl_Position = vec4(proj * vec3(pos, 1.0), 1.0);
}
)";

        constexpr const char* fragmentSource = R"(#version 300 es
precision highp float;
in vec2 screenPos;
uniform vec4 workspaceBox;
uniform float radius;
uniform float range;
uniform float alpha;
layout(location = 0) out vec4 fragColor;

float roundedRectDistance(vec2 point) {
    vec2 halfSize = workspaceBox.zw * 0.5;
    vec2 center = workspaceBox.xy + halfSize;
    vec2 q = abs(point - center) - (halfSize - vec2(radius));
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void main() {
    float dist = roundedRectDistance(screenPos);
    if (dist <= 0.0)
        discard;

    float outer = 1.0 - smoothstep(0.0, range, dist);
    if (outer <= 0.001)
        discard;

    float falloff = outer * outer;
    vec3 color = vec3(0.0, 0.0, 0.0);
    float a = falloff * alpha;
    fragColor = vec4(color * a, a);
}
)";

        const GLuint vertex = compileShader(GL_VERTEX_SHADER, vertexSource);
        if (!vertex)
            return {};

        const GLuint fragment = compileShader(GL_FRAGMENT_SHADER, fragmentSource);
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
            .proj = glGetUniformLocation(program, "proj"),
            .shadowBox = glGetUniformLocation(program, "shadowBox"),
            .workspaceBox = glGetUniformLocation(program, "workspaceBox"),
            .radius = glGetUniformLocation(program, "radius"),
            .range = glGetUniformLocation(program, "range"),
            .alpha = glGetUniformLocation(program, "alpha"),
        };
    }

    static const SProgramState& programState() {
        static SProgramState state;

        if (!state.program)
            state = createProgram();

        return state;
    }

    static SGeometryState& geometryState() {
        static SGeometryState state;

        if (!state.vao)
            glGenVertexArrays(1, &state.vao);
        if (!state.vbo)
            glGenBuffers(1, &state.vbo);

        return state;
    }

    static void saveState(SGLState& state) {
        glGetIntegerv(GL_CURRENT_PROGRAM, &state.program);
        glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &state.arrayBuffer);
        glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &state.vertexArray);
        glGetIntegerv(GL_ACTIVE_TEXTURE, &state.activeTexture);
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
        glActiveTexture(state.activeTexture);
    }

    void render() {
        if (!(m_data.shadowBox.w > 1.0 && m_data.shadowBox.h > 1.0) || !(m_data.range > 1.F) || !(m_data.alpha > 0.F))
            return;

        const SProgramState& program = programState();
        if (!program.program)
            return;

        SGLState state;
        saveState(state);

        const std::array<float, 12> vertices = {
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
        glBufferData(GL_ARRAY_BUFFER, vertices.size() * sizeof(float), vertices.data(), GL_STATIC_DRAW);

        glUseProgram(program.program);
        glEnable(GL_BLEND);
        const auto projection = g_pHyprRenderer->projectBoxToTarget(m_data.shadowBox).getMatrix();
        glUniformMatrix3fv(program.proj, 1, GL_TRUE, projection.data());
        glUniform4f(program.shadowBox, m_data.shadowBox.x, m_data.shadowBox.y, m_data.shadowBox.w, m_data.shadowBox.h);
        glUniform4f(program.workspaceBox, m_data.workspaceBox.x, m_data.workspaceBox.y, m_data.workspaceBox.w, m_data.workspaceBox.h);
        glUniform1f(program.radius, m_data.radius);
        glUniform1f(program.range, m_data.range);
        glUniform1f(program.alpha, std::clamp(m_data.alpha, 0.F, 1.F));

        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), nullptr);
        glDrawArrays(GL_TRIANGLES, 0, vertices.size() / 2);
        glDisableVertexAttribArray(0);

        restoreState(state);
    }

    SData m_data;
};

} // namespace

void renderWorkspacePreviewShadow(PHLMONITOR pMonitor, const CBox& workspaceBox, int rounding, float opacity) {
    if (!pMonitor || !(workspaceBox.w > 1.0 && workspaceBox.h > 1.0) || rounding <= 0 || opacity <= 0.001F)
        return;

    const double scale = std::max(1.0, static_cast<double>(pMonitor->m_scale));
    const double range = std::max(14.0, std::round(26.0 * scale));
    const double margin = range + 2.0;

    COverviewShadowPassElement::SData data;
    data.workspaceBox = workspaceBox;
    data.shadowBox = CBox{
        workspaceBox.x - margin,
        workspaceBox.y - margin,
        workspaceBox.w + margin * 2.0,
        workspaceBox.h + margin * 2.0,
    };
    data.radius = static_cast<float>(rounding);
    data.range = static_cast<float>(range);
    data.alpha = std::clamp(opacity, 0.F, 1.F) * 0.26F;
    g_pHyprRenderer->m_renderPass.add(makeUnique<COverviewShadowPassElement>(data));
}

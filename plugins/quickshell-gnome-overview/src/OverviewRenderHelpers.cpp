#include "OverviewRenderHelpers.hpp"

#include <hyprland/src/helpers/memory/Memory.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>
#include <hyprland/src/render/pass/RendererHintsPassElement.hpp>
#include <hyprland/src/render/pass/SurfacePassElement.hpp>
#include <hyprland/src/render/pass/TexPassElement.hpp>
#include <hyprutils/utils/ScopeGuard.hpp>

#include <algorithm>
#include <any>
#include <cmath>

static bool boxesIntersectForOverview(const CBox& a, const CBox& b) {
    return a.x < b.x + b.w &&
        a.x + a.w > b.x &&
        a.y < b.y + b.h &&
        a.y + a.h > b.y;
}

void renderRect(CBox box, CHyprColor color, int rounding, float roundingPower) {
    CRectPassElement::SRectData rectdata;
    rectdata.color = color;
    rectdata.box = box;
    rectdata.round = rounding;
    rectdata.roundingPower = roundingPower;
    g_pHyprRenderer->m_renderPass.add(makeUnique<CRectPassElement>(rectdata));
}

void renderRectWithBlur(CBox box, CHyprColor color, int rounding, float roundingPower) {
    CRectPassElement::SRectData rectdata;
    rectdata.color = color;
    rectdata.box = box;
    rectdata.round = rounding;
    rectdata.roundingPower = roundingPower;
    rectdata.blur = true;
    g_pHyprRenderer->m_renderPass.add(makeUnique<CRectPassElement>(rectdata));
}

void renderWindowStub(PHLWINDOW pWindow, PHLMONITOR pMonitor, PHLWORKSPACE pWorkspaceOverride, CBox rectOverride, CBox clipBox, const Time::steady_tp& time, float alpha, int forcedRounding, float forcedRoundingPower) {
    if (!pWindow || !pMonitor || !pWorkspaceOverride) return;
    if (!pWindow->m_isMapped || !pWindow->wlSurface() || !pWindow->wlSurface()->resource()) return;

    const auto oSize = pWindow->m_realSize->value();
    const float logicalW = std::max((float)oSize.x, 5.F);
    const float logicalH = std::max((float)oSize.y, 5.F);
    const float scaleX = rectOverride.w / logicalW;
    const float scaleY = rectOverride.h / logicalH;
    if (!(scaleX > 0.F) || !(scaleY > 0.F) || !(rectOverride.w > 0 && rectOverride.h > 0)) return;

    const int windowRounding = forcedRounding >= 0
        ? forcedRounding
        : (pWindow->isEffectiveInternalFSMode(FSMODE_FULLSCREEN) ? 0 : static_cast<int>(std::round(pWindow->rounding() * scaleX)));
    const float windowRoundingPower = forcedRounding >= 0 ? forcedRoundingPower : pWindow->roundingPower();

    pWindow->wlSurface()->resource()->breadthfirst(
        [&](SP<CWLSurfaceResource> s, const Vector2D& offset, void*) {
            if (!s || !s->m_current.texture)
                return;

            if (s->m_current.size.x < 1 || s->m_current.size.y < 1)
                return;

            const bool mainSurface = s == pWindow->wlSurface()->resource();
            CBox surfaceBox = rectOverride;
            int rounding = windowRounding;
            float roundingPower = windowRoundingPower;

            if (!mainSurface) {
                surfaceBox = CBox{
                    rectOverride.x + offset.x * scaleX,
                    rectOverride.y + offset.y * scaleY,
                    std::max<double>(2.0, s->m_current.size.x * scaleX),
                    std::max<double>(2.0, s->m_current.size.y * scaleY),
                };
                rounding = 0;
                roundingPower = 2.0F;
            }

            if (!(surfaceBox.w > 0.5 && surfaceBox.h > 0.5) || !boxesIntersectForOverview(surfaceBox, clipBox))
                return;

            CTexPassElement::SRenderData renderData;
            renderData.tex = s->m_current.texture;
            renderData.box = surfaceBox;
            renderData.a = std::clamp(alpha, 0.F, 1.F);
            renderData.round = rounding;
            renderData.roundingPower = roundingPower;
            renderData.clipBox = clipBox;
            renderData.surface = s;
            renderData.discardMode = DISCARD_ALPHA;
            g_pHyprRenderer->m_renderPass.add(makeUnique<CTexPassElement>(renderData));
        },
        nullptr);
}

void renderLayerSurfaceStub(PHLLS pLayer, PHLMONITOR pMonitor, CBox rectOverride, CBox clipBox, const Time::steady_tp& time, float alpha, int rounding, float roundingPower) {
    if (!pLayer || !pMonitor) return;

    if (!pLayer->m_mapped || pLayer->m_readyToDelete || !pLayer->m_layerSurface || !pLayer->wlSurface() || !pLayer->wlSurface()->resource()) return;

    Vector2D oRealPosition = pLayer->m_realPosition->value();
    Vector2D oSize = pLayer->m_realSize->value();

    const float curScaling = rectOverride.w / (oSize.x);
    if (!(curScaling > 0.F) || !(rectOverride.w > 0 && rectOverride.h > 0)) return;

    Render::SRenderModifData renderModif;

    renderModif.modifs.push_back(std::make_pair(Render::SRenderModifData::eRenderModifType::RMOD_TYPE_TRANSLATE, std::any(pMonitor->m_position + (rectOverride.pos() / curScaling) - oRealPosition)));
    renderModif.modifs.push_back(std::make_pair(Render::SRenderModifData::eRenderModifType::RMOD_TYPE_SCALE, std::any(curScaling)));
    renderModif.enabled = true;

    g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{.renderModif = renderModif}));
    Hyprutils::Utils::CScopeGuard x([] {
        g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{.renderModif = Render::SRenderModifData{}}));
    });

    CSurfacePassElement::SRenderData renderdata = {pMonitor, time, oRealPosition};
    renderdata.fadeAlpha = std::clamp(alpha, 0.F, 1.F);
    renderdata.alpha = std::clamp(alpha, 0.F, 1.F);
    renderdata.blur = false;
    renderdata.surface = pLayer->wlSurface()->resource();
    renderdata.decorate = false;
    renderdata.w = oSize.x;
    renderdata.h = oSize.y;
    renderdata.pLS = pLayer;
    renderdata.clipBox = clipBox;
    renderdata.rounding = rounding;
    renderdata.roundingPower = roundingPower;
    renderdata.surfaceCounter = 0;

    pLayer->wlSurface()->resource()->breadthfirst(
        [&renderdata, &pLayer](SP<CWLSurfaceResource> s, const Vector2D& offset, void*) {
            if (!s || !s->m_current.texture)
                return;

            if (s->m_current.size.x < 1 || s->m_current.size.y < 1)
                return;

            renderdata.localPos = offset;
            renderdata.texture = s->m_current.texture;
            renderdata.surface = s;
            renderdata.mainSurface = s == pLayer->wlSurface()->resource();
            g_pHyprRenderer->m_renderPass.add(makeUnique<CSurfacePassElement>(renderdata));
            renderdata.surfaceCounter++;
        },
        &renderdata);
}

void renderLayerSurfaceTextureStub(PHLLS pLayer, CBox rectOverride, CBox clipBox, float alpha, int rounding, float roundingPower) {
    if (!pLayer)
        return;

    if (!pLayer->m_mapped || pLayer->m_readyToDelete || !pLayer->m_layerSurface || !pLayer->wlSurface() || !pLayer->wlSurface()->resource())
        return;

    const Vector2D sourceSize = pLayer->m_realSize->value();
    const float sourceW = std::max((float)sourceSize.x, 1.F);
    const float sourceH = std::max((float)sourceSize.y, 1.F);
    const float scaleX = rectOverride.w / sourceW;
    const float scaleY = rectOverride.h / sourceH;
    if (!(scaleX > 0.F) || !(scaleY > 0.F) || !(rectOverride.w > 0.5 && rectOverride.h > 0.5))
        return;

    pLayer->wlSurface()->resource()->breadthfirst(
        [&](SP<CWLSurfaceResource> surface, const Vector2D& offset, void*) {
            if (!surface || !surface->m_current.texture)
                return;

            if (surface->m_current.size.x < 1 || surface->m_current.size.y < 1)
                return;

            const bool mainSurface = surface == pLayer->wlSurface()->resource();
            CBox surfaceBox = mainSurface
                ? rectOverride
                : CBox{
                    rectOverride.x + offset.x * scaleX,
                    rectOverride.y + offset.y * scaleY,
                    std::max<double>(2.0, surface->m_current.size.x * scaleX),
                    std::max<double>(2.0, surface->m_current.size.y * scaleY),
                };

            if (!(surfaceBox.w > 0.5 && surfaceBox.h > 0.5) || !boxesIntersectForOverview(surfaceBox, clipBox))
                return;

            CTexPassElement::SRenderData renderData;
            renderData.tex = surface->m_current.texture;
            renderData.box = surfaceBox;
            renderData.a = std::clamp(alpha, 0.F, 1.F);
            renderData.round = mainSurface ? rounding : 0;
            renderData.roundingPower = mainSurface ? roundingPower : 2.0F;
            renderData.clipBox = clipBox;
            renderData.surface = surface;
            renderData.discardMode = DISCARD_ALPHA;
            g_pHyprRenderer->m_renderPass.add(makeUnique<CTexPassElement>(renderData));
        },
        nullptr);
}

bool renderFullscreenBackground(PHLMONITOR pMonitor, const CBox& monitorClip, const Time::steady_tp& time) {
    if (!pMonitor)
        return false;

    bool rendered = false;
    for (auto& ls : pMonitor->m_layerSurfaceLayers[0]) {
        if (!ls)
            continue;

        const auto layer = ls.lock();
        if (!layer)
            continue;
        if (layer->m_namespace == "quickshell:applications")
            continue;
        if (!layer->m_mapped || layer->m_readyToDelete || !layer->m_layerSurface || !layer->wlSurface() || !layer->wlSurface()->resource())
            continue;

        const auto surface = layer->wlSurface()->resource();
        if (!surface->m_current.texture)
            continue;
        if (surface->m_current.size.x < 1 || surface->m_current.size.y < 1)
            continue;

        const Vector2D layerPos = (layer->m_realPosition->value() - pMonitor->m_position) * pMonitor->m_scale;
        const Vector2D layerSize = layer->m_realSize->value() * pMonitor->m_scale;
        if (!(layerSize.x > 1 && layerSize.y > 1))
            continue;

        renderLayerSurfaceStub(layer, pMonitor, CBox{layerPos, layerSize}, monitorClip, time);
        rendered = true;
    }

    return rendered;
}

bool renderWorkspaceBackgroundTexture(PHLMONITOR pMonitor, const CBox& workspaceBox, const CBox& clipBox, float alpha, int rounding, float roundingPower) {
    if (!pMonitor)
        return false;

    for (auto& ls : pMonitor->m_layerSurfaceLayers[0]) {
        if (!ls)
            continue;

        const auto layer = ls.lock();
        if (!layer)
            continue;
        if (layer->m_namespace == "quickshell:applications")
            continue;
        if (!layer->m_mapped || layer->m_readyToDelete || !layer->m_layerSurface || !layer->wlSurface() || !layer->wlSurface()->resource())
            continue;

        const auto surface = layer->wlSurface()->resource();
        if (!surface->m_current.texture)
            continue;

        if (surface->m_current.size.x < 1 || surface->m_current.size.y < 1)
            continue;

        CTexPassElement::SRenderData renderData;
        renderData.tex = surface->m_current.texture;
        renderData.box = workspaceBox;
        renderData.a = std::clamp(alpha, 0.F, 1.F);
        renderData.round = rounding;
        renderData.roundingPower = roundingPower;
        renderData.clipBox = clipBox;
        renderData.surface = surface;
        g_pHyprRenderer->m_renderPass.add(makeUnique<CTexPassElement>(renderData));
        return true;
    }

    return false;
}

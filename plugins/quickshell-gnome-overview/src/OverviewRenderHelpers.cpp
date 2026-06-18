#include "OverviewRenderHelpers.hpp"

#include <hyprland/src/helpers/memory/Memory.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>
#include <hyprland/src/render/pass/RendererHintsPassElement.hpp>
#include <hyprland/src/render/pass/SurfacePassElement.hpp>
#include <hyprland/src/render/pass/TexPassElement.hpp>
#include <hyprutils/utils/ScopeGuard.hpp>

#include <algorithm>
#include <any>

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

    Render::SRenderModifData renderModif;

    const auto oRealPosition = pWindow->m_realPosition->value();
    const auto oSize = pWindow->m_realSize->value();
    const float logicalW = std::max((float)oSize.x, 5.F);
    const float scaleMod = rectOverride.w / std::max(logicalW * pMonitor->m_scale, 5.F);
    if (!(scaleMod > 0.F) || !(rectOverride.w > 0 && rectOverride.h > 0)) return;

    const Vector2D logicalTL = oRealPosition + pWindow->m_floatingOffset;
    const Vector2D scaledTL = (logicalTL - pMonitor->m_position) * pMonitor->m_scale;
    const Vector2D translate = rectOverride.pos() / scaleMod - scaledTL;

    renderModif.modifs.push_back(std::make_pair(Render::SRenderModifData::eRenderModifType::RMOD_TYPE_TRANSLATE, std::any(translate)));
    renderModif.modifs.push_back(std::make_pair(Render::SRenderModifData::eRenderModifType::RMOD_TYPE_SCALE, std::any(scaleMod)));
    renderModif.enabled = true;

    g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{.renderModif = renderModif}));
    Hyprutils::Utils::CScopeGuard x([] {
        g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{.renderModif = Render::SRenderModifData{}}));
    });

    CSurfacePassElement::SRenderData renderdata = {pMonitor, time};
    renderdata.pos = oRealPosition + pWindow->m_floatingOffset;
    renderdata.w = std::max(oSize.x, 5.0);
    renderdata.h = std::max(oSize.y, 5.0);
    renderdata.surface = pWindow->wlSurface()->resource();
    renderdata.dontRound = forcedRounding < 0 && pWindow->isEffectiveInternalFSMode(FSMODE_FULLSCREEN);
    renderdata.fadeAlpha = std::clamp(alpha, 0.F, 1.F);
    renderdata.alpha = std::clamp(alpha, 0.F, 1.F);
    renderdata.decorate = false;
    renderdata.rounding = renderdata.dontRound ? 0 : pWindow->rounding() * scaleMod * pMonitor->m_scale;
    renderdata.roundingPower = renderdata.dontRound ? 2.0F : pWindow->roundingPower();
    if (forcedRounding >= 0) {
        renderdata.rounding = static_cast<decltype(renderdata.rounding)>(forcedRounding);
        renderdata.roundingPower = forcedRoundingPower;
    }
    renderdata.blur = false;
    renderdata.pWindow = pWindow;
    renderdata.clipBox = clipBox;
    renderdata.useNearestNeighbor = false;
    renderdata.squishOversized = true;
    renderdata.surfaceCounter = 0;

    pWindow->wlSurface()->resource()->breadthfirst(
        [&renderdata, &pWindow](SP<CWLSurfaceResource> s, const Vector2D& offset, void*) {
            if (!s || !s->m_current.texture)
                return;

            if (s->m_current.size.x < 1 || s->m_current.size.y < 1)
                return;

            renderdata.localPos = offset;
            renderdata.texture = s->m_current.texture;
            renderdata.surface = s;
            renderdata.mainSurface = s == pWindow->wlSurface()->resource();
            g_pHyprRenderer->m_renderPass.add(makeUnique<CSurfacePassElement>(renderdata));
            renderdata.surfaceCounter++;
        },
        nullptr);
}

namespace {

void renderLayerStub(PHLLS pLayer, PHLMONITOR pMonitor, CBox rectOverride, CBox clipBox, const Time::steady_tp& time, float alpha = 1.F, int rounding = 0, float roundingPower = 2.0F) {
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

} // namespace

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

        const Vector2D layerPos = (layer->m_realPosition->value() - pMonitor->m_position) * pMonitor->m_scale;
        const Vector2D layerSize = layer->m_realSize->value() * pMonitor->m_scale;
        if (!(layerSize.x > 1 && layerSize.y > 1))
            continue;

        renderLayerStub(layer, pMonitor, CBox{layerPos, layerSize}, monitorClip, time);
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

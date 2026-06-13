#include "Overview.hpp"
#include "Globals.hpp"
#include <hyprland/src/helpers/memory/Memory.hpp>
#include <hyprland/src/config/shared/complex/ComplexDataTypes.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>
#include <hyprland/src/render/pass/BorderPassElement.hpp>
#include <hyprland/src/render/pass/SurfacePassElement.hpp>
#include <hyprland/src/render/pass/RendererHintsPassElement.hpp>
#include <hyprlang.hpp>
#include <hyprutils/utils/ScopeGuard.hpp>
#include <algorithm>
#include <climits>
#include <cmath>


void renderRect(CBox box, CHyprColor color) {
    CRectPassElement::SRectData rectdata;
    rectdata.color = color;
    rectdata.box = box;
    g_pHyprRenderer->m_renderPass.add(makeUnique<CRectPassElement>(rectdata));
}

void renderRectWithBlur(CBox box, CHyprColor color) {
    CRectPassElement::SRectData rectdata;
    rectdata.color = color;
    rectdata.box = box;
    rectdata.blur = true;
    g_pHyprRenderer->m_renderPass.add(makeUnique<CRectPassElement>(rectdata));
}

void renderBorder(CBox box, const Config::CGradientValueData& gradient, int size) {
    CBorderPassElement::SBorderData data;
    data.box = box;
    data.grad1 = gradient;
    data.round = 0;
    data.a = 1.f;
    data.borderSize = size;
    g_pHyprRenderer->m_renderPass.add(makeUnique<CBorderPassElement>(data));
}

void renderWindowStub(PHLWINDOW pWindow, PHLMONITOR pMonitor, PHLWORKSPACE pWorkspaceOverride, CBox rectOverride, CBox clipBox, const Time::steady_tp& time) {
    if (!pWindow || !pMonitor || !pWorkspaceOverride) return;
    if (!pWindow->m_isMapped || !pWindow->wlSurface() || !pWindow->wlSurface()->resource()) return;

    Render::SRenderModifData renderModif;

    const auto oRealPosition = pWindow->m_realPosition->value();
    const auto oSize = pWindow->m_realSize->value();
    const float    logicalW = std::max((float)oSize.x, 5.F);
    const float    scaleMod = rectOverride.w / std::max(logicalW * pMonitor->m_scale, 5.F);
    if (!(scaleMod > 0.F) || !(rectOverride.w > 0 && rectOverride.h > 0)) return;

    const Vector2D logicalTL = oRealPosition + pWindow->m_floatingOffset;
    const Vector2D scaledTL  = (logicalTL - pMonitor->m_position) * pMonitor->m_scale;
    const Vector2D translate = rectOverride.pos() / scaleMod - scaledTL;

    renderModif.modifs.push_back(std::make_pair(Render::SRenderModifData::eRenderModifType::RMOD_TYPE_TRANSLATE, std::any(translate)));
    renderModif.modifs.push_back(std::make_pair(Render::SRenderModifData::eRenderModifType::RMOD_TYPE_SCALE, std::any(scaleMod)));
    renderModif.enabled = true;

    g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{.renderModif = renderModif}));
    Hyprutils::Utils::CScopeGuard x([] {
        g_pHyprRenderer->m_renderPass.add(makeUnique<CRendererHintsPassElement>(CRendererHintsPassElement::SData{.renderModif = Render::SRenderModifData{}}));
    });

    g_pHyprRenderer->damageWindow(pWindow);

    CSurfacePassElement::SRenderData renderdata = {pMonitor, time};
    renderdata.pos                  = oRealPosition + pWindow->m_floatingOffset;
    renderdata.w                    = std::max(oSize.x, 5.0);
    renderdata.h                    = std::max(oSize.y, 5.0);
    renderdata.surface              = pWindow->wlSurface()->resource();
    renderdata.dontRound            = pWindow->isEffectiveInternalFSMode(FSMODE_FULLSCREEN);
    renderdata.fadeAlpha            = 1.F;
    renderdata.alpha                = 1.F;
    renderdata.decorate             = false;
    renderdata.rounding             = renderdata.dontRound ? 0 : pWindow->rounding() * scaleMod * pMonitor->m_scale;
    renderdata.roundingPower        = renderdata.dontRound ? 2.0F : pWindow->roundingPower();
    renderdata.blur                 = false;
    renderdata.pWindow              = pWindow;
    renderdata.clipBox              = clipBox;
    renderdata.useNearestNeighbor   = false;
    renderdata.squishOversized      = true;
    renderdata.surfaceCounter       = 0;

    pWindow->wlSurface()->resource()->breadthfirst(
        [&renderdata, &pWindow](SP<CWLSurfaceResource> s, const Vector2D& offset, void* data) {
            if (!s || !s->m_current.texture)
                return;

            if (s->m_current.size.x < 1 || s->m_current.size.y < 1)
                return;

            renderdata.localPos    = offset;
            renderdata.texture     = s->m_current.texture;
            renderdata.surface     = s;
            renderdata.mainSurface = s == pWindow->wlSurface()->resource();
            g_pHyprRenderer->m_renderPass.add(makeUnique<CSurfacePassElement>(renderdata));
            renderdata.surfaceCounter++;
        },
        nullptr);
}

void renderLayerStub(PHLLS pLayer, PHLMONITOR pMonitor, CBox rectOverride, CBox clipBox, const Time::steady_tp& time) {
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
    renderdata.fadeAlpha                        = 1.F;
    renderdata.alpha                            = 1.F;
    renderdata.blur                             = false;
    renderdata.surface                          = pLayer->wlSurface()->resource();
    renderdata.decorate                         = false;
    renderdata.w                                = oSize.x;
    renderdata.h                                = oSize.y;
    renderdata.pLS                              = pLayer;
    renderdata.clipBox                          = clipBox;
    renderdata.surfaceCounter                   = 0;

    pLayer->wlSurface()->resource()->breadthfirst(
        [&renderdata, &pLayer](SP<CWLSurfaceResource> s, const Vector2D& offset, void* data) {
            if (!s || !s->m_current.texture)
                return;

            if (s->m_current.size.x < 1 || s->m_current.size.y < 1)
                return;

            renderdata.localPos    = offset;
            renderdata.texture     = s->m_current.texture;
            renderdata.surface     = s;
            renderdata.mainSurface = s == pLayer->wlSurface()->resource();
            g_pHyprRenderer->m_renderPass.add(makeUnique<CSurfacePassElement>(renderdata));
            renderdata.surfaceCounter++;
        },
        &renderdata);
}

bool renderFullscreenBackground(PHLMONITOR pMonitor, const CBox& monitorClip, const Time::steady_tp& time) {
    if (!pMonitor)
        return false;

    bool rendered = false;
    for (auto& ls : pMonitor->m_layerSurfaceLayers[0]) {
        if (!ls)
            continue;

        const Vector2D layerPos = (ls->m_realPosition->value() - pMonitor->m_position) * pMonitor->m_scale;
        const Vector2D layerSize = ls->m_realSize->value() * pMonitor->m_scale;
        if (!(layerSize.x > 1 && layerSize.y > 1))
            continue;

        renderLayerStub(ls.lock(), pMonitor, CBox{layerPos, layerSize}, monitorClip, time);
        rendered = true;
    }

    return rendered;
}

// Minimal overview renderer: fullscreen wallpaper dim + one continuous workspace strip with live windows only.
void CHyprspaceWidget::draw() {
    workspaceBoxes.clear();

    if (!active)
        return;

    const auto owner = getOwner();
    if (!owner)
        return;

    const CBox monitorClip = {{0, 0}, owner->m_transformedSize};
    const auto time = Time::steadyNow();

    g_pHyprRenderer->m_renderData.clipBox = monitorClip;

    // Draw the real desktop background over the whole monitor first.
    // The overview should feel like one continuous workspace ribbon over the actual wallpaper,
    // not like separate dark cards. Topbar/AppDock are layer surfaces rendered by Hyprland after
    // this POST_WINDOWS hook, so they remain visible and clickable.
    const bool hasBackground = renderFullscreenBackground(owner, monitorClip, time);
    if (!hasBackground)
        renderRect(CBox{0, 0, owner->m_transformedSize.x, owner->m_transformedSize.y}, CHyprColor(0.02, 0.025, 0.032, 1.0));

    // One global background layer for the whole overview:
    // wallpaper -> blur/dim overlay -> live workspace strip.
    // Do not draw any additional wallpaper/dim layer inside the strip itself, otherwise
    // the image looks like three separate layers instead of one unified GNOME-like canvas.
    const CBox fullscreenDim = CBox{0, 0, owner->m_transformedSize.x, owner->m_transformedSize.y};
    if (!Config::disableBlur)
        renderRectWithBlur(fullscreenDim, CHyprColor(0.02, 0.025, 0.032, 0.36));
    else
        renderRect(fullscreenDim, CHyprColor(0.02, 0.025, 0.032, 0.42));

    std::vector<int> workspaces;
    int highestID = std::max(1, static_cast<int>(owner->activeWorkspaceID()));

    for (auto& ws : g_pCompositor->getWorkspaces()) {
        if (!ws || !ws->m_monitor)
            continue;
        if (ws->m_monitor->m_id != ownerID)
            continue;
        if (ws->m_id < 1)
            continue;

        workspaces.push_back(ws->m_id);
        highestID = std::max(highestID, static_cast<int>(ws->m_id));
    }

    if (Config::showEmptyWorkspace) {
        for (int id = 1; id <= highestID; ++id)
            workspaces.push_back(id);
    }

    std::sort(workspaces.begin(), workspaces.end());
    workspaces.erase(std::unique(workspaces.begin(), workspaces.end()), workspaces.end());

    if (workspaces.empty())
        return;

    const double margin = std::max<double>(8.0, Config::workspaceMargin * owner->m_scale);
    // Do not leave a dim strip between workspace previews. The outer margin is still used
    // for screen edges, but adjacent previews touch each other with a tiny overlap so
    // rounding does not reveal the fullscreen dim background between them.
    const double workspaceGap = 0.0;
    const double workspaceOverlap = 1.0;
    const double reservedBottom = std::max<double>(0.0, Config::reservedArea * owner->m_scale);
    const double availableW = owner->m_transformedSize.x;
    const double availableH = std::max<double>(120.0, owner->m_transformedSize.y - reservedBottom);

    // Keep the first version simple: several workspaces visible, centered around active workspace.
    const double previewScale = std::min<double>(0.46, std::min((availableW - margin * 3.0) / (owner->m_transformedSize.x * 2.25), (availableH - margin * 2.0) / owner->m_transformedSize.y));
    const double workspaceBoxW = owner->m_transformedSize.x * previewScale;
    const double workspaceBoxH = owner->m_transformedSize.y * previewScale;
    if (!(workspaceBoxW > 0 && workspaceBoxH > 0))
        return;

    int activeIndex = 0;
    for (size_t i = 0; i < workspaces.size(); ++i) {
        if (workspaces[i] == owner->activeWorkspaceID()) {
            activeIndex = static_cast<int>(i);
            break;
        }
    }

    const double step = std::max<double>(1.0, workspaceBoxW + workspaceGap - workspaceOverlap);
    const double groupWidth = workspaceBoxW * workspaces.size() + (workspaceGap - workspaceOverlap) * std::max<int>(0, workspaces.size() - 1);
    const double minStart = availableW - groupWidth - margin;
    const double maxStart = margin;

    // Compute the natural ribbon origin first and clamp that base position before
    // applying user scroll. Previously, when activeIndex was 0, startX was first
    // centered and only then clamped to the left edge. Small scroll deltas were
    // swallowed by that clamp, so scrolling from workspace 1 felt delayed and very
    // insensitive. Keeping scroll as a separate relative offset fixes that.
    double baseStartX = (availableW * 0.5) - ((activeIndex + 0.5) * step);
    if (groupWidth <= availableW - margin * 2.0)
        baseStartX = (availableW - groupWidth) * 0.5;
    else
        baseStartX = std::clamp(baseStartX, minStart, maxStart);

    workspaceScrollMin = groupWidth <= availableW - margin * 2.0 ? 0.0 : minStart - baseStartX;
    workspaceScrollMax = groupWidth <= availableW - margin * 2.0 ? 0.0 : maxStart - baseStartX;

    const double clampedScroll = std::clamp<double>(workspaceScrollOffset->value(), workspaceScrollMin, workspaceScrollMax);
    if (clampedScroll != workspaceScrollOffset->value())
        workspaceScrollOffset->setValueAndWarp(clampedScroll);

    const double startX = baseStartX + clampedScroll;

    // Keep previews above the AppDock area, with no bottom panel from the plugin itself.
    const double startY = std::max<double>(margin, ((availableH - workspaceBoxH) * 0.5));

    const auto frameNow = std::chrono::steady_clock::now();
    double frameDt = 1.0 / 60.0;
    if (lastWorkspaceHoverFrameValid) {
        frameDt = std::chrono::duration<double>(frameNow - lastWorkspaceHoverFrame).count();
        if (!(frameDt > 0.0) || frameDt > 0.12)
            frameDt = 1.0 / 60.0;
    }
    lastWorkspaceHoverFrame = frameNow;
    lastWorkspaceHoverFrameValid = true;
    const double hoverEase = std::clamp<double>(frameDt / 0.075, 0.0, 1.0);
    const auto mouseCoords = g_pInputManager->getMouseCoordsInternal();

    for (size_t index = 0; index < workspaces.size(); ++index) {
        const int wsID = workspaces[index];
        const auto ws = g_pCompositor->getWorkspaceByID(wsID);
        CBox workspaceBox = {startX + index * step, startY, workspaceBoxW, workspaceBoxH};

        CBox baseInputBox = workspaceBox;
        baseInputBox.scale(1 / owner->m_scale);
        baseInputBox.x += owner->m_position.x;
        baseInputBox.y += owner->m_position.y;

        const bool hoveredWorkspace = baseInputBox.containsPoint(mouseCoords);
        float& hoverProgress = workspaceHoverProgress[wsID];
        const float targetHover = hoveredWorkspace ? 1.0F : 0.0F;
        hoverProgress += (targetHover - hoverProgress) * static_cast<float>(hoverEase);
        if (std::abs(hoverProgress) < 0.001F)
            hoverProgress = 0.0F;

        const double hoverScale = 1.0 + static_cast<double>(hoverProgress) * 0.035;
        if (hoverScale != 1.0) {
            const double centerX = workspaceBox.x + workspaceBox.w * 0.5;
            const double centerY = workspaceBox.y + workspaceBox.h * 0.5;
            workspaceBox.w *= hoverScale;
            workspaceBox.h *= hoverScale;
            workspaceBox.x = centerX - workspaceBox.w * 0.5;
            workspaceBox.y = centerY - workspaceBox.h * 0.5;
        }

        const double monitorScaleForPreview = previewScale * hoverScale * owner->m_scale;

        // Keep the backdrop uniform. Do not draw a per-workspace background under windows,
        // otherwise gaps between tiled windows look like the background is split into pieces.
        bool hasVisibleWindow = false;
        if (ws) {
            for (auto& w : g_pCompositor->m_windows) {
                if (!w)
                    continue;
                if (w->m_workspace != ws)
                    continue;
                if (!w->m_isMapped)
                    continue;

                hasVisibleWindow = true;
                break;
            }
        }

        if (!hasVisibleWindow)
            renderRect(workspaceBox, ws == owner->m_activeWorkspace ? Config::workspaceActiveBackground : Config::workspaceInactiveBackground);

        if (ws) {
            for (auto& w : g_pCompositor->m_windows) {
                if (!w)
                    continue;
                if (w->m_workspace != ws)
                    continue;
                if (!w->m_isMapped)
                    continue;

                const double wX = workspaceBox.x + ((w->m_realPosition->value().x - owner->m_position.x) * monitorScaleForPreview);
                const double wY = workspaceBox.y + ((w->m_realPosition->value().y - owner->m_position.y) * monitorScaleForPreview);
                const double wW = w->m_realSize->value().x * monitorScaleForPreview;
                const double wH = w->m_realSize->value().y * monitorScaleForPreview;

                if (!(wW > 1 && wH > 1))
                    continue;

                renderWindowStub(w, owner, ws, CBox{wX, wY, wW, wH}, workspaceBox, time);
            }
        }

        // Input boxes are absolute logical coordinates.
        CBox inputBox = workspaceBox;
        inputBox.scale(1 / owner->m_scale);
        inputBox.x += owner->m_position.x;
        inputBox.y += owner->m_position.y;
        workspaceBoxes.emplace_back(std::make_tuple(wsID, inputBox));
    }

    g_pHyprRenderer->m_renderData.clipBox = monitorClip;
    g_pHyprRenderer->damageMonitor(owner);
}

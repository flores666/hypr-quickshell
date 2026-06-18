#include "Overview.hpp"
#include "Globals.hpp"
#include <hyprland/src/helpers/memory/Memory.hpp>
#include <hyprland/src/config/shared/complex/ComplexDataTypes.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>
#include <hyprland/src/render/pass/SurfacePassElement.hpp>
#include <hyprland/src/render/pass/RendererHintsPassElement.hpp>
#include <hyprlang.hpp>
#include <hyprutils/utils/ScopeGuard.hpp>
#include <algorithm>
#include <climits>
#include <cmath>
#include <optional>
#include <vector>


void renderRect(CBox box, CHyprColor color, int rounding = 0, float roundingPower = 2.0F) {
    CRectPassElement::SRectData rectdata;
    rectdata.color = color;
    rectdata.box = box;
    rectdata.round = rounding;
    rectdata.roundingPower = roundingPower;
    g_pHyprRenderer->m_renderPass.add(makeUnique<CRectPassElement>(rectdata));
}

void renderRectWithBlur(CBox box, CHyprColor color, int rounding = 0, float roundingPower = 2.0F) {
    CRectPassElement::SRectData rectdata;
    rectdata.color = color;
    rectdata.box = box;
    rectdata.round = rounding;
    rectdata.roundingPower = roundingPower;
    rectdata.blur = true;
    g_pHyprRenderer->m_renderPass.add(makeUnique<CRectPassElement>(rectdata));
}

void renderWindowStub(PHLWINDOW pWindow, PHLMONITOR pMonitor, PHLWORKSPACE pWorkspaceOverride, CBox rectOverride, CBox clipBox, const Time::steady_tp& time, float alpha = 1.F, int forcedRounding = -1, float forcedRoundingPower = 2.0F) {
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

    CSurfacePassElement::SRenderData renderdata = {pMonitor, time};
    renderdata.pos                  = oRealPosition + pWindow->m_floatingOffset;
    renderdata.w                    = std::max(oSize.x, 5.0);
    renderdata.h                    = std::max(oSize.y, 5.0);
    renderdata.surface              = pWindow->wlSurface()->resource();
    renderdata.dontRound            = forcedRounding < 0 && pWindow->isEffectiveInternalFSMode(FSMODE_FULLSCREEN);
    renderdata.fadeAlpha            = std::clamp(alpha, 0.F, 1.F);
    renderdata.alpha                = std::clamp(alpha, 0.F, 1.F);
    renderdata.decorate             = false;
    renderdata.rounding             = renderdata.dontRound ? 0 : pWindow->rounding() * scaleMod * pMonitor->m_scale;
    renderdata.roundingPower        = renderdata.dontRound ? 2.0F : pWindow->roundingPower();
    if (forcedRounding >= 0) {
        renderdata.rounding = static_cast<decltype(renderdata.rounding)>(forcedRounding);
        renderdata.roundingPower = forcedRoundingPower;
    }
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
    renderdata.fadeAlpha                        = std::clamp(alpha, 0.F, 1.F);
    renderdata.alpha                            = std::clamp(alpha, 0.F, 1.F);
    renderdata.blur                             = false;
    renderdata.surface                          = pLayer->wlSurface()->resource();
    renderdata.decorate                         = false;
    renderdata.w                                = oSize.x;
    renderdata.h                                = oSize.y;
    renderdata.pLS                              = pLayer;
    renderdata.clipBox                          = clipBox;
    renderdata.rounding                         = rounding;
    renderdata.roundingPower                    = roundingPower;
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

bool renderWorkspaceBackground(PHLMONITOR pMonitor, const CBox& workspaceBox, const CBox& clipBox, const Time::steady_tp& time, float alpha, double topInset, int rounding, float roundingPower) {
    if (!pMonitor)
        return false;

    (void)topInset;

    CBox backgroundBox = workspaceBox;

    bool rendered = false;
    for (auto& ls : pMonitor->m_layerSurfaceLayers[0]) {
        if (!ls)
            continue;

        const auto layer = ls.lock();
        if (!layer)
            continue;
        if (!layer->m_mapped || layer->m_readyToDelete || !layer->m_layerSurface || !layer->wlSurface() || !layer->wlSurface()->resource())
            continue;

        renderLayerStub(layer, pMonitor, backgroundBox, clipBox, time, alpha, rounding, roundingPower);
        rendered = true;
    }

    return rendered;
}

static bool isQuickshellLayerNamespaceForOverview(const std::string& ns) {
    return ns.starts_with("quickshell") || ns.starts_with("quickshell:");
}

static double overviewTopReservedPixels(PHLMONITOR pMonitor) {
    if (!pMonitor)
        return 0.0;

    double topInset = 0.0;

    for (size_t layerIndex = 1; layerIndex < 4; ++layerIndex) {
        for (auto& weakLayer : pMonitor->m_layerSurfaceLayers[layerIndex]) {
            const auto layer = weakLayer.lock();
            if (!layer)
                continue;
            if (!layer->m_mapped || layer->m_readyToDelete || !layer->m_layerSurface)
                continue;
            if (!isQuickshellLayerNamespaceForOverview(layer->m_namespace))
                continue;

            const Vector2D layerPos = layer->m_realPosition->value();
            const Vector2D layerSize = layer->m_realSize->value();
            if (!(layerSize.x > pMonitor->m_size.x * 0.25 && layerSize.y > 1.0 && layerSize.y < pMonitor->m_size.y * 0.25))
                continue;
            if (std::abs(layerPos.y - pMonitor->m_position.y) > 4.0)
                continue;

            topInset = std::max(topInset, (layerPos.y + layerSize.y - pMonitor->m_position.y) * pMonitor->m_scale);
        }
    }

    return std::clamp(topInset, 0.0, pMonitor->m_transformedSize.y * 0.25);
}

static CBox overviewPixelSnappedBox(const CBox& box) {
    const double left = std::round(box.x);
    const double top = std::round(box.y);
    const double right = std::round(box.x + box.w);
    const double bottom = std::round(box.y + box.h);

    return CBox{left, top, std::max(1.0, right - left), std::max(1.0, bottom - top)};
}

static bool overviewBoxesIntersect(const CBox& lhs, const CBox& rhs) {
    return lhs.x < rhs.x + rhs.w &&
        lhs.x + lhs.w > rhs.x &&
        lhs.y < rhs.y + rhs.h &&
        lhs.y + lhs.h > rhs.y;
}

static int overviewWorkspaceRounding(PHLMONITOR pMonitor) {
    if (!pMonitor)
        return 10;

    return std::max(8, static_cast<int>(std::round(10.0 * pMonitor->m_scale)));
}

static bool overviewBoxOverlapsWorkspaceCorner(const CBox& box, const CBox& workspaceBox, int rounding) {
    const double radius = std::min<double>(std::max(0, rounding), std::floor(std::min(workspaceBox.w, workspaceBox.h) * 0.5));
    if (radius <= 1.0)
        return false;

    const CBox topLeft{workspaceBox.x, workspaceBox.y, radius, radius};
    const CBox topRight{workspaceBox.x + workspaceBox.w - radius, workspaceBox.y, radius, radius};
    const CBox bottomLeft{workspaceBox.x, workspaceBox.y + workspaceBox.h - radius, radius, radius};
    const CBox bottomRight{workspaceBox.x + workspaceBox.w - radius, workspaceBox.y + workspaceBox.h - radius, radius, radius};

    return overviewBoxesIntersect(box, topLeft) ||
        overviewBoxesIntersect(box, topRight) ||
        overviewBoxesIntersect(box, bottomLeft) ||
        overviewBoxesIntersect(box, bottomRight);
}

struct SOverviewWindowPreview {
    PHLWINDOW window;
    CBox box;
    bool coversWorkspace = false;
    bool overlapsWorkspaceCorner = false;
};

static bool boxContainsPointForOverview(const std::optional<CBox>& box, const Vector2D& coords) {
    return box.has_value() && box->containsPoint(coords);
}

static double overviewClamp01(double value) {
    return std::clamp(value, 0.0, 1.0);
}

static double overviewEaseOutCubic(double value) {
    const double t = overviewClamp01(value);
    const double inv = 1.0 - t;
    return 1.0 - inv * inv * inv;
}

static double overviewEaseOutQuart(double value) {
    const double t = overviewClamp01(value);
    const double inv = 1.0 - t;
    return 1.0 - inv * inv * inv * inv;
}

static double overviewEaseInOutCubic(double value) {
    const double t = overviewClamp01(value);
    if (t < 0.5)
        return 4.0 * t * t * t;

    const double inv = -2.0 * t + 2.0;
    return 1.0 - (inv * inv * inv) / 2.0;
}

static double overviewLerp(double from, double to, double progress) {
    return from + (to - from) * progress;
}

static CBox overviewLerpBox(const CBox& from, const CBox& to, double progress) {
    return CBox{overviewLerp(from.x, to.x, progress),
                overviewLerp(from.y, to.y, progress),
                overviewLerp(from.w, to.w, progress),
                overviewLerp(from.h, to.h, progress)};
}

static bool isPointerOverInteractiveLayerForOverview(PHLMONITOR pMonitor, const Vector2D& coords) {
    if (!pMonitor)
        return false;

    const CBox monitorBox = {pMonitor->m_position, pMonitor->m_size};

    for (size_t layerIndex = 0; layerIndex < 4; ++layerIndex) {
        for (auto& weakLayer : pMonitor->m_layerSurfaceLayers[layerIndex]) {
            const auto layer = weakLayer.lock();
            if (!layer)
                continue;
            if (!layer->m_mapped || layer->m_readyToDelete)
                continue;

            const bool quickshellLayer = isQuickshellLayerNamespaceForOverview(layer->m_namespace);
            if (layerIndex == 0 && !quickshellLayer)
                continue;

            const CBox realBox = {layer->m_realPosition->value(), layer->m_realSize->value()};
            if (realBox.containsPoint(coords) || boxContainsPointForOverview(layer->logicalBox(), coords) || boxContainsPointForOverview(layer->surfaceLogicalBox(), coords))
                return true;

            // When a Quickshell popup tree is open, disable workspace hover for
            // the whole monitor. Otherwise the workspace under a calendar,
            // system popup or AppDock menu still grows even though the popup is
            // visually above the overview.
            if (quickshellLayer && layer->popupsCount() > 0 && monitorBox.containsPoint(coords))
                return true;
        }
    }

    return false;
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
    const CBox fullWorkspaceBox = CBox{0, 0, owner->m_transformedSize.x, owner->m_transformedSize.y};
    const auto time = Time::steadyNow();
    const bool selectionAnimationRunning = isSelectingWorkspace();
    const bool selectionCloseMorphRunning = workspaceSelectionCloseMorphActive();
    const double selectionProgress = selectionAnimationRunning ? workspaceSelectionProgress() : 1.0;
    const double rawOpenProgress = selectionCloseMorphRunning ? (1.0 - selectionProgress) : overviewOpenProgress();
    if (isClosing() && rawOpenProgress <= 0.001) {
        finishHide();
        g_pHyprRenderer->damageMonitor(owner);
        return;
    }

    const bool closingAnimationRunning = isClosing() || selectionCloseMorphRunning;
    const bool morphAnimationRunning = rawOpenProgress < 0.999 || closingAnimationRunning;
    const double openProgress = closingAnimationRunning
        ? overviewEaseInOutCubic(rawOpenProgress)
        : overviewEaseOutCubic(rawOpenProgress);

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
    const double dimAlpha = overviewLerp(0.0, 0.10, openProgress);
    if (dimAlpha > 0.001) {
        if (!Config::disableBlur) {
            renderRectWithBlur(fullscreenDim, CHyprColor(0.02, 0.025, 0.032, dimAlpha));
        } else {
            renderRect(fullscreenDim, CHyprColor(0.02, 0.025, 0.032, dimAlpha));
        }
    }

    const auto workspaces = overviewWorkspaceIds();
    if (workspaces.empty())
        return;

    const double margin = std::max<double>(8.0, Config::workspaceMargin * owner->m_scale);
    const double workspaceGap = std::max<double>(22.0, Config::workspaceMargin * owner->m_scale * 1.45);
    const double reservedBottom = std::max<double>(0.0, Config::reservedArea * owner->m_scale);
    const double availableW = owner->m_transformedSize.x;
    const double availableH = std::max<double>(120.0, owner->m_transformedSize.y - reservedBottom);
    const double topReservedPixels = overviewTopReservedPixels(owner);
    const double previewSourceH = std::max<double>(120.0, owner->m_transformedSize.y - topReservedPixels);
    const int workspaceRounding = overviewWorkspaceRounding(owner);

    const double visualCenterIndex = visualCenterWorkspaceIndex(workspaces);
    const int visualCenterIndexRounded = std::clamp(static_cast<int>(std::round(visualCenterIndex)), 0, static_cast<int>(workspaces.size()) - 1);
    const int visualCenterWorkspaceID = workspaces[visualCenterIndexRounded];
    const int morphTargetWorkspaceID = selectionCloseMorphRunning && workspaceSelectionToID > 0
        ? workspaceSelectionToID
        : visualCenterWorkspaceID;
    int morphTargetIndex = visualCenterIndexRounded;
    if (selectionCloseMorphRunning && workspaceSelectionToID > 0) {
        auto targetIt = std::find(workspaces.begin(), workspaces.end(), workspaceSelectionToID);
        if (targetIt != workspaces.end())
            morphTargetIndex = static_cast<int>(std::distance(workspaces.begin(), targetIt));
    }

    const double centerPreviewScale = std::min<double>(
        0.64,
        std::min((availableH - margin * 2.0) / std::max<double>(previewSourceH, 1.0),
                 (availableW - margin * 2.0) / (std::max<double>(owner->m_transformedSize.x, 1.0) * 1.08)));
    const double sidePreviewScale = std::max<double>(0.24, centerPreviewScale * 0.72);
    const double centerPreviewW = owner->m_transformedSize.x * centerPreviewScale;
    const double centerPreviewH = previewSourceH * centerPreviewScale;
    const double sidePreviewW = owner->m_transformedSize.x * sidePreviewScale;
    const double sidePreviewH = previewSourceH * sidePreviewScale;
    if (!(centerPreviewW > 0 && centerPreviewH > 0 && sidePreviewW > 0 && sidePreviewH > 0))
        return;

    std::vector<double> previewScales(workspaces.size(), sidePreviewScale);
    std::vector<CBox> baseWorkspaceBoxes(workspaces.size());
    for (size_t index = 0; index < workspaces.size(); ++index) {
        const double distance = std::min<double>(1.0, std::abs(static_cast<double>(index) - visualCenterIndex));
        previewScales[index] = overviewLerp(centerPreviewScale, sidePreviewScale, distance);
    }

    baseWorkspaceBoxes[visualCenterIndexRounded] = CBox{
        (availableW - owner->m_transformedSize.x * previewScales[visualCenterIndexRounded]) * 0.5,
        std::max<double>(margin, (availableH - previewSourceH * previewScales[visualCenterIndexRounded]) * 0.5),
        owner->m_transformedSize.x * previewScales[visualCenterIndexRounded],
        previewSourceH * previewScales[visualCenterIndexRounded],
    };

    for (int index = visualCenterIndexRounded - 1; index >= 0; --index) {
        const double w = owner->m_transformedSize.x * previewScales[index];
        const double h = previewSourceH * previewScales[index];
        const CBox& nextBox = baseWorkspaceBoxes[index + 1];
        baseWorkspaceBoxes[index] = CBox{
            nextBox.x - workspaceGap - w,
            std::max<double>(margin, (availableH - h) * 0.5),
            w,
            h,
        };
    }

    for (size_t index = static_cast<size_t>(visualCenterIndexRounded + 1); index < workspaces.size(); ++index) {
        const double w = owner->m_transformedSize.x * previewScales[index];
        const double h = previewSourceH * previewScales[index];
        const CBox& prevBox = baseWorkspaceBoxes[index - 1];
        baseWorkspaceBoxes[index] = CBox{
            prevBox.x + prevBox.w + workspaceGap,
            std::max<double>(margin, (availableH - h) * 0.5),
            w,
            h,
        };
    }

    // Keep selection and scroll motion smooth even though the centered workspace is
    // larger than side workspaces. The centered workspace stays visually centered,
    // while fractional selection moves the strip between two adjacent previews.
    const double averageStep = (centerPreviewW + sidePreviewW) * 0.5 + workspaceGap;
    const double fractionalOffsetX = (static_cast<double>(visualCenterIndexRounded) - visualCenterIndex) * averageStep;
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
    const bool hoverBlockedByPopup = isPointerOverInteractiveLayerForOverview(owner, mouseCoords);

    struct SWorkspacePreview {
        int wsID = 0;
        PHLWORKSPACE ws;
        CBox box;
        CBox inputBox;
        double monitorScaleForPreview = 1.0;
        double previewScale = 1.0;
        double topInset = 0.0;
        int rounding = 0;
        float opacity = 1.0F;
        bool hovered = false;
    };

    std::vector<PHLWINDOW> mappedWindows;
    mappedWindows.reserve(g_pCompositor->m_windows.size());
    for (auto& w : g_pCompositor->m_windows) {
        if (!w)
            continue;
        if (!w->m_isMapped || !w->m_workspace)
            continue;

        mappedWindows.push_back(w);
    }

    std::vector<SWorkspacePreview> previews;
    previews.reserve(workspaces.size());
    int hoveredPreviewIndex = -1;

    for (size_t index = 0; index < workspaces.size(); ++index) {
        const int wsID = workspaces[index];
        const auto ws = g_pCompositor->getWorkspaceByID(wsID);
        CBox workspaceBox = baseWorkspaceBoxes[index];
        workspaceBox.x += fractionalOffsetX;

        CBox baseInputBox = workspaceBox;
        baseInputBox.scale(1 / owner->m_scale);
        baseInputBox.x += owner->m_position.x;
        baseInputBox.y += owner->m_position.y;

        const bool pointerOverWorkspace = !closingAnimationRunning && !selectionAnimationRunning && rawOpenProgress > 0.92 && !hoverBlockedByPopup && baseInputBox.containsPoint(mouseCoords);
        if (pointerOverWorkspace)
            hoveredPreviewIndex = static_cast<int>(index);

        float& hoverProgress = workspaceHoverProgress[wsID];
        const float targetHover = pointerOverWorkspace ? 1.0F : 0.0F;
        hoverProgress += (targetHover - hoverProgress) * static_cast<float>(hoverEase);
        if (std::abs(hoverProgress) < 0.001F)
            hoverProgress = 0.0F;

        const int directionFromTarget = static_cast<int>(index) - morphTargetIndex;
        const bool isMorphTargetPreview = wsID == morphTargetWorkspaceID;
        float previewOpacity = 1.0F;

        if (morphAnimationRunning) {
            if (isMorphTargetPreview) {
                // For click selection, this runs while visualCenterIndex is still
                // moving from the old workspace to the clicked one. The clicked
                // preview therefore swipes toward the center and grows toward
                // fullscreen in one combined GNOME-like motion.
                workspaceBox = overviewLerpBox(fullWorkspaceBox, workspaceBox, openProgress);
            } else {
                const double sideProgress = overviewEaseOutQuart((rawOpenProgress - 0.16) / 0.84);
                const double slideDistance = owner->m_transformedSize.x * 0.10;
                CBox sideStartBox = workspaceBox;
                sideStartBox.x += (directionFromTarget < 0 ? -slideDistance : slideDistance);
                workspaceBox = overviewLerpBox(sideStartBox, workspaceBox, sideProgress);
                previewOpacity = static_cast<float>(sideProgress);
            }
        }

        SWorkspacePreview preview;
        preview.wsID = wsID;
        preview.ws = ws;
        preview.box = workspaceBox;
        preview.previewScale = workspaceBox.w / std::max<double>(owner->m_transformedSize.x, 1.0);
        preview.monitorScaleForPreview = preview.previewScale * owner->m_scale;
        preview.topInset = topReservedPixels * openProgress;
        preview.rounding = static_cast<int>(std::round(workspaceRounding * openProgress));
        preview.opacity = previewOpacity;
        preview.hovered = pointerOverWorkspace;

        CBox inputBox = workspaceBox;
        inputBox.scale(1 / owner->m_scale);
        inputBox.x += owner->m_position.x;
        inputBox.y += owner->m_position.y;
        preview.inputBox = inputBox;

        previews.push_back(preview);
    }

    auto renderPreview = [&](const SWorkspacePreview& preview) {
        const auto ws = preview.ws;
        const CBox workspaceBox = overviewPixelSnappedBox(preview.box);
        CBox visibleBounds = workspaceBox;
        visibleBounds.x -= 48.0;
        visibleBounds.y -= 48.0;
        visibleBounds.w += 96.0;
        visibleBounds.h += 96.0;
        if (!overviewBoxesIntersect(visibleBounds, monitorClip))
            return;

        const double previewScale = workspaceBox.w / std::max<double>(owner->m_transformedSize.x, 1.0);
        const double monitorScaleForPreview = previewScale * owner->m_scale;
        std::vector<SOverviewWindowPreview> visibleWindows;

        if (ws && preview.opacity > 0.001F) {
            visibleWindows.reserve(mappedWindows.size());
            for (auto& w : mappedWindows) {
                if (w->m_workspace != ws)
                    continue;

                const double wX = workspaceBox.x + ((w->m_realPosition->value().x - owner->m_position.x) * monitorScaleForPreview);
                const double wY = workspaceBox.y + ((w->m_realPosition->value().y - owner->m_position.y) * monitorScaleForPreview) - (preview.topInset * previewScale);
                const double wW = w->m_realSize->value().x * monitorScaleForPreview;
                const double wH = w->m_realSize->value().y * monitorScaleForPreview;

                if (!(wW > 1 && wH > 1))
                    continue;

                const CBox windowBox = CBox{wX, wY, wW, wH};
                if (!overviewBoxesIntersect(windowBox, workspaceBox))
                    continue;

                const bool coversWorkspace = wX <= workspaceBox.x + 1.0 &&
                    wY <= workspaceBox.y + 1.0 &&
                    wX + wW >= workspaceBox.x + workspaceBox.w - 1.0 &&
                    wY + wH >= workspaceBox.y + workspaceBox.h - 1.0;
                const bool overlapsWorkspaceCorner = overviewBoxOverlapsWorkspaceCorner(windowBox, workspaceBox, preview.rounding);
                visibleWindows.push_back({w, windowBox, coversWorkspace, overlapsWorkspaceCorner});
            }
        }

        if (preview.opacity <= 0.001F)
            return;

        const bool fullCoverWindowVisible = !morphAnimationRunning && !selectionAnimationRunning && preview.opacity >= 0.999F &&
            std::any_of(visibleWindows.begin(), visibleWindows.end(), [](const SOverviewWindowPreview& windowPreview) {
                return windowPreview.coversWorkspace;
            });

        if (!fullCoverWindowVisible) {
            CHyprColor fallbackColor = preview.wsID == morphTargetWorkspaceID ? Config::workspaceActiveBackground : Config::workspaceInactiveBackground;
            fallbackColor.a = std::max<float>(fallbackColor.a * preview.opacity, 0.22F * preview.opacity);
            renderRect(workspaceBox, fallbackColor, preview.rounding, 2.0F);
        }

        for (const auto& windowPreview : visibleWindows) {
            const int forcedRounding = windowPreview.overlapsWorkspaceCorner ? preview.rounding : -1;
            renderWindowStub(windowPreview.window, owner, ws, windowPreview.box, workspaceBox, time, preview.opacity, forcedRounding, 2.0F);
        }

        workspaceBoxes.emplace_back(std::make_tuple(preview.wsID, preview.inputBox));
    };

    // Draw the hovered preview last so it wins the small overlap area against
    // its neighbors. While the opening morph is running, keep the centered
    // workspace on top too, so the fullscreen desktop visually shrinks into
    // the overview instead of being covered by the side previews.
    const int topPreviewIndex = hoveredPreviewIndex >= 0 ? hoveredPreviewIndex : ((morphAnimationRunning || selectionAnimationRunning) ? morphTargetIndex : -1);
    for (size_t index = 0; index < previews.size(); ++index) {
        if (static_cast<int>(index) == topPreviewIndex)
            continue;
        renderPreview(previews[index]);
    }

    if (topPreviewIndex >= 0 && topPreviewIndex < static_cast<int>(previews.size()))
        renderPreview(previews[topPreviewIndex]);

    g_pHyprRenderer->m_renderData.clipBox = monitorClip;

    if (selectionAnimationRunning && workspaceSelectionProgress() >= 0.999) {
        finishWorkspaceSelectionAnimation();
        return;
    }

    if (morphAnimationRunning || selectionAnimationRunning) {
        g_pHyprRenderer->damageMonitor(owner);
        g_pCompositor->scheduleFrameForMonitor(owner);
    }
}

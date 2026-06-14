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
#include <optional>


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

void renderWindowStub(PHLWINDOW pWindow, PHLMONITOR pMonitor, PHLWORKSPACE pWorkspaceOverride, CBox rectOverride, CBox clipBox, const Time::steady_tp& time, float alpha = 1.F) {
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
    renderdata.fadeAlpha            = std::clamp(alpha, 0.F, 1.F);
    renderdata.alpha                = std::clamp(alpha, 0.F, 1.F);
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

static bool isQuickshellLayerNamespaceForOverview(const std::string& ns) {
    return ns.starts_with("quickshell") || ns.starts_with("quickshell:");
}

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
    const double rawOpenProgress = overviewOpenProgress();
    if (isClosing() && rawOpenProgress <= 0.001) {
        finishHide();
        g_pHyprRenderer->damageMonitor(owner);
        return;
    }

    const bool closingAnimationRunning = isClosing();
    const bool morphAnimationRunning = rawOpenProgress < 0.999 || closingAnimationRunning;
    const double openProgress = closingAnimationRunning
        ? overviewEaseInOutCubic(rawOpenProgress)
        : overviewEaseOutCubic(rawOpenProgress);
    const bool selectionAnimationRunning = isSelectingWorkspace();

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
    const double dimAlpha = overviewLerp(0.0, Config::disableBlur ? 0.42 : 0.36, openProgress);
    if (dimAlpha > 0.001) {
        if (!Config::disableBlur)
            renderRectWithBlur(fullscreenDim, CHyprColor(0.02, 0.025, 0.032, dimAlpha));
        else
            renderRect(fullscreenDim, CHyprColor(0.02, 0.025, 0.032, dimAlpha));
    }

    const auto workspaces = overviewWorkspaceIds();
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

    const double visualCenterIndex = visualCenterWorkspaceIndex(workspaces);
    const int visualCenterIndexRounded = std::clamp(static_cast<int>(std::round(visualCenterIndex)), 0, static_cast<int>(workspaces.size()) - 1);
    const int visualCenterWorkspaceID = workspaces[visualCenterIndexRounded];

    const double step = std::max<double>(1.0, workspaceBoxW + workspaceGap - workspaceOverlap);
    // Keep the selected workspace visually centered. During click selection this
    // center moves fractionally from the old workspace to the target one, which
    // creates a GNOME-like plugin-owned swipe before the exit morph starts.
    const double baseStartX = (availableW * 0.5) - ((visualCenterIndex + 0.5) * step);
    workspaceScrollMin = 0.0;
    workspaceScrollMax = 0.0;

    if (workspaceScrollOffset->value() != 0.0)
        workspaceScrollOffset->setValueAndWarp(0.0);

    const double startX = baseStartX;

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
    const bool hoverBlockedByPopup = isPointerOverInteractiveLayerForOverview(owner, mouseCoords);

    struct SWorkspacePreview {
        int wsID = 0;
        PHLWORKSPACE ws;
        CBox box;
        CBox inputBox;
        double monitorScaleForPreview = 1.0;
        float opacity = 1.0F;
        bool hovered = false;
        bool hasVisibleWindow = false;
    };

    std::vector<SWorkspacePreview> previews;
    previews.reserve(workspaces.size());
    int hoveredPreviewIndex = -1;

    for (size_t index = 0; index < workspaces.size(); ++index) {
        const int wsID = workspaces[index];
        const auto ws = g_pCompositor->getWorkspaceByID(wsID);
        CBox workspaceBox = {startX + index * step, startY, workspaceBoxW, workspaceBoxH};

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

        const double hoverScale = 1.0 + static_cast<double>(hoverProgress) * 0.035;
        if (hoverScale != 1.0) {
            const double centerX = workspaceBox.x + workspaceBox.w * 0.5;
            const double centerY = workspaceBox.y + workspaceBox.h * 0.5;
            workspaceBox.w *= hoverScale;
            workspaceBox.h *= hoverScale;
            workspaceBox.x = centerX - workspaceBox.w * 0.5;
            workspaceBox.y = centerY - workspaceBox.h * 0.5;
        }

        const int directionFromCenter = static_cast<int>(index) - visualCenterIndexRounded;
        const bool isCenteredPreview = wsID == visualCenterWorkspaceID;
        float previewOpacity = 1.0F;

        if (morphAnimationRunning) {
            if (isCenteredPreview) {
                workspaceBox = overviewLerpBox(fullWorkspaceBox, workspaceBox, openProgress);
            } else {
                const double sideProgress = overviewEaseOutQuart((rawOpenProgress - 0.16) / 0.84);
                const double slideDistance = owner->m_transformedSize.x * 0.10;
                CBox sideStartBox = workspaceBox;
                sideStartBox.x += (directionFromCenter < 0 ? -slideDistance : slideDistance);
                workspaceBox = overviewLerpBox(sideStartBox, workspaceBox, sideProgress);
                previewOpacity = static_cast<float>(sideProgress);
            }
        }

        SWorkspacePreview preview;
        preview.wsID = wsID;
        preview.ws = ws;
        preview.box = workspaceBox;
        preview.monitorScaleForPreview = (workspaceBox.w / std::max<double>(owner->m_transformedSize.x, 1.0)) * owner->m_scale;
        preview.opacity = previewOpacity;
        preview.hovered = pointerOverWorkspace;

        CBox inputBox = workspaceBox;
        inputBox.scale(1 / owner->m_scale);
        inputBox.x += owner->m_position.x;
        inputBox.y += owner->m_position.y;
        preview.inputBox = inputBox;

        if (ws && preview.opacity > 0.001F) {
            for (auto& w : g_pCompositor->m_windows) {
                if (!w)
                    continue;
                if (w->m_workspace != ws)
                    continue;
                if (!w->m_isMapped)
                    continue;

                preview.hasVisibleWindow = true;
                break;
            }
        }

        previews.push_back(preview);
    }

    auto renderPreview = [&](const SWorkspacePreview& preview) {
        const auto ws = preview.ws;
        const CBox workspaceBox = preview.box;
        const double monitorScaleForPreview = preview.monitorScaleForPreview;

        // Keep the backdrop uniform. Do not draw a per-workspace background under windows,
        // otherwise gaps between tiled windows look like the background is split into pieces.
        if (!preview.hasVisibleWindow && preview.opacity > 0.001F) {
            CHyprColor emptyColor = preview.wsID == visualCenterWorkspaceID ? Config::workspaceActiveBackground : Config::workspaceInactiveBackground;
            emptyColor.a *= preview.opacity;
            renderRect(workspaceBox, emptyColor);
        }

        if (ws && preview.opacity > 0.001F) {
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

                renderWindowStub(w, owner, ws, CBox{wX, wY, wW, wH}, workspaceBox, time, preview.opacity);
            }
        }

        workspaceBoxes.emplace_back(std::make_tuple(preview.wsID, preview.inputBox));
    };

    // Draw the hovered preview last so its quick zoom appears above its
    // neighbors. While the opening morph is running, keep the centered
    // workspace on top too, so the fullscreen desktop visually shrinks into
    // the overview instead of being covered by the side previews.
    const int topPreviewIndex = hoveredPreviewIndex >= 0 ? hoveredPreviewIndex : ((morphAnimationRunning || selectionAnimationRunning) ? visualCenterIndexRounded : -1);
    for (size_t index = 0; index < previews.size(); ++index) {
        if (static_cast<int>(index) == topPreviewIndex)
            continue;
        renderPreview(previews[index]);
    }

    if (topPreviewIndex >= 0 && topPreviewIndex < static_cast<int>(previews.size()))
        renderPreview(previews[topPreviewIndex]);

    g_pHyprRenderer->m_renderData.clipBox = monitorClip;
    g_pHyprRenderer->damageMonitor(owner);

    if (selectionAnimationRunning && workspaceSelectionProgress() >= 0.999) {
        finishWorkspaceSelectionAnimation();
        return;
    }

    if (morphAnimationRunning || selectionAnimationRunning)
        g_pCompositor->scheduleFrameForMonitor(owner);
}

#include "Overview.hpp"
#include "Globals.hpp"
#include "OverviewCornerMask.hpp"
#include "OverviewRenderHelpers.hpp"
#include "OverviewShadow.hpp"
#include <algorithm>
#include <cmath>
#include <functional>
#include <iterator>
#include <optional>
#include <string>
#include <utility>
#include <vector>

extern std::function<void()> applicationsReturnToOverviewFinishedCallback;


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

struct SOverviewWorkspaceWindows {
    PHLWORKSPACE workspace;
    std::vector<PHLWINDOW> windows;
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

static double overviewSmoothStep(double edge0, double edge1, double value) {
    const double range = std::max(0.0001, edge1 - edge0);
    const double t = overviewClamp01((value - edge0) / range);
    return t * t * (3.0 - 2.0 * t);
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

static void renderOverviewBackdrop(PHLMONITOR owner, const CBox& monitorClip, const Time::steady_tp& time, double openProgress, double dimTargetAlpha) {
    if (!owner)
        return;

    // Draw the real desktop background over the whole monitor first.
    // The overview should feel like one unified GNOME-like canvas. Topbar and
    // AppDock are layer surfaces rendered by Hyprland after this POST_WINDOWS
    // hook, so they remain visible and clickable.
    const bool hasBackground = renderFullscreenBackground(owner, monitorClip, time);
    if (!hasBackground)
        renderRect(CBox{0, 0, owner->m_transformedSize.x, owner->m_transformedSize.y}, CHyprColor(0.02, 0.025, 0.032, 1.0));

    // One global background layer for the whole overview:
    // wallpaper -> blur/dim overlay -> mode content.
    const CBox fullscreenDim = CBox{0, 0, owner->m_transformedSize.x, owner->m_transformedSize.y};
    const double dimAlpha = overviewLerp(0.0, dimTargetAlpha, openProgress);
    if (dimAlpha > 0.001) {
        if (!Config::disableBlur) {
            renderRectWithBlur(fullscreenDim, CHyprColor(0.02, 0.025, 0.032, dimAlpha));
        } else {
            renderRect(fullscreenDim, CHyprColor(0.02, 0.025, 0.032, dimAlpha));
        }
    }
}

static CBox overviewApplicationCardBox(PHLMONITOR owner, double openProgress) {
    if (!owner)
        return CBox{0, 0, 1, 1};

    constexpr double CARD_PHASE_END = 0.48;
    const double cardProgress = overviewEaseInOutCubic(openProgress / CARD_PHASE_END);
    const double liftProgress = overviewEaseInOutCubic((openProgress - CARD_PHASE_END) / (1.0 - CARD_PHASE_END));

    const CBox fullDesktopBox = CBox{0, 0, owner->m_transformedSize.x, owner->m_transformedSize.y};
    const double margin = std::max<double>(8.0, Config::workspaceMargin * owner->m_scale);
    const double reservedBottom = std::max<double>(0.0, Config::reservedArea * owner->m_scale);
    const double availableW = owner->m_transformedSize.x;
    const double availableH = std::max<double>(120.0, owner->m_transformedSize.y - reservedBottom);
    const double topReservedPixels = overviewTopReservedPixels(owner);
    const double previewSourceTopInset = std::max<double>(0.0, topReservedPixels - 1.0);
    const double previewSourceH = std::max<double>(120.0, owner->m_transformedSize.y - previewSourceTopInset);
    const double centerPreviewScale = std::min<double>(
        0.64,
        std::min((availableH - margin * 2.0) / std::max<double>(previewSourceH, 1.0),
                 (availableW - margin * 2.0) / (std::max<double>(owner->m_transformedSize.x, 1.0) * 1.08)));

    const CBox overviewCardBox = CBox{
        (availableW - owner->m_transformedSize.x * centerPreviewScale) * 0.5,
        std::max<double>(margin, (availableH - previewSourceH * centerPreviewScale) * 0.5),
        owner->m_transformedSize.x * centerPreviewScale,
        previewSourceH * centerPreviewScale,
    };

    const double liftDistance = overviewCardBox.y + overviewCardBox.h + std::max<double>(42.0, owner->m_transformedSize.y * 0.08);
    CBox liftedCardBox = overviewCardBox;
    liftedCardBox.y -= liftDistance;

    const CBox cardBox = overviewLerpBox(fullDesktopBox, overviewCardBox, cardProgress);
    return overviewPixelSnappedBox(overviewLerpBox(cardBox, liftedCardBox, liftProgress));
}

static CBox overviewApplicationsLayerBox(PHLMONITOR owner, double openProgress) {
    if (!owner)
        return CBox{0, 0, 1, 1};

    constexpr double CARD_PHASE_END = 0.48;
    const double liftProgress = overviewEaseInOutCubic((openProgress - CARD_PHASE_END) / (1.0 - CARD_PHASE_END));
    const double riseOffset = std::max<double>(240.0, owner->m_transformedSize.y * 0.42);
    const double y = overviewLerp(riseOffset, 0.0, liftProgress);

    return CBox{0, y, owner->m_transformedSize.x, owner->m_transformedSize.y};
}

static bool applicationsLayerReady(PHLMONITOR owner) {
    if (!owner)
        return false;

    for (size_t layerIndex = 0; layerIndex < 4; ++layerIndex) {
        for (auto& weakLayer : owner->m_layerSurfaceLayers[layerIndex]) {
            const auto layer = weakLayer.lock();
            if (!layer)
                continue;
            if (layer->m_namespace != "quickshell:applications")
                continue;
            if (!layer->m_mapped || layer->m_readyToDelete || !layer->m_layerSurface || !layer->wlSurface() || !layer->wlSurface()->resource())
                continue;

            const Vector2D layerSize = layer->m_realSize->value() * owner->m_scale;
            if (!(layerSize.x > 1.0 && layerSize.y > 1.0))
                continue;

            return true;
        }
    }

    return false;
}

static bool renderApplicationsLayerBelowOverviewCard(PHLMONITOR owner, const CBox& monitorClip, double openProgress) {
    if (!owner)
        return false;

    for (size_t layerIndex = 0; layerIndex < 4; ++layerIndex) {
        for (auto& weakLayer : owner->m_layerSurfaceLayers[layerIndex]) {
            const auto layer = weakLayer.lock();
            if (!layer)
                continue;
            if (layer->m_namespace != "quickshell:applications")
                continue;
            if (!layer->m_mapped || layer->m_readyToDelete || !layer->m_layerSurface || !layer->wlSurface() || !layer->wlSurface()->resource())
                continue;

            const Vector2D layerSize = layer->m_realSize->value() * owner->m_scale;
            if (!(layerSize.x > 1.0 && layerSize.y > 1.0))
                continue;

            const CBox layerBox = overviewApplicationsLayerBox(owner, openProgress);
            renderLayerSurfaceTextureStub(layer, layerBox, monitorClip, 1.0F);
            return true;
        }
    }

    return false;
}

static void renderApplicationsSideWorkspacePreviews(PHLMONITOR owner,
                                                    const std::vector<int>& workspaces,
                                                    int centerWorkspaceID,
                                                    const CBox& monitorClip,
                                                    const Time::steady_tp& time,
                                                    double openProgress) {
    if (!owner || workspaces.size() <= 1)
        return;

    auto centerIt = std::find(workspaces.begin(), workspaces.end(), centerWorkspaceID);
    if (centerIt == workspaces.end()) {
        centerIt = std::lower_bound(workspaces.begin(), workspaces.end(), centerWorkspaceID);
        if (centerIt == workspaces.end())
            centerIt = std::prev(workspaces.end());
    }

    const int centerIndex = std::clamp(static_cast<int>(std::distance(workspaces.begin(), centerIt)), 0, static_cast<int>(workspaces.size()) - 1);
    constexpr double CARD_PHASE_END = 0.48;
    const double sideProgress = overviewEaseInOutCubic((openProgress - CARD_PHASE_END) / (1.0 - CARD_PHASE_END));
    const float opacity = static_cast<float>(std::clamp(1.0 - sideProgress, 0.0, 1.0));
    if (opacity <= 0.001F)
        return;

    const double margin = std::max<double>(8.0, Config::workspaceMargin * owner->m_scale);
    const double workspaceGap = std::max<double>(22.0, Config::workspaceMargin * owner->m_scale * 1.45);
    const double reservedBottom = std::max<double>(0.0, Config::reservedArea * owner->m_scale);
    const double availableW = owner->m_transformedSize.x;
    const double availableH = std::max<double>(120.0, owner->m_transformedSize.y - reservedBottom);
    const double topReservedPixels = overviewTopReservedPixels(owner);
    const double previewSourceTopInset = std::max<double>(0.0, topReservedPixels - 1.0);
    const double previewSourceH = std::max<double>(120.0, owner->m_transformedSize.y - previewSourceTopInset);
    const int workspaceRounding = overviewWorkspaceRounding(owner);

    const double centerPreviewScale = std::min<double>(
        0.64,
        std::min((availableH - margin * 2.0) / std::max<double>(previewSourceH, 1.0),
                 (availableW - margin * 2.0) / (std::max<double>(owner->m_transformedSize.x, 1.0) * 1.08)));
    const double sidePreviewScale = std::max<double>(0.24, centerPreviewScale * 0.72);

    std::vector<double> previewScales(workspaces.size(), sidePreviewScale);
    std::vector<CBox> baseWorkspaceBoxes(workspaces.size());
    for (size_t index = 0; index < workspaces.size(); ++index) {
        const double distance = std::min<double>(1.0, std::abs(static_cast<double>(index) - static_cast<double>(centerIndex)));
        previewScales[index] = overviewLerp(centerPreviewScale, sidePreviewScale, distance);
    }

    baseWorkspaceBoxes[centerIndex] = CBox{
        (availableW - owner->m_transformedSize.x * previewScales[centerIndex]) * 0.5,
        std::max<double>(margin, (availableH - previewSourceH * previewScales[centerIndex]) * 0.5),
        owner->m_transformedSize.x * previewScales[centerIndex],
        previewSourceH * previewScales[centerIndex],
    };

    for (int index = centerIndex - 1; index >= 0; --index) {
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

    for (size_t index = static_cast<size_t>(centerIndex + 1); index < workspaces.size(); ++index) {
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

    auto renderSidePreview = [&](size_t index) {
        if (static_cast<int>(index) == centerIndex)
            return;

        PHLWORKSPACE workspace = g_pCompositor->getWorkspaceByID(workspaces[index]);
        CBox workspaceBox = baseWorkspaceBoxes[index];
        const int direction = static_cast<int>(index) < centerIndex ? -1 : 1;
        const double offscreenX = direction < 0
            ? -workspaceBox.w - std::max<double>(64.0, owner->m_transformedSize.x * 0.05)
            : owner->m_transformedSize.x + std::max<double>(64.0, owner->m_transformedSize.x * 0.05);
        workspaceBox.x = overviewLerp(workspaceBox.x, offscreenX, sideProgress);
        workspaceBox = overviewPixelSnappedBox(workspaceBox);

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

        if (workspace) {
            for (auto& w : g_pCompositor->m_windows) {
                if (!w || !w->m_isMapped || !w->m_workspace || w->m_workspace != workspace)
                    continue;

                const double wX = workspaceBox.x + ((w->m_realPosition->value().x - owner->m_position.x) * monitorScaleForPreview);
                const double wY = workspaceBox.y + ((w->m_realPosition->value().y - owner->m_position.y) * monitorScaleForPreview) - (previewSourceTopInset * previewScale);
                const double wW = w->m_realSize->value().x * monitorScaleForPreview;
                const double wH = w->m_realSize->value().y * monitorScaleForPreview;
                if (!(wW > 1.0 && wH > 1.0))
                    continue;

                const CBox windowBox = CBox{wX, wY, wW, wH};
                if (!overviewBoxesIntersect(windowBox, workspaceBox))
                    continue;

                const bool coversWorkspace = wX <= workspaceBox.x + 1.0 &&
                    wY <= workspaceBox.y + 1.0 &&
                    wX + wW >= workspaceBox.x + workspaceBox.w - 1.0 &&
                    wY + wH >= workspaceBox.y + workspaceBox.h - 1.0;
                const bool overlapsWorkspaceCorner = overviewBoxOverlapsWorkspaceCorner(windowBox, workspaceBox, workspaceRounding);
                visibleWindows.push_back({w, windowBox, coversWorkspace, overlapsWorkspaceCorner});
            }
        }

        renderWorkspacePreviewShadow(owner, workspaceBox, workspaceRounding, opacity);

        const bool fullCoverWindowVisible = std::any_of(visibleWindows.begin(), visibleWindows.end(), [](const SOverviewWindowPreview& windowPreview) {
            return windowPreview.coversWorkspace;
        });

        if (!fullCoverWindowVisible) {
            const bool backgroundRendered = renderWorkspaceBackgroundTexture(owner, workspaceBox, workspaceBox, opacity, workspaceRounding, 2.0F);
            CHyprColor tintColor = Config::workspaceInactiveBackground;
            tintColor.a = backgroundRendered
                ? std::max<float>(tintColor.a * opacity, 0.10F * opacity)
                : std::max<float>(tintColor.a * opacity, 0.22F * opacity);
            renderRect(workspaceBox, tintColor, workspaceRounding, 2.0F);
        }

        for (const auto& windowPreview : visibleWindows)
            renderWindowStub(windowPreview.window, owner, workspace, windowPreview.box, workspaceBox, time, opacity, -1, 2.0F);

        if (std::any_of(visibleWindows.begin(), visibleWindows.end(), [](const SOverviewWindowPreview& windowPreview) {
                return windowPreview.overlapsWorkspaceCorner;
            }))
            renderOverviewCornerMask(owner, workspaceBox, opacity, workspaceRounding, 0.28F);
    };

    for (size_t index = 0; index < workspaces.size(); ++index)
        renderSidePreview(index);
}

static void renderApplicationsDesktopCard(PHLMONITOR owner, PHLWORKSPACE workspace, const CBox& monitorClip, const Time::steady_tp& time, double openProgress) {
    if (!owner || !workspace)
        return;

    const CBox workspaceBox = overviewApplicationCardBox(owner, openProgress);
    if (!overviewBoxesIntersect(workspaceBox, monitorClip))
        return;

    const double previewScale = workspaceBox.w / std::max<double>(owner->m_transformedSize.x, 1.0);
    const double monitorScaleForPreview = previewScale * owner->m_scale;
    const double topReservedPixels = overviewTopReservedPixels(owner);
    constexpr double CARD_PHASE_END = 0.48;
    const double cardProgress = overviewEaseInOutCubic(openProgress / CARD_PHASE_END);
    const double previewSourceTopInset = std::max<double>(0.0, topReservedPixels - 1.0) * cardProgress;
    const int rounding = static_cast<int>(std::round(overviewWorkspaceRounding(owner) * cardProgress));
    const float fadeProgress = static_cast<float>(overviewSmoothStep(0.62, 1.0, openProgress));
    const float blurProgress = static_cast<float>(overviewSmoothStep(0.54, 0.92, openProgress));
    const float alpha = std::clamp(1.0F - fadeProgress, 0.0F, 1.0F);
    if (alpha <= 0.001F)
        return;

    std::vector<SOverviewWindowPreview> visibleWindows;
    for (auto& w : g_pCompositor->m_windows) {
        if (!w || !w->m_isMapped || !w->m_workspace || w->m_workspace != workspace)
            continue;

        const double wX = workspaceBox.x + ((w->m_realPosition->value().x - owner->m_position.x) * monitorScaleForPreview);
        const double wY = workspaceBox.y + ((w->m_realPosition->value().y - owner->m_position.y) * monitorScaleForPreview) - (previewSourceTopInset * previewScale);
        const double wW = w->m_realSize->value().x * monitorScaleForPreview;
        const double wH = w->m_realSize->value().y * monitorScaleForPreview;
        if (!(wW > 1.0 && wH > 1.0))
            continue;

        const CBox windowBox = CBox{wX, wY, wW, wH};
        if (!overviewBoxesIntersect(windowBox, workspaceBox))
            continue;

        const bool coversWorkspace = wX <= workspaceBox.x + 1.0 &&
            wY <= workspaceBox.y + 1.0 &&
            wX + wW >= workspaceBox.x + workspaceBox.w - 1.0 &&
            wY + wH >= workspaceBox.y + workspaceBox.h - 1.0;
        const bool overlapsWorkspaceCorner = overviewBoxOverlapsWorkspaceCorner(windowBox, workspaceBox, rounding);
        visibleWindows.push_back({w, windowBox, coversWorkspace, overlapsWorkspaceCorner});
    }

    renderWorkspacePreviewShadow(owner, workspaceBox, rounding, alpha);

    const bool fullCoverWindowVisible = std::any_of(visibleWindows.begin(), visibleWindows.end(), [](const SOverviewWindowPreview& windowPreview) {
        return windowPreview.coversWorkspace;
    });

    if (!fullCoverWindowVisible) {
        const bool backgroundRendered = renderWorkspaceBackgroundTexture(owner, workspaceBox, workspaceBox, alpha, rounding, 2.0F);
        CHyprColor tintColor = Config::workspaceActiveBackground;
        const float tintProgress = static_cast<float>(overviewClamp01(openProgress));
        tintColor.a = backgroundRendered
            ? std::max<float>(tintColor.a * alpha * tintProgress, 0.10F * alpha * tintProgress)
            : std::max<float>(tintColor.a * alpha * tintProgress, 0.22F * alpha * tintProgress);
        if (tintColor.a > 0.001F)
            renderRect(workspaceBox, tintColor, rounding, 2.0F);
    }

    for (const auto& windowPreview : visibleWindows)
        renderWindowStub(windowPreview.window, owner, workspace, windowPreview.box, workspaceBox, time, alpha, -1, 2.0F);

    if (!Config::disableBlur && blurProgress > 0.001F) {
        const float blurAlpha = std::clamp(0.46F * blurProgress * std::max(alpha, 0.24F), 0.0F, 0.46F);
        renderRectWithBlur(workspaceBox, CHyprColor(0.02, 0.025, 0.032, blurAlpha), rounding, 2.0F);
    }

    if (std::any_of(visibleWindows.begin(), visibleWindows.end(), [](const SOverviewWindowPreview& windowPreview) {
            return windowPreview.overlapsWorkspaceCorner;
        }))
        renderOverviewCornerMask(owner, workspaceBox, alpha, rounding, 0.28F);
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
    double rawOpenProgress = selectionCloseMorphRunning ? (1.0 - selectionProgress) : overviewOpenProgress();
    if (isClosing() && rawOpenProgress <= 0.001) {
        if (holdFinalFrameForCloseNotification()) {
            rawOpenProgress = 0.0;
        } else {
            finishHide();
            g_pHyprRenderer->damageMonitor(owner);
            return;
        }
    }

    const bool closingAnimationRunning = isClosing() || selectionCloseMorphRunning;
    const bool morphAnimationRunning = rawOpenProgress < 0.999 || closingAnimationRunning;
    const double openProgress = closingAnimationRunning
        ? overviewEaseInOutCubic(rawOpenProgress)
        : overviewEaseOutCubic(rawOpenProgress);

    g_pHyprRenderer->m_renderData.clipBox = monitorClip;

    renderOverviewBackdrop(owner, monitorClip, time, openProgress, 0.10);
    const double dimAlpha = overviewLerp(0.0, 0.10, openProgress);

    const auto workspaces = overviewWorkspaceIds();
    if (workspaces.empty())
        return;
    const int passiveTrailingWorkspaceID = maxOccupiedWorkspaceID() + 1;

    const double margin = std::max<double>(8.0, Config::workspaceMargin * owner->m_scale);
    const double workspaceGap = std::max<double>(22.0, Config::workspaceMargin * owner->m_scale * 1.45);
    const double reservedBottom = std::max<double>(0.0, Config::reservedArea * owner->m_scale);
    const double availableW = owner->m_transformedSize.x;
    const double availableH = std::max<double>(120.0, owner->m_transformedSize.y - reservedBottom);
    const double topReservedPixels = overviewTopReservedPixels(owner);
    const double previewSourceTopInset = std::max<double>(0.0, topReservedPixels - 1.0);
    const double previewSourceH = std::max<double>(120.0, owner->m_transformedSize.y - previewSourceTopInset);
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

    for (auto it = workspaceAppearProgress.begin(); it != workspaceAppearProgress.end();) {
        if (std::find(workspaces.begin(), workspaces.end(), it->first) == workspaces.end())
            it = workspaceAppearProgress.erase(it);
        else
            ++it;
    }

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

    std::vector<SOverviewWorkspaceWindows> windowsByWorkspace;
    windowsByWorkspace.reserve(workspaces.size());
    for (auto& w : g_pCompositor->m_windows) {
        if (!w)
            continue;
        if (!w->m_isMapped || !w->m_workspace)
            continue;

        auto bucket = std::find_if(windowsByWorkspace.begin(), windowsByWorkspace.end(), [&w](const SOverviewWorkspaceWindows& item) {
            return item.workspace == w->m_workspace;
        });

        if (bucket == windowsByWorkspace.end()) {
            SOverviewWorkspaceWindows item;
            item.workspace = w->m_workspace;
            item.windows.push_back(w);
            windowsByWorkspace.push_back(std::move(item));
        } else {
            bucket->windows.push_back(w);
        }
    }

    std::vector<SWorkspacePreview> previews;
    previews.reserve(workspaces.size());
    int hoveredPreviewIndex = -1;
    bool workspaceAppearAnimationRunning = false;

    for (size_t index = 0; index < workspaces.size(); ++index) {
        const int wsID = workspaces[index];
        const auto ws = g_pCompositor->getWorkspaceByID(wsID);
        const bool passiveTrailingPreview = wsID == passiveTrailingWorkspaceID &&
            wsID != centeredWorkspaceID &&
            wsID != workspaceSelectionToID &&
            wsID != std::max(1, static_cast<int>(owner->activeWorkspaceID()));
        float passiveAppearProgress = 1.0F;
        if (passiveTrailingPreview) {
            float& appearProgress = workspaceAppearProgress[wsID];
            appearProgress += (1.0F - appearProgress) * static_cast<float>(hoverEase);
            if (appearProgress > 0.995F)
                appearProgress = 1.0F;
            passiveAppearProgress = appearProgress;
            if (passiveAppearProgress < 1.0F)
                workspaceAppearAnimationRunning = true;
        }

        CBox workspaceBox = baseWorkspaceBoxes[index];
        workspaceBox.x += fractionalOffsetX;
        if (passiveTrailingPreview && passiveAppearProgress < 1.0F) {
            const double slide = owner->m_transformedSize.x * 0.035 * (1.0F - passiveAppearProgress);
            workspaceBox.x += slide;
        }

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
                const double sideExitProgress = overviewClamp01((rawOpenProgress - 0.30) / 0.70);
                const double sideProgress = closingAnimationRunning
                    ? sideExitProgress * sideExitProgress
                    : overviewEaseOutQuart((rawOpenProgress - 0.16) / 0.84);
                const double slideDistance = owner->m_transformedSize.x * (closingAnimationRunning ? 0.14 : 0.10);
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
        preview.topInset = previewSourceTopInset * openProgress;
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
            const auto workspaceWindows = std::find_if(windowsByWorkspace.begin(), windowsByWorkspace.end(), [&ws](const SOverviewWorkspaceWindows& item) {
                return item.workspace == ws;
            });

            if (workspaceWindows != windowsByWorkspace.end()) {
                visibleWindows.reserve(workspaceWindows->windows.size());
                for (auto& w : workspaceWindows->windows) {
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
        }

        if (preview.opacity <= 0.001F)
            return;

        renderWorkspacePreviewShadow(owner, workspaceBox, preview.rounding, preview.opacity);

        const bool fullCoverWindowVisible = !morphAnimationRunning && !selectionAnimationRunning && preview.opacity >= 0.999F &&
            std::any_of(visibleWindows.begin(), visibleWindows.end(), [](const SOverviewWindowPreview& windowPreview) {
                return windowPreview.coversWorkspace;
            });

        if (!fullCoverWindowVisible) {
            float backgroundOpacity = preview.opacity;
            if (preview.wsID == morphTargetWorkspaceID && (morphAnimationRunning || selectionAnimationRunning))
                backgroundOpacity *= static_cast<float>(openProgress);

            const bool backgroundRendered = renderWorkspaceBackgroundTexture(owner, workspaceBox, workspaceBox, backgroundOpacity, preview.rounding, 2.0F);

            CHyprColor tintColor = preview.wsID == morphTargetWorkspaceID ? Config::workspaceActiveBackground : Config::workspaceInactiveBackground;
            tintColor.a = backgroundRendered
                ? std::max<float>(tintColor.a * backgroundOpacity, 0.10F * backgroundOpacity)
                : std::max<float>(tintColor.a * backgroundOpacity, 0.22F * backgroundOpacity);
            renderRect(workspaceBox, tintColor, preview.rounding, 2.0F);
        }

        for (const auto& windowPreview : visibleWindows) {
            renderWindowStub(windowPreview.window, owner, ws, windowPreview.box, workspaceBox, time, preview.opacity, -1, 2.0F);
        }

        if (std::any_of(visibleWindows.begin(), visibleWindows.end(), [](const SOverviewWindowPreview& windowPreview) {
                return windowPreview.overlapsWorkspaceCorner;
            }))
            renderOverviewCornerMask(owner, workspaceBox, preview.opacity, preview.rounding, dimAlpha);

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

    if (morphAnimationRunning || selectionAnimationRunning || workspaceAppearAnimationRunning) {
        g_pHyprRenderer->damageMonitor(owner);
        g_pCompositor->scheduleFrameForMonitor(owner);
    }
}

void CHyprspaceWidget::drawApplicationsBackground() {
    workspaceBoxes.clear();

    if (!active)
        return;

    const auto owner = getOwner();
    if (!owner)
        return;

    constexpr double OVERVIEW_OPEN_ANIMATION_SECONDS = 0.24;
    constexpr double APPLICATIONS_PREVIEW_RAW_PROGRESS = 0.19585484828218835;

    auto setApplicationsRawProgress = [&](double rawProgress) {
        overviewAnimationStarted = true;
        overviewAnimationStartedAt = std::chrono::steady_clock::now() - std::chrono::duration_cast<std::chrono::steady_clock::duration>(
            std::chrono::duration<double>(OVERVIEW_OPEN_ANIMATION_SECONDS * std::clamp(rawProgress, 0.0, 1.0)));
    };

    const bool applicationLayerReady = applicationsLayerReady(owner);
    if (!isClosing() && !applicationLayerReady) {
        applicationsLayerReadyForTransition = false;
        setApplicationsRawProgress(applicationsTransitionStartedFromOverview ? APPLICATIONS_PREVIEW_RAW_PROGRESS : 0.0);
    }

    if (!isClosing() && applicationLayerReady && !applicationsLayerReadyForTransition) {
        applicationsLayerReadyForTransition = true;
        setApplicationsRawProgress(applicationsTransitionStartedFromOverview ? APPLICATIONS_PREVIEW_RAW_PROGRESS : 0.0);
    }

    const CBox monitorClip = {{0, 0}, owner->m_transformedSize};
    const auto time = Time::steadyNow();
    const bool selectionCloseMorphRunning = workspaceSelectionCloseMorphActive();
    const double selectionProgress = isSelectingWorkspace() ? workspaceSelectionProgress() : 1.0;
    double rawOpenProgress = selectionCloseMorphRunning ? (1.0 - selectionProgress) : overviewOpenProgress();
    double returnProgress = 1.0;
    if (applicationsReturningToOverview) {
        returnProgress = applicationsReturnProgress();
        rawOpenProgress = overviewLerp(1.0, APPLICATIONS_PREVIEW_RAW_PROGRESS, returnProgress);
    }
    if (isClosing() && rawOpenProgress <= 0.001) {
        if (holdFinalFrameForCloseNotification()) {
            rawOpenProgress = 0.0;
        } else {
            finishHide();
            g_pHyprRenderer->damageMonitor(owner);
            return;
        }
    }

    const bool closingAnimationRunning = isClosing() || selectionCloseMorphRunning;
    const bool morphAnimationRunning = rawOpenProgress < 0.999 || closingAnimationRunning;
    const bool returnAnimationFinished = applicationsReturningToOverview && returnProgress >= 0.999;
    const double openProgress = closingAnimationRunning
        ? overviewEaseInOutCubic(rawOpenProgress)
        : overviewEaseOutCubic(rawOpenProgress);

    g_pHyprRenderer->m_renderData.clipBox = monitorClip;

    // GNOME Applications is not a popup over workspace previews. It is the
    // second overview mode. Render the applications layer inside the plugin,
    // below the shrinking desktop card, so both surfaces animate as one scene.
    renderOverviewBackdrop(owner, monitorClip, time, openProgress, 0.28);
    renderApplicationsLayerBelowOverviewCard(owner, monitorClip, openProgress);

    if ((applicationsTransitionStartedFromOverview || applicationsReturningToOverview) && !isClosing()) {
        const auto workspaces = overviewWorkspaceIds();
        const int workspaceID = centeredWorkspaceID > 0
            ? centeredWorkspaceID
            : std::max(1, static_cast<int>(owner->activeWorkspaceID()));
        renderApplicationsSideWorkspacePreviews(owner, workspaces, workspaceID, monitorClip, time, openProgress);
    }

    const int workspaceID = centeredWorkspaceID > 0
        ? centeredWorkspaceID
        : std::max(1, static_cast<int>(owner->activeWorkspaceID()));
    PHLWORKSPACE workspace = g_pCompositor->getWorkspaceByID(workspaceID);
    if (!workspace)
        workspace = owner->m_activeWorkspace;
    renderApplicationsDesktopCard(owner, workspace, monitorClip, time, openProgress);

    if (morphAnimationRunning) {
        g_pHyprRenderer->damageMonitor(owner);
        g_pCompositor->scheduleFrameForMonitor(owner);
    }

    if (returnAnimationFinished) {
        applicationsReturningToOverview = false;
        applicationsTransitionStartedFromOverview = false;
        applicationsLayerReadyForTransition = false;
        overviewAnimationStarted = false;
        if (applicationsReturnToOverviewFinishedCallback)
            applicationsReturnToOverviewFinishedCallback();
        g_pHyprRenderer->damageMonitor(owner);
        g_pCompositor->scheduleFrameForMonitor(owner);
        return;
    }

    if (applicationsReturningToOverview) {
        g_pHyprRenderer->damageMonitor(owner);
        g_pCompositor->scheduleFrameForMonitor(owner);
    }
}

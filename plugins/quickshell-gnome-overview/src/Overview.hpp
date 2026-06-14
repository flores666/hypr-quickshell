#pragma once
#include <hyprland/src/Compositor.hpp>
#include <hyprutils/animation/AnimationConfig.hpp>
#include <chrono>
#include <unordered_map>
#include <vector>

class CHyprspaceWidget {

    bool active = false;

    int64_t ownerID;

    // animation override stuff
    Hyprutils::Animation::SAnimationPropertyConfig curAnimationConfig;
    Hyprutils::Animation::SAnimationPropertyConfig curAnimation;

    // for checking mouse hover for workspace drag and move
    // modified on draw call, accessed on mouse click and release
    std::vector<std::tuple<int, CBox>> workspaceBoxes;

    // for storing the fullscreen state of windows prior to overview activation (which unfullscreens all windows)
    std::vector<std::tuple<PHLWINDOWREF, eFullscreenMode>> prevFullscreen;

    // for storing the layer alpha values prior to overview activation (which sets all panel to transparent when configured)
    std::vector<std::tuple<PHLLS, float>> oLayerAlpha;

    // for click-to-exit
    std::chrono::system_clock::time_point lastPressedTime = std::chrono::high_resolution_clock::now();

    bool swiping = false;
    // whether if the panel is active before the current swiping event
    bool activeBeforeSwipe = false;
    double avgSwipeSpeed = 0.;
    // number of swiping speed frames recorded
    int swipePoints = 0;
    // on second thought, this seems redundant as we could just write to curYOffset while swiping
    double curSwipeOffset = 10.;

    PHLANIMVAR<float> workspaceScrollOffset;

    // Scroll bounds are recalculated on every draw from the current workspace ribbon
    // geometry. axisEvent clamps against them so scrolling from workspace 1 starts
    // immediately instead of first fighting the final startX clamp in draw().
    double workspaceScrollMin = 0.0;
    double workspaceScrollMax = 0.0;

    // Smooth touchpad scrolling is accumulated and converted into exact one-workspace
    // steps. Coarse mouse-wheel notches switch immediately by exactly one workspace.
    double workspaceScrollAccumulator = 0.0;

    // Per-workspace hover progress for the small GNOME-like zoom on hover.
    std::unordered_map<int, float> workspaceHoverProgress;

    // Workspace preview currently centered in the overview strip. This is
    // intentionally separate from Hyprland's active workspace: empty in-between
    // workspaces often do not exist until switched to, so the overview must be
    // able to scroll through their numeric slot even before Hyprland creates
    // a real workspace object for it.
    int centeredWorkspaceID = 0;
    std::chrono::steady_clock::time_point lastWorkspaceHoverFrame;
    bool lastWorkspaceHoverFrameValid = false;

    std::chrono::steady_clock::time_point overviewAnimationStartedAt;
    bool overviewAnimationStarted = false;

    std::chrono::steady_clock::time_point overviewClosingStartedAt;
    bool overviewClosing = false;

    double currentWorkspaceStep() const;
    double overviewOpenProgress() const;
    bool isClosing() const;
    std::vector<int> overviewWorkspaceIds() const;

    void closeOwnerSpecialWorkspace();
    void finishHide();
    bool switchOverviewWorkspaceBy(int direction);

public:

    // for slide-in animation and swiping
    PHLANIMVAR<float> curYOffset;

    CHyprspaceWidget(uint64_t);
    ~CHyprspaceWidget();

    PHLMONITOR getOwner() const;
    bool isActive();

    void show();
    void hide();

    void updateConfig();

    // should be called active or not
    void draw();

    // reserves area on owner monitor
    void updateLayout();

    bool buttonEvent(bool, Vector2D coords);
    bool axisEvent(double, wl_pointer_axis axis, Vector2D coords);

    bool isSwiping();

    bool beginSwipe(IPointer::SSwipeBeginEvent);
    bool updateSwipe(IPointer::SSwipeUpdateEvent);
    bool endSwipe(IPointer::SSwipeEndEvent);

};

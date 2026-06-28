#pragma once
#include <hyprland/src/Compositor.hpp>
#include <hyprutils/animation/AnimationConfig.hpp>
#include <chrono>
#include <unordered_map>
#include <vector>

class CHyprspaceWidget {

    bool active = false;

    int64_t ownerID;

    // While the native overview is visible, Hyprland's own workspace
    // transition animation must be suppressed. Otherwise selecting or scrolling
    // workspaces inside the overview makes the real desktop perform its normal
    // swipe/slide animation behind the custom GNOME-like morph.
    Hyprutils::Animation::SAnimationPropertyConfig savedWorkspaceAnimation;
    bool workspaceAnimationSuppressed = false;

    // for checking mouse hover for workspace drag and move
    // modified on draw call, accessed on mouse click and release
    std::vector<std::tuple<int, CBox>> workspaceBoxes;

    // for click-to-exit
    std::chrono::system_clock::time_point lastPressedTime = std::chrono::high_resolution_clock::now();

    // Smooth touchpad scrolling is accumulated and converted into exact one-workspace
    // steps. Coarse mouse-wheel notches switch immediately by exactly one workspace.
    double workspaceScrollAccumulator = 0.0;

    // Per-workspace hover progress for hit testing and draw ordering.
    std::unordered_map<int, float> workspaceHoverProgress;
    std::unordered_map<int, float> workspaceAppearProgress;

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

    // When the user selects a side workspace in the overview, first animate the
    // overview ribbon to that workspace and only then run the existing GNOME-like
    // exit morph. This keeps the visual transition inside the plugin instead of
    // letting Hyprland snap the selected preview to the center.
    std::chrono::steady_clock::time_point workspaceSelectionAnimationStartedAt;
    bool workspaceSelectionAnimating = false;
    bool closeAfterWorkspaceSelectionAnimation = false;
    bool closeNotifiedForWorkspaceSelection = false;
    bool closeNotifyPendingForAnimatedHide = false;
    bool releaseAfterCloseNotification = false;
    std::chrono::steady_clock::time_point releaseAfterCloseNotificationStartedAt;
    bool applicationsModeResetPendingForAnimatedHide = false;
    bool applicationsTransitionStartedFromOverview = false;
    bool applicationsLayerReadyForTransition = false;
    bool applicationsLayerHiddenForClose = false;
    bool applicationsLayerSettledNotified = false;
    bool applicationsReturningToOverview = false;
    std::chrono::steady_clock::time_point applicationsReturnStartedAt;
    bool applyingWorkspaceActivation = false;

    static constexpr double OVERVIEW_OPEN_ANIMATION_SECONDS = 0.24;
    static constexpr double OVERVIEW_CLOSE_ANIMATION_SECONDS = 0.22;
    static constexpr double APPLICATIONS_OPEN_ANIMATION_SECONDS = 0.34;
    static constexpr double APPLICATIONS_CLOSE_ANIMATION_SECONDS = 0.30;
    static constexpr double APPLICATIONS_RETURN_ANIMATION_SECONDS = 0.30;
    static constexpr double APPLICATIONS_CARD_PHASE_END = 0.48;
    // Raw overview progress whose eased value is APPLICATIONS_CARD_PHASE_END.
    // It keeps the applications-enter animation on the same desktop-card
    // position used by the mainMod applications-exit path.
    static constexpr double APPLICATIONS_PREVIEW_RAW_PROGRESS = 0.19585484828218835;
    static constexpr double APPLICATIONS_FROM_OVERVIEW_START_PROGRESS = APPLICATIONS_PREVIEW_RAW_PROGRESS;
    int workspaceSelectionFromID = 0;
    int workspaceSelectionToID = 0;

    double overviewOpenProgress() const;
    double workspaceSelectionProgress() const;
    bool workspaceSelectionCloseMorphActive() const;
    double visualCenterWorkspaceIndex(const std::vector<int>& ids) const;
    bool isSelectingWorkspace() const;
    int maxOccupiedWorkspaceID() const;
    int maxSelectableWorkspaceID() const;
    std::vector<int> overviewWorkspaceIds() const;

    void closeOwnerSpecialWorkspace();
    void suppressWorkspaceTransitionAnimation();
    void restoreWorkspaceTransitionAnimation();
    void warpWorkspaceTransitionState(int visibleWorkspaceID);
    void activateWorkspaceForOverview(int targetWorkspaceID);
    void finishHide();
    bool holdFinalFrameForCloseNotification();
    bool switchOverviewWorkspaceBy(int direction);
    bool startWorkspaceSelectionAnimation(int targetWorkspaceID, bool closeAfterAnimation);
    void finishWorkspaceSelectionAnimation();
    double applicationsReturnProgress() const;
    double applicationsOverviewOpenProgress() const;
    void setOverviewCursor();

public:

    CHyprspaceWidget(uint64_t);
    ~CHyprspaceWidget();

    PHLMONITOR getOwner() const;
    bool isActive();
    bool isClosing() const;
    bool isAnimating() const;
    bool isApplyingWorkspaceActivation() const;

    void show();
    void startApplicationsTransitionFromOverview();
    void startApplicationsReturnToOverview();
    void hide();
    void hideKeepingWorkspace(int workspaceID);

    // should be called active or not
    void draw();
    void drawApplicationsBackground();

    bool buttonEvent(bool, Vector2D coords);
    bool axisEvent(double, wl_pointer_axis axis, Vector2D coords);

    // Animate the overview ribbon without switching the real Hyprland workspace.
    // Used by Quickshell topbar clicks/scroll and by intercepted mainMod+N
    // shortcuts while overview is open.
    bool selectWorkspaceInOverview(int targetWorkspaceID);
    bool activateWorkspaceInOverview(int targetWorkspaceID);
    bool selectWorkspaceInOverviewBy(int direction);
    bool syncExternalWorkspaceSwitch(int targetWorkspaceID);
    bool activateWorkspaceBy(int direction);

};

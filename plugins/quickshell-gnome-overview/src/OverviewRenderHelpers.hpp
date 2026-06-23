#pragma once

#include "Globals.hpp"

void renderRect(CBox box, CHyprColor color, int rounding = 0, float roundingPower = 2.0F);
void renderRectWithBlur(CBox box, CHyprColor color, int rounding = 0, float roundingPower = 2.0F);
void renderWindowStub(PHLWINDOW pWindow, PHLMONITOR pMonitor, PHLWORKSPACE pWorkspaceOverride, CBox rectOverride, CBox clipBox, const Time::steady_tp& time, float alpha = 1.F, int forcedRounding = -1, float forcedRoundingPower = 2.0F);
void renderLayerSurfaceStub(PHLLS pLayer, PHLMONITOR pMonitor, CBox rectOverride, CBox clipBox, const Time::steady_tp& time, float alpha = 1.F, int rounding = 0, float roundingPower = 2.0F);
void renderLayerSurfaceTextureStub(PHLLS pLayer, CBox rectOverride, CBox clipBox, float alpha = 1.F, int rounding = 0, float roundingPower = 2.0F);
bool renderFullscreenBackground(PHLMONITOR pMonitor, const CBox& monitorClip, const Time::steady_tp& time);
bool renderWorkspaceBackgroundTexture(PHLMONITOR pMonitor, const CBox& workspaceBox, const CBox& clipBox, float alpha, int rounding, float roundingPower);

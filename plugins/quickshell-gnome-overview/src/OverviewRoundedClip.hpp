#pragma once

#include "Globals.hpp"

#include <hyprland/src/render/Texture.hpp>

bool renderRoundedClippedTexture(
    SP<Render::ITexture> texture,
    const CBox& textureBox,
    const CBox& clipRoundedBox,
    int clipRounding,
    const CBox& contentRoundedBox,
    int contentRounding,
    float opacity);

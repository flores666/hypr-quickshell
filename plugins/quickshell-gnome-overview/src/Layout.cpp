#include "Overview.hpp"
#include "Globals.hpp"

void CHyprspaceWidget::updateLayout() {
    // Minimal overview mode does not reserve monitor space, change gaps, or rewrite workspace rules.
    // This keeps toggle safe: the plugin only renders previews and a dim background.
}

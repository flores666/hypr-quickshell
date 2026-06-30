import QtQuick
import "../../services" as Services

QtObject {
    id: root

    property var panel: null
    property var modelController: null
    property var tooltipController: null

    function itemKey(item) { return modelController ? modelController.itemKey(item) : ""; }
    function orderKeyFor(item) { return modelController ? modelController.orderKeyFor(item) : ""; }

    function canDragItem(item) {
        return item && orderKeyFor(item).length > 0;
    }

    function visualIndexForItemKey(key) {
        var lookup = String(key || "");
        for (var i = 0; i < panel.panelItems.length; i++) {
            if (itemKey(panel.panelItems[i]) === lookup)
                return i;
        }
        return panel.panelItems.length;
    }

    function pinnedInsertionIndexFor(item) {
        var visual = visualIndexForItemKey(itemKey(item));
        var count = 0;
        for (var i = 0; i < Math.min(visual, panel.panelItems.length); i++) {
            if (panel.panelItems[i] && panel.panelItems[i].pinned)
                count++;
        }
        return count;
    }

    function visualIndexAtContentX(contentX) {
        var count = Math.max(0, panel.panelItems.length);
        if (count <= 0)
            return 0;

        var step = panel.itemSize + panel.itemSpacing;
        var index = Math.round((contentX - panel.itemSize / 2) / step);
        return Math.max(0, Math.min(index, count - 1));
    }

    function draggedPreviewOrder() {
        var items = panel.panelItems.slice();
        if (!panel.draggingItem || !panel.draggingItemId)
            return items;

        var from = -1;
        for (var i = 0; i < items.length; i++) {
            if (items[i] && itemKey(items[i]) === panel.draggingItemId) {
                from = i;
                break;
            }
        }
        if (from < 0)
            return items;

        var item = items.splice(from, 1)[0];
        var to = Math.max(0, Math.min(panel.dragTargetIndex, items.length));
        items.splice(to, 0, item);
        return items;
    }

    function dockOrderFromPreview() {
        var items = draggedPreviewOrder();
        var result = [];
        for (var i = 0; i < items.length; i++) {
            var item = items[i];
            if (!canDragItem(item))
                continue;
            var key = orderKeyFor(item);
            if (key.length > 0 && result.indexOf(key) < 0)
                result.push(key);
        }
        return result;
    }

    function currentDockOrder() {
        var result = [];
        for (var i = 0; i < panel.panelItems.length; i++) {
            var item = panel.panelItems[i];
            if (!canDragItem(item))
                continue;
            var key = orderKeyFor(item);
            if (key.length > 0 && result.indexOf(key) < 0)
                result.push(key);
        }
        return result;
    }

    function dragShiftFor(item) {
        if (!panel.draggingItem || !item || itemKey(item) === panel.draggingItemId)
            return 0;

        var index = visualIndexForItemKey(itemKey(item));
        if (index < 0 || panel.dragSourceIndex < 0 || panel.dragTargetIndex < 0 || panel.dragSourceIndex === panel.dragTargetIndex)
            return 0;

        var step = panel.itemSize + panel.itemSpacing;
        if (panel.dragTargetIndex > panel.dragSourceIndex && index > panel.dragSourceIndex && index <= panel.dragTargetIndex)
            return -step;
        if (panel.dragTargetIndex < panel.dragSourceIndex && index >= panel.dragTargetIndex && index < panel.dragSourceIndex)
            return step;
        return 0;
    }

    function beginItemDrag(item, contentX) {
        if (!canDragItem(item))
            return;

        panel.closePopup();
        panel.draggingItem = true;
        panel.draggingItemId = itemKey(item);
        panel.dragSourceIndex = visualIndexForItemKey(panel.draggingItemId);
        panel.dragTargetIndex = visualIndexAtContentX(contentX);
        if (tooltipController)
            tooltipController.hide();
    }

    function updateItemDragTarget(contentX) {
        if (!panel.draggingItem)
            return;
        panel.dragTargetIndex = visualIndexAtContentX(contentX);
    }

    function finishItemDrag() {
        var nextOrder = dockOrderFromPreview();
        var changed = panel.draggingItemId.length > 0
                && panel.dragSourceIndex >= 0
                && panel.dragTargetIndex >= 0
                && panel.dragTargetIndex !== panel.dragSourceIndex;

        panel.draggingItem = false;
        panel.draggingItemId = "";
        panel.dragSourceIndex = -1;
        panel.dragTargetIndex = -1;

        if (changed)
            Services.AppPanelService.setOrder(nextOrder);
        if (panel.rebuildQueued) {
            panel.rebuildQueued = false;
            if (modelController)
                modelController.rebuildModel();
        }
    }

    function cancelItemDrag() {
        panel.draggingItem = false;
        panel.draggingItemId = "";
        panel.dragSourceIndex = -1;
        panel.dragTargetIndex = -1;
        if (panel.rebuildQueued) {
            panel.rebuildQueued = false;
            if (modelController)
                modelController.rebuildModel();
        }
    }

}

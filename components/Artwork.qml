pragma ComponentBehavior: Bound

import QtQuick
import "../qml/SourceState.js" as SourceState

Rectangle {
    id: root
    required property var tokens
    property string artworkPath: ""
    // False leaves the box empty until the art arrives: no tinted square and
    // no music glyph standing in while it loads.
    property bool placeholder: true
    readonly property bool ready: raster.ready
    readonly property bool showingPrevious: previous.shown
    readonly property url safeSource: SourceState.artworkUrl(artworkPath)
    readonly property bool motionAllowed: visible && !tokens.reducedMotion
    readonly property bool fadeRunning: fade.running
    implicitWidth: tokens.artSize
    implicitHeight: tokens.artSize
    radius: tokens.gap
    color: placeholder || raster.ready ? tokens.hover : "transparent"
    onMotionAllowedChanged: if (!motionAllowed) {
        fade.stop();
        raster.opacity = raster.ready ? 1 : 0;
        if (raster.ready)
            previous.release();
    }
    // A new cover fades in over the one it replaces, which stays drawn until
    // the fade ends, so a track change never flashes the placeholder.
    NumberAnimation {
        id: fade
        target: raster
        property: "opacity"
        from: 0
        to: 1
        duration: 180
        easing.type: Easing.OutCubic
        onFinished: previous.release()
    }
    IslandIcon {
        objectName: "artworkPlaceholder"
        anchors.centerIn: parent
        ink: root.tokens.secondary
        visible: root.placeholder && !raster.ready && !previous.shown
    }
    // The cover being replaced: the old image, still loaded, painted until
    // the new one has faded in, or dropped at once when there is no new one.
    Canvas {
        id: previous
        objectName: "artworkPrevious"
        anchors.fill: parent
        property string path: ""
        property var crop: null
        readonly property bool shown: path !== ""
        visible: shown
        onImageLoaded: requestPaint()
        function hold(oldPath, oldCrop) {
            release();
            if (!oldPath || !oldCrop)
                return;
            path = oldPath;
            crop = oldCrop;
            // Each Canvas keeps its own image list; the pixmap is cached,
            // so this load completes at once.
            loadImage(path);
            if (isImageLoaded(path))
                requestPaint();
        }
        function release() {
            if (path) {
                unloadImage(path);
                path = "";
                requestPaint();
            }
        }
        onPaint: {
            var c = getContext("2d");
            c.reset();
            if (!path || !crop || !isImageLoaded(path))
                return;
            root.drawCover(c, path, crop, width, height);
        }
    }
    // The centred square of the image, clipped to the rounded tile.
    function drawCover(c, path, crop, width, height) {
        c.beginPath();
        c.roundedRect(0, 0, width, height, root.radius, root.radius);
        c.clip();
        c.drawImage(path, crop.x, crop.y, crop.edge, crop.edge, 0, 0, width, height);
    }
    // The helper has already sanitized and bounded this raster. The hidden
    // Image supplies dimensions/status; Canvas clips without a GPU-only mask.
    Image {
        id: image
        objectName: "artworkImage"
        source: root.visible ? root.safeSource : ""
        sourceSize.width: 256
        sourceSize.height: 256
        asynchronous: true
        cache: false
        visible: false
        onSourceChanged: {
            fade.stop();
            // Hand the shown cover to `previous` when a new one follows, so
            // it stays up while the new one loads. When the raster had not
            // painted its cover yet (a skip during a load), the cover that
            // `previous` already holds is still the last one displayed and
            // stays. Only clearing the artwork drops it.
            if (source.toString() === "")
                previous.release();
            else if (raster.ready && raster.loadedPath && raster.crop)
                previous.hold(raster.loadedPath, raster.crop);
            if (raster.loadedPath)
                raster.unloadImage(raster.loadedPath);
            raster.crop = null;
            raster.ready = false;
            raster.opacity = 0;
            raster.loadedPath = "";
            raster.requestPaint();
        }
        onStatusChanged: if (status === Image.Error)
            previous.release()
        else if (status === Image.Ready) {
            raster.loadedPath = source.toString();
            raster.loadImage(raster.loadedPath);
            // Canvas emits imageLoaded only for a fetch it starts. When another
            // Artwork (the pill beside the hero) already holds this image in
            // the shared pixmap cache, the load completes at once, silently.
            if (raster.isImageLoaded(raster.loadedPath))
                raster.present();
        }
    }
    Canvas {
        id: raster
        objectName: "artworkRaster"
        anchors.fill: parent
        property bool ready: false
        property string loadedPath: ""
        property var crop: null
        onImageLoaded: present()
        function present() {
            if (ready || !root.visible || !loadedPath || loadedPath !== image.source.toString() || !isImageLoaded(loadedPath))
                return;
            ready = true;
            requestPaint();
            fade.stop();
            if (root.motionAllowed)
                fade.start();
            else {
                opacity = 1;
                previous.release();
            }
        }
        onPaint: {
            var c = getContext("2d");
            c.reset();
            if (!ready || !loadedPath || !isImageLoaded(loadedPath))
                return;
            var w = image.implicitWidth, h = image.implicitHeight;
            if (w <= 0 || h <= 0)
                return;
            var edge = Math.min(w, h);
            crop = { x: (w - edge) / 2, y: (h - edge) / 2, edge: edge };
            root.drawCover(c, loadedPath, crop, width, height);
        }
    }
}

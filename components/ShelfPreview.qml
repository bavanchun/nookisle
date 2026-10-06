pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Shelf.js" as Shelf

// A small preview inside the shelf strip. It reads thumbnails through the
// existing cache/helper route and asks ShelfActions for bounded file metadata.
Item {
    id: root
    property var item: null
    property var coordinator: null
    property var actions: null
    property var ink: null
    readonly property string mime: item && coordinator && coordinator.shelfMimes
        ? coordinator.shelfMimes[item.id] || "" : ""
    readonly property bool imageFile: item && item.kind === "file" && mime.indexOf("image/") === 0
    readonly property bool textItem: item && item.kind === "text"
    readonly property bool linkItem: item && item.kind === "link"
    readonly property bool nonImageFile: item && item.kind === "file" && !imageFile
    readonly property var candidates: imageFile && coordinator && typeof coordinator.shelfThumbnailCandidates === "function"
        ? coordinator.shelfThumbnailCandidates(item.id) : []
    readonly property string host: {
        var match = linkItem ? /^https?:\/\/([^/?#]+)/i.exec(item.url) : null
        return match ? match[1] : ""
    }
    property int attempt: 0
    property string sizeText: "Size unavailable"
    property string sizeJob: ""
    objectName: "shelfPreview"
    Accessible.role: Accessible.Pane
    Accessible.name: item ? "Preview of " + item.name : "Shelf preview"

    function formatSize(bytes) {
        if (!Number.isFinite(bytes) || bytes < 0) return "Size unavailable"
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1024 * 1024) return Math.round(bytes / 1024) + " KB"
        return (bytes / (1024 * 1024)).toFixed(1) + " MB"
    }
    function firstLines(value) {
        return String(value || "").split(/\r?\n/).slice(0, 4).join("\n").slice(0, 300)
    }
    function requestSize() {
        sizeJob = ""
        sizeText = "Size unavailable"
        if (!visible || !nonImageFile || !actions
            || typeof actions.fileSizeCommand !== "function" || typeof actions.execute !== "function") return
        var path = Shelf.localPath(item.uri)
        if (path) sizeJob = actions.execute(actions.fileSizeCommand(path))
    }
    function requestThumbnail() {
        if (visible && imageFile && attempt >= candidates.length && coordinator
            && typeof coordinator.requestShelfThumbnail === "function")
            coordinator.requestShelfThumbnail(item.id)
    }
    onItemChanged: Qt.callLater(requestSize)
    onMimeChanged: {
        Qt.callLater(requestSize)
        Qt.callLater(requestThumbnail)
    }
    onVisibleChanged: {
        if (visible) {
            Qt.callLater(requestSize)
            Qt.callLater(requestThumbnail)
        }
    }
    onCandidatesChanged: {
        attempt = 0
        Qt.callLater(requestThumbnail)
    }
    Connections {
        target: root.actions
        ignoreUnknownSignals: true
        function onFinished(job, status, exitCode, output) {
            if (job !== root.sizeJob || !root.visible) return
            root.sizeJob = ""
            var value = String(output).trim()
            if (status === "ok" && /^\d+$/.test(value))
                root.sizeText = root.formatSize(Number(value))
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: root.ink.raised
        border.width: 1
        border.color: root.ink.selectedStroke
    }
    Row {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10
        Item {
            width: 84
            height: 84
            visible: root.imageFile
            Image {
                id: image
                objectName: "shelfPreviewImage"
                anchors.fill: parent
                sourceSize: Qt.size(168, 168)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                source: root.attempt < root.candidates.length ? Shelf.fileUrl(root.candidates[root.attempt]) : ""
                onStatusChanged: if (status === Image.Error) root.attempt++
            }
            IslandIcon {
                anchors.centerIn: parent
                width: 38
                height: 38
                visible: image.status !== Image.Ready
                name: "file"
                ink: root.ink.inkSecondary
            }
        }
        Column {
            width: parent.width - (root.imageFile ? 94 : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text {
                visible: root.imageFile
                width: parent.width
                text: root.item ? root.item.name : ""
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: root.ink.ink
                font.family: root.ink.fontFamily
                renderType: root.ink.textRenderType
                font.pixelSize: root.ink.bodySize
            }
            Text {
                visible: root.textItem
                objectName: "shelfPreviewText"
                width: parent.width
                text: root.item ? root.firstLines(root.item.text) : ""
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 4
                elide: Text.ElideRight
                color: root.ink.ink
                font.family: root.ink.fontFamily
                renderType: root.ink.textRenderType
                font.pixelSize: root.ink.bodySize
            }
            Text {
                visible: root.linkItem
                objectName: "shelfPreviewHost"
                width: parent.width
                text: root.host
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.ink.ink
                font.family: root.ink.fontFamily
                renderType: root.ink.textRenderType
                font.pixelSize: root.ink.bodySize
            }
            Text {
                visible: root.linkItem
                objectName: "shelfPreviewUrl"
                width: parent.width
                text: root.item ? root.item.url : ""
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: root.ink.inkSecondary
                font.family: root.ink.fontFamily
                renderType: root.ink.textRenderType
                font.pixelSize: root.ink.captionSize
            }
            Text {
                visible: root.nonImageFile
                objectName: "shelfPreviewFileName"
                width: parent.width
                text: root.item ? root.item.name : ""
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: root.ink.ink
                font.family: root.ink.fontFamily
                renderType: root.ink.textRenderType
                font.pixelSize: root.ink.bodySize
            }
            Text {
                visible: root.nonImageFile
                objectName: "shelfPreviewFileType"
                width: parent.width
                text: root.mime || "Unknown type"
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.ink.inkSecondary
                font.family: root.ink.fontFamily
                renderType: root.ink.textRenderType
                font.pixelSize: root.ink.captionSize
            }
            Text {
                visible: root.nonImageFile
                objectName: "shelfPreviewFileSize"
                width: parent.width
                text: root.sizeText
                textFormat: Text.PlainText
                color: root.ink.inkSecondary
                font.family: root.ink.fontFamily
                renderType: root.ink.textRenderType
                font.pixelSize: root.ink.captionSize
            }
        }
    }
}

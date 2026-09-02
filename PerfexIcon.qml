import QtQuick
import QtQuick.Shapes
import qs.Commons

// The Perfex CRM mark, drawn as vector paths so it can be painted in the
// bar's foreground colour like every other bar icon (NetBird and Omarchy's
// own logo widgets do the same). `monochrome: false` restores the brand
// colours for places that can afford them, such as the panel hero.
//
// Geometry traced from the official logo: a D-shaped bowl split by a
// diagonal into teal and magenta, over a dark stem that widens down-right.
// In monochrome the three pieces merge into one P-like mark, by design.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property bool monochrome: true

  readonly property real viewWidth: 31
  readonly property real viewHeight: 45

  width: Math.round(iconSize * viewWidth / viewHeight)
  height: iconSize
  implicitWidth: width
  implicitHeight: height

  Item {
    id: canvas
    width: root.viewWidth
    height: root.viewHeight
    anchors.centerIn: parent
    scale: Math.min(root.width / root.viewWidth, root.height / root.viewHeight)

    Shape {
      width: canvas.width
      height: canvas.height
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer

      Mark {
        brandColor: "#28b8da"
        PathSvg { path: "M0,0 H15.5 A15.5,13.75 0 0 1 15.5,27.5 H0 Z" }
      }
      Mark {
        brandColor: "#b72974"
        PathSvg { path: "M0,0.8 L19,27.5 H0 Z" }
      }
      Mark {
        brandColor: "#444952"
        PathSvg { path: "M0,28 H19.3 L30.5,44.5 H0 Z" }
      }
    }
  }

  component Mark: ShapePath {
    property color brandColor: "#444952"

    fillColor: root.monochrome ? root.color : brandColor
    strokeWidth: 0
    fillRule: ShapePath.WindingFill
  }
}

import QtQuick
import qs.Commons
import qs.Ui

// Weather page of the hub: current conditions as a hero, four days of
// forecast under it, and a click-to-edit location.
//
// The data is not here — `hub.weather` is a WeatherSource that Panel.qml
// keeps alive whether or not this page has ever been opened, because the
// bar icon reads it too. This file only paints what that reports and hands
// edits back to it.
Item {
  id: root

  // ---- Tab contract, injected by Panel.qml.
  property var hub: null
  property QtObject bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property var weather: hub ? hub.weather : null
  readonly property bool keysBlocked: weather ? weather.editingLocation : false

  implicitHeight: weatherColumn.implicitHeight

  // ---- Tab contract: keyboard. Arrows are free here — the page has no
  //      cursor of its own — so Enter opens the location editor, which is
  //      the only thing on the page you can actually change.
  function handleActivate() {
    startEditing()
    return true
  }

  function refresh() {
    if (!weather) return
    weather.locationFile.reload()
    weather.refresh()
  }

  function panelClosed() {
    if (weather && weather.editingLocation) weather.cancelEditingLocation()
  }

  function startEditing() {
    if (!weather) return
    weather.startEditingLocation()
    Qt.callLater(function() {
      locationField.text = root.weather.configuredLocation
      locationField.selectAll()
      locationField.forceActiveFocus()
    })
  }

  function cancelEditing() {
    if (weather) weather.cancelEditingLocation()
  }

  Connections {
    target: root.weather
    // The edit can end inside a fetch callback (a save that landed), so the
    // page has to be told rather than noticing — otherwise focus stays in a
    // field that is no longer on screen.
    function onEditingFinished() {
      if (root.hub && typeof root.hub.focusKeyCatcher === "function") root.hub.focusKeyCatcher()
    }
  }

  Column {
    id: weatherColumn
    width: parent.width
    spacing: Style.space(14)

    // ---- Hero row: big icon + temp on the left; location and stats stacked
    //      on the right.
    Item {
      width: parent.width
      height: Math.max(heroLeft.height, heroRight.height)

      Row {
        id: heroLeft
        anchors.left: parent.left
        anchors.leftMargin: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(16)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: 5
          text: (root.weather ? root.weather.label : "") || "—"
          color: root.foreground
          font.family: root.fontFamily
          // Decorative condition glyph; intentionally larger than the
          // Style.font.* scale's displayLarge (28).
          font.pixelSize: 64
        }

        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            id: tempBig
            text: (root.weather ? root.weather.reportTempNum : "") || "—"
            color: root.foreground
            font.family: root.fontFamily
            // Hero temperature read-out; deliberately oversized, outside the
            // Style.font.* scale.
            font.pixelSize: 56
            font.bold: true
          }

          Text {
            text: root.weather && root.weather.current ? root.weather.tempUnit : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.top: tempBig.top
            anchors.topMargin: Style.space(10)
          }
        }
      }

      Column {
        id: heroRight
        width: weatherStats.implicitWidth
        anchors.right: parent.right
        anchors.rightMargin: Style.space(20)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(12)

        Row {
          visible: root.weather && !root.weather.editingLocation && root.weather.reportLocation !== ""
          spacing: Style.space(6)

          TapHandler {
            onTapped: root.startEditing()
          }
          HoverHandler {
            cursorShape: Qt.PointingHandCursor
          }

          Text {
            text: ""  // nf-fa-map_marker
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: (root.weather ? root.weather.reportLocation : "").toUpperCase()
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.letterSpacing: 1
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Row {
          visible: root.weather && root.weather.editingLocation
          spacing: Style.space(6)

          TextField {
            id: locationField
            width: Style.space(190)
            enabled: root.weather && !root.weather.savingLocation
            placeholderText: "Search city"
            foreground: root.foreground
            font.family: root.fontFamily

            onTextChanged: {
              if (root.weather && root.weather.editingLocation && !root.weather.savingLocation)
                root.weather.queueGeocode(locationField.text)
            }

            Keys.onPressed: function(event) {
              if (!root.weather) return
              if (event.key === Qt.Key_Escape) {
                root.cancelEditing()
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.weather.moveSuggestion(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.weather.moveSuggestion(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.weather.commitLocation(locationField.text)
                event.accepted = true
              }
            }
          }

          // Clear back to IP auto-detect. While a committed location is
          // loading, this same compact affordance becomes a spinner.
          Rectangle {
            width: Style.space(18)
            height: Style.space(18)
            anchors.verticalCenter: parent.verticalCenter
            radius: Math.min(4, Style.cornerRadius)
            color: root.weather && !root.weather.savingLocation && clearLocationArea.containsMouse
              ? Style.hoverFillFor(root.foreground, Color.accent)
              : "transparent"

            Text {
              anchors.centerIn: parent
              text: root.weather && root.weather.savingLocation ? "󰦖" : "✕"
              font.family: root.fontFamily
              color: Qt.darker(root.foreground, 1.4)
              font.pixelSize: Style.font.bodySmall

              RotationAnimator on rotation {
                running: root.weather ? root.weather.savingLocation : false
                from: 0; to: 360
                duration: 800
                loops: Animation.Infinite
              }
            }

            MouseArea {
              id: clearLocationArea
              anchors.fill: parent
              enabled: root.weather && !root.weather.savingLocation
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.weather.clearLocation()
            }
          }
        }

        Row {
          id: weatherStats
          visible: !!(root.weather && root.weather.current)
          spacing: Style.space(36)

          Column {
            spacing: Style.space(5)
            Text {
              text: "FEELS"
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
            }
            Text {
              text: root.weather ? root.weather.reportFeels : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
          }

          Column {
            spacing: Style.space(5)
            Text {
              text: "WIND"
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
            }
            Text {
              text: root.weather ? root.weather.reportWind : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
          }

          Column {
            spacing: Style.space(5)
            Text {
              text: "HUMID"
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
            }
            Text {
              text: root.weather ? root.weather.reportHumidity : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
          }
        }
      }
    }

    // ---- Geocoding suggestions while the location is being edited.
    Column {
      visible: root.weather && root.weather.editingLocation && !root.weather.savingLocation
        && root.weather.locationSuggestions.length > 0
      width: parent.width
      spacing: 0

      Repeater {
        model: root.weather ? root.weather.locationSuggestions : []

        Rectangle {
          required property var modelData
          required property int index
          width: parent.width
          height: suggestionRow.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: root.weather && index === root.weather.suggestionIndex
            ? Style.hoverFillFor(root.foreground, Color.accent)
            : "transparent"

          Row {
            id: suggestionRow
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              text: modelData.name
              color: root.weather && index === root.weather.suggestionIndex
                ? Style.hoverStateColor(root.foreground, Color.accent)
                : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              visible: text !== ""
              text: modelData.description
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: if (root.weather) root.weather.suggestionIndex = index
            onClicked: if (root.weather) root.weather.pickSuggestion(modelData)
          }
        }
      }
    }

    Text {
      visible: !(root.weather && root.weather.current)
      text: "Fetching forecast…"
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.italic: true
    }

    // ---- Divider between current conditions and forecast.
    Rectangle {
      visible: root.weather && root.weather.forecastDays.length > 0
      width: parent.width
      height: Style.spacing.hairline
      color: root.foreground
      opacity: 0.12
    }

    // ---- Forecast row: each cell has the day icon left of a day-name +
    //      hi/lo column. Wrapped in an Item so the block of cells can be
    //      centered within the page.
    Item {
      visible: root.weather && root.weather.forecastDays.length > 0
      width: parent.width
      height: forecastRow.height

      Row {
        id: forecastRow
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(44)

        Repeater {
          model: root.weather ? root.weather.forecastDays : []

          Row {
            required property var modelData
            spacing: Style.space(10)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.weather ? root.weather.dayIcon(modelData) : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: root.weather ? root.weather.dayName(modelData.date).toUpperCase() : ""
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }

              Row {
                spacing: Style.space(6)

                Text {
                  text: root.weather ? root.weather.bareTempForDay(modelData, "max") : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  text: root.weather ? root.weather.bareTempForDay(modelData, "min") : ""
                  color: Qt.darker(root.foreground, 1.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }
      }
    }
  }
}

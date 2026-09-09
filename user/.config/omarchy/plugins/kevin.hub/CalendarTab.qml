import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "ClockModel.js" as ClockModel

// Calendar page of the hub: a month grid with ISO week numbers.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen —
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// Panel.qml owns the popup and the scrolling; this only has to lay itself
// out and report an honest implicitHeight.
Item {
  id: root

  // ---- Tab contract, injected by Panel.qml.
  property var hub: null
  property QtObject bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property bool keysBlocked: root.editingLife

  function setting(name, fallback) {
    return hub && typeof hub.setting === "function" ? hub.setting(name, fallback) : fallback
  }

  function persist(values) {
    if (hub && typeof hub.persistSettings === "function") hub.persistSettings(values)
  }

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: ClockModel.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: ClockModel.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: ClockModel.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: ClockModel.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: ClockModel.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: ClockModel.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: ClockModel.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: ClockModel.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: ClockModel.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  readonly property string nextWeekStartLabel: Qt.locale().dayName(ClockModel.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: ClockModel.weekdayOrder(weekStart)
  readonly property var weeks: ClockModel.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  implicitHeight: calendarColumn.implicitHeight
  implicitWidth: gridColumn.width

  // ---- Tab contract: keyboard.
  function handleMove(dx, dy) {
    if (dx !== 0) moveMonth(dx)
    if (dy !== 0) moveYear(dy)
    return true
  }

  function handleActivate() {
    goToToday()
    return true
  }

  function handleTextKey(t) {
    if (t === "[") moveMonth(-1)
    else if (t === "]") moveMonth(1)
    else if (t === "{") moveYear(-1)
    else if (t === "}") moveYear(1)
    else if (t === "t" || t === "T") goToToday()
    else if (t === "w" || t === "W") toggleWeekStart()
    else return false
    return true
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  function panelClosed() {
    if (root.editingLife) root.cancelEditingLife()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = ClockModel.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  function setWeekStart(day) {
    var next = ClockModel.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persist({ weekStartDay: ClockModel.weekStartSettingName(next) })
  }

  function toggleWeekStart() {
    setWeekStart(ClockModel.toggledWeekStart(root.weekStart))
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    if (hub && typeof hub.focusKeyCatcher === "function") hub.focusKeyCatcher()
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persist({ birthYear: 0 })
  }

  function commitLife() {
    var born = ClockModel.parseBirthYear(bornField.text, today.getFullYear())
    var span = ClockModel.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persist({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  // Locale short day names, trimmed of the trailing period some locales
  // carry ("man." -> "MAN") so the header row stays a clean band of caps.
  function weekdayLabel(weekday) {
    return String(Qt.locale().dayName(weekday, Locale.ShortFormat)).replace(/\.$/, "").toUpperCase()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (ClockModel.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  Column {
    id: calendarColumn
    width: parent.width
    spacing: Style.space(8)

    // ---- Hero: today, centered. Once the view has stepped back it is also
    //      the way home — clicking the date you are looking for beats
    //      hunting for a reset button.
    Item {
      width: parent.width
      height: heroRow.height

      Row {
        id: heroRow
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(22)

        Text {
          // Baseline-aligned, not center-aligned: "July 26" carries a
          // descender, so centering the two boxes leaves the icon sitting
          // visibly low against the digits.
          anchors.baseline: heroDate.baseline
          text: "󰃭"
          color: heroMouse.containsMouse
            ? Style.hoverStateColor(root.foreground, Color.accent)
            : root.foreground
          font.family: root.fontFamily
          // Decorative, and deliberately outside the Style.font.* scale.
          // Sized so the glyph reads at the cap height of the date beside it
          // rather than towering over it.
          font.pixelSize: 48
        }

        Text {
          id: heroDate
          anchors.verticalCenter: parent.verticalCenter
          text: Qt.formatDate(root.today, "MMMM d")
          color: heroMouse.containsMouse
            ? Style.hoverStateColor(root.foreground, Color.accent)
            : root.foreground
          font.family: root.fontFamily
          font.pixelSize: 52
          font.bold: true
        }
      }

      MouseArea {
        id: heroMouse
        x: heroRow.x
        y: heroRow.y
        width: heroRow.width
        height: heroRow.height
        enabled: !root.viewingCurrentMonth
        hoverEnabled: enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.goToToday()

        PanelToolTip {
          visible: heroMouse.containsMouse
          text: "Back to today"
          fontFamily: root.fontFamily
        }
      }
    }

    // ---- Year progress, doubling as the rule under the hero: a plain
    //      hairline said nothing, and whole days done over days in the year
    //      says the same thing louder.
    Item {
      width: parent.width
      height: yearBlock.y + yearBlock.height

      Item {
        id: yearBlock
        y: Style.space(6)
        anchors.horizontalCenter: parent.horizontalCenter
        width: gridColumn.width
        height: Math.max(yearLabel.implicitHeight, Style.space(10))

        TapHandler {
          enabled: !root.editingLife
          onDoubleTapped: root.startEditingLife()
        }

        Row {
          visible: root.editingLife
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "BORN"
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }

          TextField {
            id: bornField
            width: Style.space(70)
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "year"
            foreground: root.foreground
            font.family: root.fontFamily
            inputMethodHints: Qt.ImhDigitsOnly

            Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.space(6)
            text: "LIVE TO"
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }

          TextField {
            id: expectancyField
            width: Style.space(60)
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "90"
            foreground: root.foreground
            font.family: root.fontFamily
            inputMethodHints: Qt.ImhDigitsOnly

            Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
          }
        }

        Text {
          id: yearLabel
          visible: !root.editingLife
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.today.getFullYear()
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }

        Text {
          id: yearPercent
          visible: !root.editingLife
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.yearDonePercent + "%"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Rectangle {
          id: yearTrack
          visible: !root.editingLife
          anchors.left: yearLabel.right
          anchors.right: yearPercent.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(6)
          radius: Style.cornerRadius > 0 ? height / 2 : 0
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

          Rectangle {
            width: Math.round(parent.width * root.yearDone)
            height: parent.height
            radius: parent.radius
            color: Style.selectedStateColor(root.foreground, Color.accent)

            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          }
        }
      }
    }

    // ---- Memento mori. Only here once someone has gone looking and given
    //      an age; the same rail as the year above it, measured against a
    //      nominal lifetime.
    Item {
      visible: root.birthYear > 0
      width: parent.width
      height: visible ? lifeBlock.height : 0

      Item {
        id: lifeBlock
        anchors.horizontalCenter: parent.horizontalCenter
        width: gridColumn.width
        height: Math.max(lifeLabel.implicitHeight, Style.space(10))

        Text {
          id: lifeLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "LIFE"
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }

        Text {
          id: lifePercent
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.lifeDonePercent + "%"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Rectangle {
          anchors.left: lifeLabel.right
          anchors.right: lifePercent.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(6)
          radius: Style.cornerRadius > 0 ? height / 2 : 0
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

          Rectangle {
            width: Math.round(parent.width * root.lifeDone)
            height: parent.height
            radius: parent.radius
            color: Style.selectedStateColor(root.foreground, Color.accent)

            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          }
        }

        TapHandler {
          onDoubleTapped: root.clearLife()
        }

        MouseArea {
          id: lifeMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton

          PanelToolTip {
            visible: lifeMouse.containsMouse
            text: "Memento Mori"
            fontFamily: root.fontFamily
          }
        }
      }
    }

    // ---- Month grid: week numbers down a gutter on the left, then the
    //      seven day columns. Always six rows, so the page is exactly as
    //      tall in February as it is in August.
    Item {
      width: parent.width
      height: gridColumn.y + gridColumn.height

      WheelHandler {
        onWheel: function(event) {
          // Horizontal wheels and touchpad side-scrolls report y === 0;
          // without this they would every one read as "next month".
          if (event.angleDelta.y === 0) return
          root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
        }
      }

      Column {
        id: gridColumn
        // The meter above is a solid rule; the grid needs room to read as
        // its own block rather than hanging off it.
        y: Style.space(18)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(3)

        Row {
          id: headerRow
          spacing: root.cellSpacing

          // The week-number heading doubles as the week-start toggle. It is
          // the one control in the page whose meaning is not self-evident,
          // so it carries a tooltip naming the day the click will switch to.
          Rectangle {
            width: root.weekColumnWidth
            height: Style.space(16)
            radius: Style.cornerRadius
            color: weekStartMouse.containsMouse
              ? Style.hoverFillFor(root.foreground, Color.accent)
              : "transparent"

            Text {
              anchors.centerIn: parent
              text: "W"
              color: weekStartMouse.containsMouse
                ? Style.hoverStateColor(root.foreground, Color.accent)
                : Qt.darker(root.foreground, 1.9)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }

            MouseArea {
              id: weekStartMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleWeekStart()
            }

            PanelToolTip {
              visible: weekStartMouse.containsMouse
              text: "Start weeks on " + root.nextWeekStartLabel
              fontFamily: root.fontFamily
            }
          }

          Item {
            width: root.gutterWidth
            height: Style.space(16)
          }

          Repeater {
            model: root.weekdays

            Text {
              required property var modelData
              width: root.cellWidth
              height: Style.space(16)
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: root.weekdayLabel(modelData)
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }
          }
        }

        Repeater {
          model: root.weeks

          Row {
            required property var modelData
            spacing: root.cellSpacing

            Text {
              width: root.weekColumnWidth
              height: root.cellHeight
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: modelData.week
              color: Qt.darker(root.foreground, 1.9)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Item {
              width: root.gutterWidth
              height: root.cellHeight
            }

            Repeater {
              model: modelData.days

              Rectangle {
                required property var modelData

                width: root.cellWidth
                height: root.cellHeight
                radius: Style.cornerRadius
                // Today is outlined, not filled: a lit-up block shouts over
                // a grid this quiet.
                color: "transparent"
                border.width: modelData.today ? Style.spacing.hairline : 0
                border.color: Style.normalBorderFor(root.foreground, Color.accent)

                Text {
                  anchors.centerIn: parent
                  text: modelData.day
                  color: modelData.inMonth
                    ? (modelData.weekend ? Qt.darker(root.foreground, 1.45) : root.foreground)
                    : Qt.darker(root.foreground, 2.2)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: modelData.today
                }
              }
            }
          }
        }
      }

      // Hairline down the week-number gutter, drawn only beside the day rows
      // so it does not cut through the header band.
      Rectangle {
        x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
        y: gridColumn.y + headerRow.height + gridColumn.spacing
        width: Style.spacing.hairline
        height: gridColumn.height - headerRow.height - gridColumn.spacing
        color: root.foreground
        opacity: 0.1
      }
    }

    // ---- Month stepping, spanning the grid it drives. The chevrons sit on
    //      the grid's outer bounds, the same edges the year rail above uses,
    //      so the row reads as the page's other full-width rail instead of a
    //      cluster floating in space. The label is centered and fixed-width,
    //      so it holds still from "MAY" to "SEPTEMBER".
    Item {
      width: parent.width
      height: monthNav.height

      Item {
        id: monthNav
        anchors.horizontalCenter: parent.horizontalCenter
        width: gridColumn.width
        height: monthLabel.implicitHeight + Style.space(10)

        Text {
          id: monthLabel
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          // Fixed width so the chevrons hold still between a "MAY 2026" and
          // a "SEPTEMBER 2026".
          width: Style.space(130)
          horizontalAlignment: Text.AlignHCenter
          text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.letterSpacing: 1
        }

        PanelActionButton {
          // Pulled out by the button's own padding so the glyph, not its hit
          // box, lines up with the "2026" on the year rail.
          anchors.left: parent.left
          anchors.leftMargin: -Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰅁"
          tooltipText: "Previous month"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.moveMonth(-1)
        }

        PanelActionButton {
          anchors.right: parent.right
          anchors.rightMargin: -Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰅂"
          tooltipText: "Next month"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.moveMonth(1)
        }
      }
    }
  }
}

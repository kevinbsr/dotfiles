import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui

Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  // A locked session blanks the displays after a few seconds. Nothing is
  // visible from then until the user wakes it, so a video must not keep
  // decoding through what is usually the longest part of a lock.
  property bool displaysBlank: false
  property bool powerSaverActive: false
  property string passwordText: ""
  property bool syncingPasswordText: false

  readonly property string placeholderText: "Enter Password"
  // Geometry from the hyprlock setup used on Omarchy 3, recovered from the
  // dotfiles git history (commit 4060f57^, user/.config/hypr/hyprlock.conf):
  // input-field size = 320, 65 / rounding = 10 / outline_thickness = 2.
  readonly property int fieldWidth: 320
  readonly property int fieldHeight: 65
  readonly property int outlineThickness: 2
  readonly property int fieldRadius: 10

  // Avatar and username, mirroring the `image` block (path = ~/.user_image,
  // size 64, rounding 100, border_size 2) and `label` block of that file.
  readonly property string userImagePath: Quickshell.env("HOME") + "/.user_image"
  readonly property string userName: Quickshell.env("USER") || ""
  property var now: new Date()
  readonly property int fieldFontSize: Math.round(Style.font.heading * 1.125)
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 1.33)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.19)
  // Space to keep clear on each side of the field for the fingerprint icon
  // (icon width plus a gap) so the centered dots never run under it.
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible — otherwise long passwords clip with no feedback.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0
  readonly property var inputBorderSpec: errorState
    ? Border.surfaceSpec("lock", "border-error", Color.lock.borderError, root.outlineThickness, "border-alpha")
    : Border.surfaceSpec("lock", "border", Color.lock.border, root.outlineThickness, "border-alpha")

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  // Measures the masked password at full size; passwordDotScale compares this
  // against the field width to decide how far the dots must shrink to fit.
  TextMetrics {
    id: dotMetrics
    font.family: Style.font.family
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background

    BackgroundMedia {
      id: wallpaper
      anchors.fill: parent
      path: root.loadBackground ? root.backgroundPath : ""
      version: root.backgroundVersion
      playbackEnabled: root.loadBackground && !root.displaysBlank && !root.powerSaverActive
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper.video ? null : wallpaper
      visible: !wallpaper.video
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.ready
      blur: 1.0
      blurMax: 128
      blurMultiplier: 1.25
      contrast: -0.08
    }

    // Qt's video output cannot be sampled by MultiEffect on every renderer.
    // Keep video wallpapers visible and darken them slightly for legibility.
    Rectangle {
      anchors.fill: wallpaper
      visible: wallpaper.video
      color: "#22000000"
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    // A single timer, stopped while the displays are blanked: a clock that
    // keeps ticking behind dark screens is work thrown away during the longest
    // part of a lock.
    Timer {
      interval: 1000
      running: !root.displaysBlank && !root.powerSaverActive
      repeat: true
      triggeredOnStart: true
      onTriggered: root.now = new Date()
    }

    // Small date above the large time, in the order the DATE and TIME labels
    // appeared in hyprlock (CaskaydiaMono 18 and 95).
    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.space(90)
      spacing: Style.space(4)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: Qt.formatDateTime(root.now, "ddd dd MMM")
        color: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Style.space(18)
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        // `date +%-I:%M` -- 12-hour, no leading zero.
        text: {
          var h = root.now.getHours() % 12
          if (h === 0) h = 12
          var m = root.now.getMinutes()
          return h + ":" + (m < 10 ? "0" + m : m)
        }
        color: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Style.space(95)
        horizontalAlignment: Text.AlignHCenter
      }
    }

    // Avatar and username anchored to the bottom as in hyprlock (image at
    // valign end / position 0,160; label just below it at 0,120).
    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(110)
      spacing: Style.space(10)
      visible: avatar.status === Image.Ready

      Item {
        id: avatarFrame
        width: Style.space(64)
        height: Style.space(64)
        anchors.horizontalCenter: parent.horizontalCenter

        // Circular mask: the same arrangement the image-picker uses -- an Item
        // whose layer.effect is a MultiEffect masked by an invisible shape.
        Rectangle {
          id: avatarMask
          anchors.fill: parent
          radius: width / 2
          color: "white"
          visible: false
          layer.enabled: true
        }

        Item {
          anchors.fill: parent
          layer.enabled: true
          layer.smooth: true
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: avatarMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.1
          }

          Image {
            id: avatar
            anchors.fill: parent
            source: Util.fileUrl(root.userImagePath)
            fillMode: Image.PreserveAspectCrop
            // The file is 2883x2884 and 8 MB. Decoding at physical size keeps
            // the full bitmap out of the lock's memory, which stays loaded for
            // the whole session (keepLoaded).
            sourceSize.width: avatarFrame.width * Screen.devicePixelRatio
            sourceSize.height: avatarFrame.height * Screen.devicePixelRatio
            asynchronous: true
            cache: true
          }
        }

        // A 2px ring on top, matching hyprlock's border_size/border_color.
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: "transparent"
          border.width: Style.space(2)
          border.color: Color.lock.border
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: root.userName
        color: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: Style.space(14)
        horizontalAlignment: Text.AlignHCenter
      }
    }

    BorderSurface {
      id: inputField
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.centerIn: parent
      color: Color.lock.background
      borderSpec: root.inputBorderSpec
      radius: root.fieldRadius
      clip: true

      TextInput {
        id: passwordInput
        anchors.fill: parent
        anchors.topMargin: inputField.borderTop
        // Reserve the fingerprint icon's width on both sides so the centered
        // dots stay symmetric and never slide under the icon as they grow.
        anchors.rightMargin: inputField.borderRight + 18 + root.fingerprintReserve
        anchors.bottomMargin: inputField.borderBottom
        anchors.leftMargin: inputField.borderLeft + 18 + root.fingerprintReserve
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        activeFocusOnPress: true
        clip: true
        enabled: root.inputEnabled && !root.authenticatingPassword
        readOnly: root.authenticatingPassword
        echoMode: TextInput.Password
        passwordCharacter: "\u25CF"
        passwordMaskDelay: 0
        color: Color.lock.text
        selectionColor: Color.lock.selection
        selectedTextColor: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
        font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
        cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
        cursorDelegate: Rectangle {
          width: 2
          color: Color.lock.text
          visible: passwordInput.cursorVisible
        }

        onTextChanged: {
          if (!root.syncingPasswordText) root.passwordTextEdited(text)
          if (text.length > 0) {
            root.wakeRequested()
          }
          if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
        }

        onAccepted: {
          var submitted = root.passwordText
          root.passwordTextEdited("")
          if (submitted.length > 0) root.submitPassword(submitted)
        }

        // Keypad input when Num Lock arrives switched off at the lock screen.
        // The session-lock surface starts without inheriting the LOCKED Num
        // Lock modifier, so keypad keys land as navigation (7 becomes Home, 8
        // becomes Up, and so on) and the password simply never goes in.
        //
        // Qt sets KeypadModifier on everything that came from the keypad, and
        // on nothing else. That is why the mapping below does NOT affect the
        // real Home, End and arrow keys: those arrive without the modifier and
        // keep working inside the field.
        //
        // The text.length guard is the second half: when Num Lock does work,
        // the keypad delivers "7" as text and this branch never runs.
        Keys.onPressed: function(event) {
          root.wakeRequested()
          if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
            root.passwordTextEdited("")
            event.accepted = true
            return
          }

          if ((event.modifiers & Qt.KeypadModifier) && event.text.length === 0) {
            var digit = ({
              [Qt.Key_Insert]: "0",
              [Qt.Key_End]: "1",
              [Qt.Key_Down]: "2",
              [Qt.Key_PageDown]: "3",
              [Qt.Key_Left]: "4",
              [Qt.Key_Clear]: "5",
              [Qt.Key_Right]: "6",
              [Qt.Key_Home]: "7",
              [Qt.Key_Up]: "8",
              [Qt.Key_PageUp]: "9",
              [Qt.Key_Delete]: "."
            })[event.key]
            if (digit !== undefined) {
              // Write into the field rather than emitting the signal, so the
              // character takes exactly the same path a normal keystroke does
              // (onTextChanged -> passwordTextEdited) instead of depending on
              // the Service handing the value back.
              passwordInput.insert(passwordInput.cursorPosition, digit)
              event.accepted = true
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.fill: passwordInput
        text: root.authenticatingPassword ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
        visible: passwordInput.text.length === 0
        color: root.authenticatingPassword ? Color.lock.text : (root.failureMessage.length > 0 ? Color.lock.textError : Color.lock.placeholder)
        font.family: Style.font.family
        font.pixelSize: root.fieldFontSize
        font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }

      // Fingerprint hint pinned inside the field's right edge when a sensor is
      // enrolled, so the user knows they can touch to unlock instead of typing.
      // Matches hyprlock, which draws its fingerprint icon in the same spot.
      Text {
        id: fingerprintIcon
        objectName: "fingerprintIndicator"
        anchors.right: parent.right
        anchors.rightMargin: inputField.borderRight + 18
        anchors.verticalCenter: parent.verticalCenter
        visible: root.fingerprintConfigured
        text: "󰈷"
        color: Color.lock.placeholder
        font.family: Style.font.family
        font.pixelSize: Math.round(root.fieldFontSize * 1.1)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }
}

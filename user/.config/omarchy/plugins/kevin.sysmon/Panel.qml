import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Monitor de sistema: CPU, memória, GPU e discos.
//
// Substitui o módulo custom/cpu-info da waybar antiga. Duas diferenças
// deliberadas em relação a ele:
//
//   - Rede ficou de fora: o painel de Network do Omarchy já cobre isso.
//   - A dGPU NVIDIA é lida pelos contadores de runtime PM do kernel, nunca por
//     nvidia-smi. O script antigo chamava nvidia-smi a cada 1s, e cada chamada
//     acorda o chip para P0/1702MHz -- ou seja, o próprio monitor era o que
//     mantinha a GPU acordada. Aqui a linha "dGPU" mostra justamente se ela
//     está em D3cold, sem perturbá-la.
//
// A sondagem só roda com o painel aberto: o ícone da barra é estático, então
// não há nada para atualizar enquanto ele estiver fechado.
Panel {
  id: root
  moduleName: "kevin.sysmon"
  ipcTarget: "kevin.sysmon"

  // O Bar dimensiona cada widget pelo implicitWidth/Height da raiz. Sem estes
  // dois o slot fica com 0px: o QML carrega, o IPC responde, e mesmo assim não
  // aparece ícone nenhum na barra.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property var stats: ({})
  property bool loaded: false

  readonly property var cpu: stats.cpu || ({})
  readonly property var ram: stats.ram || ({})
  readonly property var swap: stats.swap || ({})
  readonly property var igpu: stats.igpu || ({})
  readonly property var dgpu: stats.dgpu || ({})
  readonly property var disks: stats.disks || []

  readonly property int cpuPercent: Math.max(0, Math.min(100, cpu.percent || 0))
  readonly property color foreground: bar ? bar.foreground : Color.foreground

  // Verde/amarelo/vermelho seriam cores fora do tema. Em vez disso a barra
  // carregada puxa para "urgent", que todo tema do Omarchy define.
  function meterColor(fraction) {
    if (fraction >= 0.9) return bar ? bar.urgent : Color.urgent
    return foreground
  }

  function applyJson(text) {
    var raw = String(text || "").trim()
    if (raw === "") return
    try {
      root.stats = JSON.parse(raw)
      root.loaded = true
    } catch (e) {
      // Uma leitura malformada não deve derrubar o painel; a próxima sondagem
      // (2s) corrige.
    }
  }

  function probe() {
    if (!probeProcess.running) probeProcess.running = true
  }

  function formatKb(kb) {
    var value = Number(kb) || 0
    if (value >= 1048576) return (value / 1048576).toFixed(1) + " Gi"
    return Math.round(value / 1024) + " Mi"
  }

  function formatBytes(bytes) {
    var value = Number(bytes) || 0
    if (value >= 1099511627776) return (value / 1099511627776).toFixed(1) + " T"
    if (value >= 1073741824) return Math.round(value / 1073741824) + " G"
    return Math.round(value / 1048576) + " M"
  }

  // "suspended" é o estado que interessa: dGPU realmente em D3cold.
  readonly property string dgpuLabel: {
    if (!dgpu.present) return "Absent"
    var suffix = dgpu.powerState ? " (" + dgpu.powerState + ")" : ""
    if (dgpu.status === "suspended") return "Asleep" + suffix
    if (dgpu.status === "active") return "Active" + suffix
    return String(dgpu.status || "unknown")
  }

  readonly property string heroStatus: {
    if (!loaded) return "reading…"
    var parts = []
    if (cpu.temp) parts.push(cpu.temp + "°C")
    if (cpu.cores) parts.push(cpu.cores + " threads")
    return parts.join(" · ")
  }

  Process {
    id: probeProcess
    command: ["omarchy-sysmon-probe"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyJson(text)
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.opened
    onTriggered: root.probe()
  }

  onOpenedChanged: if (opened) probe()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍛"
    slotSize: Style.bar.iconSlot
    tooltipText: "System monitor"
    onPressed: function(b) {
      if (b === Qt.RightButton) Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: CPU ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroValue.implicitHeight)

          Text {
            id: heroIcon
            text: "󰍛"
            color: root.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroValue.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Processor"
              color: root.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: root.heroStatus.toUpperCase()
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroValue
            text: root.loaded ? root.cpuPercent + "%" : "—"
            color: root.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Meter { fraction: root.cpuPercent / 100 }

        // ---------- Memória ----------
        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "MEMORY"
            foreground: root.foreground
            fontFamily: root.bar.fontFamily
          }

          InfoPair {
            label: "RAM"
            value: root.loaded ? root.formatKb(root.ram.usedKb) + " / " + root.formatKb(root.ram.totalKb) + "  (" + (root.ram.percent || 0) + "%)" : "—"
          }
          Meter { fraction: (root.ram.percent || 0) / 100 }

          InfoPair {
            visible: (root.swap.totalKb || 0) > 0
            label: "Swap"
            value: root.loaded ? root.formatKb(root.swap.usedKb) + " / " + root.formatKb(root.swap.totalKb) + "  (" + (root.swap.percent || 0) + "%)" : "—"
          }
          Meter {
            visible: (root.swap.totalKb || 0) > 0
            fraction: (root.swap.percent || 0) / 100
          }
        }

        // ---------- GPU ----------
        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "GRAPHICS"
            foreground: root.foreground
            fontFamily: root.bar.fontFamily
          }

          InfoPair {
            visible: root.igpu.present === true
            label: "iGPU (AMD)"
            value: root.loaded ? (root.igpu.busy || 0) + "%  ·  " + (root.igpu.temp || 0) + "°C  ·  " + (root.igpu.watts || 0) + " W" : "—"
          }
          Meter {
            visible: root.igpu.present === true
            fraction: (root.igpu.busy || 0) / 100
          }

          InfoPair {
            visible: root.igpu.present === true
            label: "VRAM"
            value: root.loaded ? (root.igpu.vramUsedMi || 0) + " / " + (root.igpu.vramTotalMi || 0) + " Mi  ·  " + (root.igpu.mhz || 0) + " MHz" : "—"
          }

          // A dGPU só ganha as mesmas linhas da iGPU quando já está acordada.
          // Dormindo ela está sem energia: não há uso nem temperatura para ler,
          // e a consulta (NVML) seria justamente o que a acordaria.
          InfoPair {
            visible: root.dgpu.present === true
            label: "dGPU (NVIDIA)"
            value: {
              if (!root.loaded) return "—"
              if (root.dgpu.detailed === true)
                return (root.dgpu.busy || 0) + "%  ·  " + (root.dgpu.temp || 0) + "°C  ·  " + (root.dgpu.watts || 0) + " W"
              return root.dgpuLabel + "  ·  " + (root.dgpu.activePercent || 0) + "% awake"
            }
          }
          Meter {
            visible: root.dgpu.detailed === true
            fraction: (root.dgpu.busy || 0) / 100
          }

          InfoPair {
            visible: root.dgpu.detailed === true
            label: "dGPU VRAM"
            value: root.loaded ? (root.dgpu.vramUsedMi || 0) + " / " + (root.dgpu.vramTotalMi || 0) + " Mi  ·  " + (root.dgpu.mhz || 0) + " MHz" : "—"
          }
        }

        // ---------- Discos ----------
        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "STORAGE"
            foreground: root.foreground
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.disks

            Column {
              required property var modelData
              width: column.width
              spacing: Style.spacing.labelGap

              InfoPair {
                label: modelData.label + " (" + modelData.mount + ")"
                value: root.formatBytes(modelData.used) + " / " + root.formatBytes(modelData.total) + "  (" + modelData.percent + "%)"
              }
              Meter { fraction: (modelData.percent || 0) / 100 }
            }
          }
        }

        // ---------- Ação ----------
        Button {
          width: parent.width
          iconText: "󰅶"
          iconSize: Style.font.title
          text: "Open btop"
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          onClicked: {
            Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])
            root.close()
          }
        }
      }
    }
  }

  component Meter: Item {
    property real fraction: 0

    width: column.width
    implicitHeight: Style.space(6)

    Rectangle {
      id: track
      anchors.fill: parent
      radius: height / 2
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    }

    Rectangle {
      anchors.left: track.left
      anchors.verticalCenter: track.verticalCenter
      height: track.height
      radius: track.radius
      color: root.meterColor(parent.fraction)
      width: Math.max(track.height, track.width * Math.max(0, Math.min(1, parent.fraction)))

      Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: 220 } }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: column.width
    spacing: Style.space(8)

    Text {
      text: parent.label
      color: root.foreground
      opacity: 0.6
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }

    Text {
      text: parent.value
      color: root.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}

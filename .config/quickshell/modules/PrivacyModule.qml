import QtQuick
import qs.config
import qs.components
import qs.services

// Red indicators while the mic is recorded, the camera is used or the screen is shared.
Row {
    height: Theme.barHeight

    component Indicator: BarModule {
        textColor: Colors.critical
        SequentialAnimation on opacity {
            running: shown
            loops: Animation.Infinite
            NumberAnimation { to: 0.45; duration: 1000; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 1000; easing.type: Easing.InOutSine }
        }
    }

    Indicator {
        icon: "\uf130"     // microphone
        shown: Privacy.mic
        tooltip: "Microphone in use by:\n" + Privacy.micApps.join("\n")
    }
    Indicator {
        icon: "\uf030"     // camera
        shown: Privacy.camera
        tooltip: "Camera in use"
    }
    Indicator {
        icon: "\uf108"     // desktop
        shown: Privacy.screen
        tooltip: "Screen is being shared"
    }
}

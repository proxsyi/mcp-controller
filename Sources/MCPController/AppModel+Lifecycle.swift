import Foundation

extension AppModel {
    func shutdownForApplicationQuit() {
        flushPersistNow()
        stopImmediatelyForApplicationQuit()
        stopTailscaleFunnel()
    }
}

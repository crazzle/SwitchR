//
//  WindowFinder.swift
//  SwitchR
//
//  Created by Mark Keinhörster on 21.02.21.
//

import AppKit
import Foundation
import RxSwift
import RxRelay

typealias UIWindow = (id: CGWindowID, axapp: AXUIElement, axwindow: AXUIElement, name: String, title: String)
typealias UIWindowNeighbours = (previous: UIWindow, next: UIWindow)
typealias SelectedUIWindow = (Int, ControlAction, UIWindow?)
typealias UIWindowList = (Int, ControlAction, Array<UIWindow>)

let UNDEFINED_WINDOW_ID : Int = 0

class WindowFinder {
    let disposableBag: DisposeBag = DisposeBag()
    let stream: Observable<ControlAction>
    let confirmationStream: Observable<ControlAction>
    let pickStream: Observable<UIWindow?>
    let imageStream: Observable<(NSImage?, String, String)>
    
    init(stream: Observable<ControlAction>) {
        self.stream = stream.map({checkAccessibilityTrusted(action: $0)})
        self.pickStream = self.stream.filter({$0 != .confirm})
            .map({(UNDEFINED_WINDOW_ID, $0, getRelevantWindows())})
            .scan((UNDEFINED_WINDOW_ID, ControlAction.next, Optional.none)){select(acc: $0, value: $1)}.map { $0.2 }
        self.confirmationStream = self.stream.filter({$0 == .confirm})
        self.imageStream = self.pickStream.map{ (captureImage(window: $0), $0!.name, $0!.title) }
        self.confirmationStream.withLatestFrom(self.pickStream)
            .subscribe(onNext: { setFocus(window: $0 )})
            .disposed(by: disposableBag)
        
    }
}

/**
 Retrieve the relevant windows based on the currently running applications
 */
func getRelevantWindows() -> [UIWindow] {
    let apps = NSWorkspace.shared.runningApplications.filter{$0.activationPolicy == .regular}
    let windows: Array<UIWindow> = apps.map(getActiveWindowsForApp)
        .reduce([], +)
        .filter(windowIsNotMinimized)
        .filter(windowIsEnabled)
        .sorted(by: {$0.id > $1.id})
    return windows
}

/**
 Retrieve all active windows of a running application
 */
func getActiveWindowsForApp(app: NSRunningApplication) -> [UIWindow]{
    let pid = app.processIdentifier
    let name = app.localizedName
    let app = AXUIElementCreateApplication(pid)
   
    /**
     Retrieve all  windows for an NSRunningApplication
     */
    guard let windowsList = getAXAttribute(container: app, attribute: kAXWindowsAttribute, to: Array<AXUIElement>()) else {
        return Array<UIWindow>()
    }
    
    /**
     Map  AXUIElemenst to a UIWindows
     */
    return windowsList.map{
        let id = IDFinder.getWindowID($0)
        guard let title = getAXAttribute(container: $0, attribute: kAXTitleAttribute, to: String()) else {
            return (id, app, $0, name!, "")
        }
        return (id, app, $0, name!, title)
    }
}

/**
 Check if a AXUIWindow is not minimized
 */
func windowIsNotMinimized(window: UIWindow) -> Bool{
    guard let minimized = getAXAttribute(container: window.axwindow,
                                         attribute: kAXMinimizedAttribute,
                                         to: Bool()) else {
        return false
    }
    return !minimized
}

/**
 Check if a AXUIWindow is enabled and a user can interact with it.
 E.g. this is needed for the Finder Application which runs almost all the
 time containing a disabled window
 */
func windowIsEnabled(window: UIWindow) -> Bool{
    guard let enabled = getAXAttribute(container: window.axwindow,
                                       attribute: kAXEnabledAttribute,
                                       to: Bool()) else {
        return true
    }
    return enabled
}

/**
 Selects a new window by looking at the index of the current selection and action
 */
func select(acc: SelectedUIWindow, value: UIWindowList) -> SelectedUIWindow{
    let (lastIndex, _, _) = acc
    let (_, newAction, currentWindows) = value
    let nextIndex : Int = {
        switch newAction{
        // Return the index of the next window or the first one
        case .next: return lastIndex < currentWindows.count - 1 ? lastIndex + 1 : 0
        // Return the index of the previous window or the last oneπ
        case .previous: return lastIndex > 0 ? lastIndex - 1 : currentWindows.count - 1
        default: return lastIndex
        }
    }()
    return currentWindows.isEmpty ? (nextIndex, newAction, .none) : (nextIndex, newAction, currentWindows[nextIndex])
}

/**
 Focusing not only an app, but a specified window of an app. All three attributes have to be set:
 - kAXFrontmostAttribute to set the app as active and selected
 - kAXMainAttribute make the window the main window of the app
 - kAXFocusedAttribute to set the keyboard focus for the main window
 */
func setFocus(window: UIWindow?){
    if let win = window {
        AXUIElementSetAttributeValue(win.axapp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(win.axwindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(win.axwindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
}

/**
 Capturing a screenshot from a window using it's CGWindowID
 */
func captureImage(window: UIWindow?) -> NSImage?{
    guard let window = window else {
        return .none
    }
    guard let windowImage: CGImage =
            CGWindowListCreateImage(.null, .optionIncludingWindow, window.id,
                                    [.boundsIgnoreFraming, .nominalResolution]) else {
        return .none
    }
    return NSImage(cgImage:windowImage, size:NSZeroSize)
}

/**
 Checks if the needed accessibilty access  is granted.
 Needed access rights:
 - check if SwitchR is a trusted accessibilty client to get information about running apps
 - check if SwitchR is allowed to take screen captures for app thumbnails
 */
func checkAccessibilityTrusted(action: ControlAction) -> ControlAction{
    switch (gotAXIAccess() && gotCaptureAccess()) {
    case true:
        return action
    default:
        return .abort
    }
}

func gotAXIAccess() -> Bool{
    return AXIsProcessTrusted()
}

func gotCaptureAccess() -> Bool{
    return CGPreflightScreenCaptureAccess()
}

/**
 Helper function to retrieve an attribute from an AXUIElement which is either an app or a window.
 */
func getAXAttribute<T>(container: AXUIElement, attribute: String, to type: T) -> T?{
    var ax: CFTypeRef?
    AXUIElementCopyAttributeValue(container, attribute as CFString, &ax)
    guard let axResult = ax else { return .none }
    return axResult as? T
}

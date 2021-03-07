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

typealias UIWindow = (id: CGWindowID, axapp: AXUIElement, axwindow: AXUIElement, name: String)
typealias UIWindowNeighbours = (previous: UIWindow, next: UIWindow)
typealias UIWindowSelection = (Int, ControlAction, UIWindow?)
typealias UIWindowSelectable = (Int, ControlAction, Array<UIWindow>)

class WindowFinder {
    let disposableBag: DisposeBag = DisposeBag()
    let stream: Observable<ControlAction>
    let confirmationStream: Observable<ControlAction>
    let pickStream: Observable<UIWindow?>
    let imageStream: Observable<NSImage?>
    
    init(stream: Observable<ControlAction>) {
        self.stream = stream.map({checkAccessibilityTrusted(action: $0)})
        self.pickStream = self.stream.filter({$0 != .confirm})
            .map({(0, $0, getRelevantWindows())})
            .scan((0, ControlAction.next, Optional.none)){select(acc: $0, value: $1)}.map { $0.2 }
        self.confirmationStream = self.stream.filter({$0 == .confirm})
        self.imageStream = self.pickStream.map{ captureImage(window: $0)}
        self.confirmationStream.withLatestFrom(self.pickStream)
            .subscribe(onNext: { setFocus(window: $0 )})
            .disposed(by: disposableBag)
        
    }
}

func gotAccess() -> Bool{
    return AXIsProcessTrusted() && CGPreflightScreenCaptureAccess()
}

func checkAccessibilityTrusted(action: ControlAction) -> ControlAction{
    let trusted = gotAccess()
    switch trusted {
    case true:
        return action
    default:
        return .abort
    }
}

func getRelevantWindows() -> [UIWindow] {
    let apps = NSWorkspace.shared.runningApplications.filter{$0.activationPolicy == .regular}
    let windows: Array<UIWindow> = apps.map{
        let pid = $0.processIdentifier
        let name = $0.localizedName
        let app = AXUIElementCreateApplication(pid)
        guard let windowsList =  getAXAttribute(container: app, attribute: kAXWindowsAttribute, to: Array<AXUIElement>()) else {
            return Array<UIWindow>()
        }
        return windowsList.map{
            let id = IDFinder.getWindowID($0)
            return (id, app, $0, name!)
        }
    }.reduce([], +).filter {
        guard let minimized = getAXAttribute(container: $0.axwindow, attribute: kAXMinimizedAttribute, to: Bool()) else {
            return false
        }
        return !minimized
    }.filter {
        guard let enabled = getAXAttribute(container: $0.axwindow, attribute: kAXEnabledAttribute, to: Bool()) else {
            return true
        }
        return !enabled
    }.sorted(by: {$0.id > $1.id})
    return windows
}

func select(acc: UIWindowSelection, value: UIWindowSelectable) -> UIWindowSelection{
    let (lastIndex, _, _) = acc
    let (_, newAction, currentWindows) = value
    let nextIndex : Int = {
        switch newAction{
        case .next: return lastIndex < currentWindows.count - 1 ? lastIndex + 1 : 0
        case .previous: return lastIndex > 0 ? lastIndex - 1 : currentWindows.count - 1
        default: return lastIndex
        }
    }()
    return currentWindows.isEmpty ? (nextIndex, newAction, .none) : (nextIndex, newAction, currentWindows[nextIndex])
}

func setFocus(window: UIWindow?){
    if let win = window {
        AXUIElementSetAttributeValue(win.axapp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(win.axwindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(win.axwindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
}

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

func resizeNsImage(img: NSImage) -> NSImage {
    let destSize = NSMakeSize(CGFloat(560), CGFloat(350))
    let newImage = NSImage(size: destSize)
    newImage.lockFocus()
    img.draw(in: NSMakeRect(0, 0, destSize.width, destSize.height),
             from: NSMakeRect(0, 0, img.size.width, img.size.height),
             operation: NSCompositingOperation.sourceOver,
             fraction: CGFloat(1))
    newImage.unlockFocus()
    newImage.size = destSize
    return newImage
}

func getAXAttribute<T>(container: AXUIElement, attribute: String, to type: T) -> T?{
    var ax: CFTypeRef?
    AXUIElementCopyAttributeValue(container, attribute as CFString, &ax)
    guard let axResult = ax else { return .none }
    return axResult as? T
}

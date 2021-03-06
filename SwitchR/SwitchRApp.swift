//
//  SwitchRApp.swift
//  SwitchR
//
//  Created by Mark Keinhörster on 06.03.21.
//

import SwiftUI
import Foundation
import Cocoa
import HotKey
import RxSwift
import RxRelay

enum ControlAction{
    case nextWindow
    case previousWindow
    case confirmWindow
}

struct ActiveControlKeys {
    private let next: HotKey = HotKey(keyCombo: KeyCombo(key: .n, modifiers: [.control, .option]))
    private let previous: HotKey = HotKey(keyCombo: KeyCombo(key: .p, modifiers: [.control, .option]))
    private let confirm: HotKey = HotKey(keyCombo: KeyCombo(key: .return, modifiers: [.control, .option]))
    private let disposeBag = DisposeBag()
    private let relay: PublishRelay<ControlAction> = PublishRelay<ControlAction>()
    
    init(){
        register()
    }
    
    func register() {
        next.keyDownHandler = {relay.accept(.nextWindow)}
        previous.keyDownHandler = {relay.accept(.previousWindow)}
        confirm.keyDownHandler = {relay.accept(.confirmWindow)}
    }
    
    func stream() -> Observable<ControlAction>{
        return relay.asObservable()
    }
    
}

@main
struct SwitchR: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings{
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var windowFinder: WindowFinder!
    var popover: NSPopover!
    let hotkeys: ActiveControlKeys = ActiveControlKeys()
    let disposableBag: DisposeBag = DisposeBag()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        self.initializeStatusbar()
        self.initializePopover()
        self.initializeStreams()
    }
    
    func initializeStatusbar(){
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        statusBarItem.button?.image = NSImage(named: "Icon")
        let statusBarMenu = NSMenu()
        statusBarItem.menu = statusBarMenu
        statusBarMenu.addItem(withTitle: "Quit", action: #selector(AppDelegate.quit), keyEquivalent: "")
    }
    
    func initializePopover(){
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 560, height: 350)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: EmptyView())
        self.popover = popover
    }
    
    func initializeStreams(){
        windowFinder = WindowFinder(stream: hotkeys.stream())
        windowFinder.imageStream
            .map { self.resizeNsImage(img: $0) }
            .subscribe(onNext: { self.toggleWithImage(img: $0) })
            .disposed(by: disposableBag)
        windowFinder.confirmationStream
            .subscribe(onNext: {self.popover.performClose($0)}).disposed(by: disposableBag)
    }
    
    func toggleWithImage(img: NSImage?){
        if let img = img {
            NSApp.activate(ignoringOtherApps: true)
            if let button = self.statusBarItem.button {
                self.popover.contentViewController!.view = NSImageView(image: img)
                self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            }
        }
    }
    
    func resizeNsImage(img: NSImage?) -> NSImage? {
        guard let img = img else { return .none }
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
    
    func applicationWillResignActive(_ notification: Notification) {
        self.popover.close()
    }
    
    @objc func quit() {
        NSApp.terminate(self)
    }
    
}

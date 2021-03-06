//
//  WindowFinderPrivateCaller.m
//  supperactive
//
//  Created by Mark Keinhörster on 27.02.21.
//

#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>
#import "WindowFinderPrivateCaller.h"

AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *idOut);

@implementation IDFinder

+ (CGWindowID) getWindowID: (AXUIElementRef) axElementRef{
    CGWindowID windowID;
    AXError error = _AXUIElementGetWindow(axElementRef, &windowID);
    if (error != kAXErrorSuccess) {
        return NO;
    }
    return windowID;
}

@end


//
//  WindowFinderPrivateCaller.h
//  supperactive
//
//  Created by Mark Keinhörster on 27.02.21.
//

#ifndef WindowFinderPrivateCaller_h
#define WindowFinderPrivateCaller_h
#import <Carbon/Carbon.h>

@interface IDFinder : NSObject
+ (CGWindowID) getWindowID: (AXUIElementRef) axElementRef;
@end

#endif /* WindowFinderPrivateCaller_h */

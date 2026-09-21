//
//  main.m
//  TweakSettings
//
//  Created by Dana Buehre on 5/16/21.
//
//

#import <UIKit/UIKit.h>
#import <dlfcn.h>

#import "TSAppDelegate.h"
#import "rootless.h"


int main(int argc, char *argv[]) {

    NSString *appDelegateClassName;

    @autoreleasepool {

        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([TSAppDelegate class]);

        NSArray *librariesToLoad = ARRAY_WITH_PLIST([NSBundle.mainBundle pathForResource:@"libraries" ofType:@"plist"]);

        for (NSString *path in librariesToLoad) {
            if (![path isKindOfClass:NSString.class] || !path.isAbsolutePath) continue;
            NSString *resolvedPath = ROOT_PATH_NS_VAR(path);
            if (!resolvedPath.length) continue;
            if (!dlopen(resolvedPath.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL)) {
                NSLog(@"TweakSettings: unable to load %@: %s", resolvedPath, dlerror());
            }
        }

    }

    return UIApplicationMain(argc, argv, nil, appDelegateClassName);

}

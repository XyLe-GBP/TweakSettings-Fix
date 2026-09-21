//
//  AppDelegate.m
//  TweakSettings
//
//  Created by Dana Buehre on 5/16/21.
//
//

#import "TSAppDelegate.h"
#import <CoreSpotlight/CoreSpotlight.h>
#import <dlfcn.h>
#import "TSRootListController.h"
#import "Localizable.h"
#import "TSRootNavigationManager.h"
#import "TSUserDefaults.h"
#import "../Shared/TSUtilitySupport.h"
#import "../Shared/TSPreferenceSupport.h"


static void HandleExceptions(NSException *exception) {
    NSLog(@"TweakSettings unhandled exception: %@", exception.debugDescription);
}

@implementation TSAppDelegate

#pragma mark - UIApplicationDelegate

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {

    NSSetUncaughtExceptionHandler(&HandleExceptions);

    application.shortcutItems = @[
            [[UIApplicationShortcutItem alloc] initWithType:TSActionTypeTweakInject localizedTitle:NSLocalizedString(TWEAKINJECT_TITLE_KEY, nil) localizedSubtitle:NSLocalizedString(TWEAKINJECT_SUBTITLE_KEY, nil) icon:nil userInfo:nil],
            [[UIApplicationShortcutItem alloc] initWithType:TSActionTypeUICache localizedTitle:NSLocalizedString(UICACHE_TITLE_KEY, nil) localizedSubtitle:NSLocalizedString(UICACHE_SUBTITLE_KEY, nil) icon:nil userInfo:nil],
            [[UIApplicationShortcutItem alloc] initWithType:TSActionTypeSafemode localizedTitle:NSLocalizedString(SAFEMODE_TITLE_KEY, nil) localizedSubtitle:NSLocalizedString(SAFEMODE_SUBTITLE_KEY, nil) icon:nil userInfo:nil],
            [[UIApplicationShortcutItem alloc] initWithType:TSActionTypeRespring localizedTitle:NSLocalizedString(RESPRING_TITLE_KEY, nil) localizedSubtitle:NSLocalizedString(RESPRING_SUBTITLE_KEY, nil) icon:nil userInfo:nil]
    ];

    application.shortcutItems = [application.shortcutItems filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UIApplicationShortcutItem *item, NSDictionary *bindings) {
        return TSActionIsAvailable(item.type.UTF8String);
    }]];
    _navigationManager = [TSRootNavigationManager new];

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = (id)_navigationManager.splitController;
    [self.window makeKeyAndVisible];

    return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    if (launchOptions[UIApplicationLaunchOptionsShortcutItemKey]) {

        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleActionForType:[(UIApplicationShortcutItem *)launchOptions[UIApplicationLaunchOptionsShortcutItemKey] type]];
        });
        return NO;
    }

    if (launchOptions[UIApplicationLaunchOptionsURLKey]) {

        [self.navigationManager.rootListController setShowOnLoad:NO];
        [self.navigationManager setDeferredLoadURL:launchOptions[UIApplicationLaunchOptionsURLKey]];
        dispatch_async(dispatch_get_main_queue(), ^{ [self.navigationManager processDeferredURL:NO]; });
        return YES;
    }

    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {

    if (!TSPreferenceIdentifiers(url)) return NO;
    [self.navigationManager processURL:url animated:YES];
    return YES;
}

- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler {

    [self handleActionForType:shortcutItem.type];
    completionHandler(TSIsKnownAction(shortcutItem.type.UTF8String));
}

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray<id<UIUserActivityRestoring>> *))restorationHandler {

    if ([userActivity.activityType isEqualToString:CSSearchableItemActionType]) {
        NSURL *launchURL = [NSURL URLWithString:userActivity.userInfo[CSSearchableItemActivityIdentifier]];
        if (!TSPreferenceIdentifiers(launchURL)) return NO;
        [self.navigationManager processURL:launchURL animated:NO];
        return YES;
    }

    return NO;
}

#pragma mark - Public Methods

- (void)presentAsPopover:(UIViewController *)controller withSender:(id)sender {

    if (!controller) return;
    if (sender == nil) sender = _navigationManager.rootListController.navigationItem.rightBarButtonItem;
    self.popoverSender = sender;

    if (![controller isKindOfClass:UIAlertController.class]) controller.modalPresentationStyle = UIModalPresentationPopover;

    if (sender && [sender isKindOfClass:UIBarButtonItem.class]) {
        controller.popoverPresentationController.barButtonItem = sender;
    }
    else if (sender && [sender isKindOfClass:UIView.class]) {
        controller.popoverPresentationController.sourceRect = [sender bounds];
        controller.popoverPresentationController.sourceView = sender;
        controller.popoverPresentationController.permittedArrowDirections = (UIPopoverArrowDirection)0;
    }

    if (controller.popoverPresentationController && !controller.popoverPresentationController.barButtonItem && !controller.popoverPresentationController.sourceView) {
        UIView *view = self.window.rootViewController.view;
        controller.popoverPresentationController.sourceView = view;
        controller.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds), 1, 1);
        controller.popoverPresentationController.permittedArrowDirections = 0;
    }
    [self presentViewController:controller];
}

- (void)presentViewController:(UIViewController *)controller {
    if (!controller) return;
    UIViewController *presenter = self.window.rootViewController;
    while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed) presenter = presenter.presentedViewController;
    [presenter presentViewController:controller animated:YES completion:nil];
}

- (void)handleActionForType:(NSString *)actionType {
    if (!TSIsKnownAction(actionType.UTF8String)) return;

    if (CanRunWithoutConfirmation(actionType) && !TSUserDefaults.sharedDefaults.requireActionConfirmation) {

        HandleActionForType(actionType);

    } else {

        [self presentAsPopover:ActionAlertForType(actionType) withSender:_popoverSender];
    }
}

- (void)openApplicationURL:(NSURL *)url {

    if (!url) return;
    void (*SBSOpenSensitiveURLAndUnlock)(NSURL *, BOOL);
    if ((SBSOpenSensitiveURLAndUnlock = (void (*)(NSURL *, BOOL)) dlsym(RTLD_DEFAULT, "SBSOpenSensitiveURLAndUnlock"))) {
        (*SBSOpenSensitiveURLAndUnlock)(url, YES);
    } else if (@available(iOS 10,*)) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    }
}

- (void)generateURL {
    NSURL *url = [self.navigationManager urlForCurrentNavStack];
    if (url) [NSUserDefaults.standardUserDefaults setObject:url.absoluteString forKey:@"kPreferencePositionKey"];
}

@end

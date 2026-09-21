//
//  TSRootNavigationManager.m
//  TweakSettings
//
//  Created by Dana Buehre on 11/9/21.
//
//

#import <UIKit/UIKit.h>
#import <Preferences/PSSplitViewController.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "TSRootNavigationManager.h"
#import "TSPrefsRootController.h"
#import "TSRootListController.h"
#import "TSPackageUtility.h"
#import "TSSplitViewController.h"
#import "TSAppDelegate.h"
#import "../Shared/TSPreferenceSupport.h"

@interface TSRootNavigationManager () <UISplitViewControllerDelegate, PSSplitViewControllerNavigationDelegate, UINavigationControllerDelegate>

@property(nonatomic, strong, readonly) PSListController *blankListController;

@end

@implementation TSRootNavigationManager

- (instancetype)init
{
    if (self = [super init]) {

        _blankListController = PSListController.new;
        _splitController = TSSplitViewController.new;
        _rootListController = TSRootListController.new;
        _navigationController = [[TSPrefsRootController alloc] initWithRootViewController:_rootListController rootListController:_rootListController];
        _rootController = [[TSPrefsRootController alloc] initWithRootViewController:_blankListController rootListController:_rootListController];
        _rootListController.rootController = _rootController;
        _splitController.delegate = self;
        if ([_splitController respondsToSelector:@selector(setNavigationDelegate:)]) _splitController.navigationDelegate = self;
        _splitController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
        if ([_splitController respondsToSelector:@selector(setContainerNavigationController:)]) _splitController.containerNavigationController = _rootController;
        [_splitController setViewControllers:@[_navigationController, _rootController]];
        if ([_rootController respondsToSelector:@selector(setSupportedInterfaceOrientations:)]) [_rootController setSupportedInterfaceOrientations:_splitController.supportedInterfaceOrientations];
        _navigationController.delegate = self;
        _rootController.delegate = self;
    }

    return self;
}

#pragma mark - UISplitViewControllerDelegate

- (BOOL)splitViewController:(UISplitViewController *)splitViewController collapseSecondaryViewController:(UIViewController *)secondaryViewController ontoPrimaryViewController:(UIViewController *)primaryViewController
{
    NSArray *details = [_rootController.viewControllers filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UIViewController *controller, NSDictionary *bindings) {
        return controller != self->_blankListController;
    }]];
    // Move controllers between navigation stacks instead of nesting navigation controllers.
    [_rootController setViewControllers:@[_blankListController] animated:NO];
    NSMutableArray *stack = [NSMutableArray arrayWithObject:_rootListController];
    [stack addObjectsFromArray:details];
    [self _assignRootController:(PSRootController *)_navigationController toControllers:stack];
    [_navigationController setViewControllers:stack animated:NO];
    return YES;
}

- (UIViewController *)splitViewController:(UISplitViewController *)splitViewController separateSecondaryViewControllerFromPrimaryViewController:(UIViewController *)primaryViewController {
    NSMutableArray *details = _navigationController.viewControllers.mutableCopy;
    [details removeObject:_rootListController];
    [_navigationController setViewControllers:@[_rootListController] animated:NO];
    _rootListController.rootController = _rootController;
    [self _assignRootController:_rootController toControllers:details];
    [_rootController setViewControllers:details.count ? details : @[_blankListController] animated:NO];
    [self _resetNavigationAppearance:_navigationController];
    [self _resetNavigationAppearance:_rootController];
    return _rootController;
}

#pragma mark - PSSplitViewControllerNavigationDelegate

- (void)splitViewControllerDidPopToRootController:(id)splitViewController
{
    [self _resetNavigationAppearance:_navigationController];
    [self _resetNavigationAppearance:_rootController];
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (_deferredLoadURL) {

       [self processDeferredURL:NO];
    }
}

#pragma mark - Public Methods

- (UIViewController *)topViewController
{
    return self.isCollapsed ? _navigationController.topViewController : _rootController.topViewController;
}

- (UINavigationController *)topNavigationController
{
    return self.isCollapsed ? _navigationController : (typeof(_navigationController))_rootController;
}

- (BOOL)isCollapsed
{
    return _splitController.collapsed;
}

- (NSURL *)urlForCurrentNavStack {
    NSMutableArray *identifiers = [NSMutableArray array];
    for (UIViewController *controller in self.topNavigationController.viewControllers) {
        if (controller == _rootListController || controller == _blankListController || ![controller isKindOfClass:PSViewController.class]) continue;
        NSString *identifier = [(PSViewController *)controller specifier].identifier;
        if (!identifier.length) break;
        [identifiers addObject:identifier];
    }
    return TSPreferenceURL(identifiers);
}

- (void)processDeferredURL:(BOOL)animated {
    if (!_rootListController.rootListLoaded || !_deferredLoadURL) return;
    NSURL *url = _deferredLoadURL;
    _deferredLoadURL = nil; // Clear before changing controllers, which invokes the delegate again.
    [self processURL:url animated:animated];
}

- (void)processURL:(NSURL *)url animated:(BOOL)animated {
    NSArray *components = TSPreferenceIdentifiers(url);
    if (!components) return;
    if (!_rootListController.rootListLoaded) {
        self.deferredLoadURL = url;
        return;
    }
    NSMutableArray *controllers = [NSMutableArray array];
    PSListController *parentController = _rootListController;
    for (NSString *identifier in components) {
        if (!parentController) return;
        PSSpecifier *specifier = nil;
        // Deep links must also find items hidden by the current search query.
        if (parentController == _rootListController) {
            for (PSSpecifier *candidate in _rootListController.unfilteredSpecifiers) {
                if ([candidate.identifier isEqualToString:identifier]) { specifier = candidate; break; }
            }
        } else {
            @try {
                [parentController loadViewIfNeeded];
                [parentController specifiers];
                specifier = [parentController specifierForID:identifier];
            } @catch (NSException *exception) {
                NSLog(@"TweakSettings: cannot navigate preferences: %@", exception.reason);
                [self _showLoadError:parentController.specifier];
                return;
            }
        }
        if (!specifier) return;
        PSViewController *controller = [TSPackageUtility controllerForSpecifier:specifier inController:parentController];
        if (!controller) { [self _showLoadError:specifier]; return; }
        [controllers addObject:controller];
        parentController = [controller isKindOfClass:PSListController.class] ? (PSListController *)controller : nil;
    }
    if (self.isCollapsed) [controllers insertObject:_rootListController atIndex:0];
    else if (!controllers.count) [controllers addObject:_blankListController];
    [self.topNavigationController setViewControllers:controllers animated:animated];
}

- (void)pushDetailControllerForSpecifier:(PSSpecifier *)specifier {
    PSViewController *controller = [TSPackageUtility controllerForSpecifier:specifier inController:_rootListController];

    if (controller) {

        if (self.isCollapsed) [self.topNavigationController pushViewController:controller animated:YES];
        else [self.topNavigationController setViewControllers:@[controller] animated:NO];
        [self _resetNavigationAppearance:self.rootController];
    } else {
        [self _showLoadError:specifier];
    }
}

#pragma mark - Private Methods

- (void)_showLoadError:(PSSpecifier *)specifier {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"PREFERENCE_LOAD_FAILED_TITLE", nil) message:[NSString stringWithFormat:NSLocalizedString(@"PREFERENCE_LOAD_FAILED_MESSAGE", nil), specifier.name ?: @""] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"ALERT_DISMISS_TITLE_KEY", nil) style:UIAlertActionStyleCancel handler:nil]];
    [APP_DELEGATE presentViewController:alert];
}


- (void)_resetNavigationAppearance:(UINavigationController *)controller {
    [controller.navigationBar setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
    [controller.navigationBar setShadowImage:nil];
    [controller.navigationBar setTintColor:nil];
    [controller.navigationBar setBarTintColor:nil];
    [controller.navigationBar setTitleTextAttributes:nil];
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithDefaultBackground];
    controller.navigationBar.standardAppearance = appearance;
    controller.navigationBar.scrollEdgeAppearance = appearance;
    controller.navigationBar.compactAppearance = appearance;
    if (@available(iOS 11, *)) {

        [controller.navigationBar setLargeTitleTextAttributes:nil];
    }
}

- (void)_assignRootController:(PSRootController *)rootController toControllers:(NSArray<UIViewController *> *)controllers {
    for (UIViewController *controller in controllers) {
        if ([controller isKindOfClass:PSViewController.class]) [(PSViewController *)controller setRootController:rootController];
    }
}

@end

//
// Created by Dana Buehre on 6/20/21.
//

#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>
#import <CoreSpotlight/CoreSpotlight.h>
#import <CoreServices/CoreServices.h>
#import <dlfcn.h>

#import "TSPackageUtility.h"
#import "libprefs.h"
#import "rootless.h"
#import "../Shared/TSPreferenceSupport.h"

#pragma mark - LIBPREFS Shim

BOOL PREFERENCE_FILTER_PASSES_ENVIRONMENT_CHECKS(NSDictionary *filter) {
    return TSPreferenceFilterMatchesVersion(filter, kCFCoreFoundationVersionNumber);
}

NSArray *SPECIFIERS_FROM_ENTRY(NSDictionary *entry, NSString *sourceBundlePath, NSString *title, PSListController *listController) {

    if (![entry isKindOfClass:NSDictionary.class]) return nil;
    NSString *bundleName = entry[@"bundle"];
    if (bundleName && (![bundleName isKindOfClass:NSString.class] || !bundleName.length)) return nil;
    NSString *bundlePath = entry[@"bundlePath"];
    if (![bundlePath isKindOfClass:NSString.class]) bundlePath = nil;
    NSDictionary *specifierPlist = @{ @"items" : @[entry] };
    BOOL isBundle = bundleName != nil;

    if (isBundle) {
        NSFileManager *fileManger = NSFileManager.defaultManager;
        // Prefix only jailbreak-owned absolute paths; system frameworks stay on the root filesystem.
        if ([bundlePath hasPrefix:@"/Library/"] || [bundlePath hasPrefix:@"/usr/"]) bundlePath = ROOT_PATH_NS_VAR(bundlePath);
        if (!bundlePath || ![fileManger fileExistsAtPath:bundlePath])
            bundlePath = [ROOT_PATH_NS(@"/Library/PreferenceBundles") stringByAppendingPathComponent:[bundleName stringByAppendingPathExtension:@"bundle"]];
        if (!bundlePath || ![fileManger fileExistsAtPath:bundlePath])
            bundlePath = [@"/System/Library/PreferenceBundles" stringByAppendingPathComponent:[bundleName stringByAppendingPathExtension:@"bundle"]];
        if (!bundlePath || ![fileManger fileExistsAtPath:bundlePath]) {
            return nil;
        }
    }

    NSBundle *prefBundle = [NSBundle bundleWithPath:(isBundle ? bundlePath : sourceBundlePath)];
    if (!prefBundle) return nil;
    NSMutableArray *bundleControllers = [listController valueForKey:@"_bundleControllers"];
    typedef NSArray *(*Parser)(NSDictionary *, PSSpecifier *, id, NSString *, NSBundle *, NSString **, NSString **, PSListController *, NSMutableArray **);
    static Parser parser;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        parser = (Parser)dlsym(RTLD_DEFAULT, "SpecifiersFromPlist");
    });
    if (!parser) {
        NSLog(@"TweakSettings: Preferences does not export SpecifiersFromPlist");
        return nil;
    }
    NSArray *specs = parser(specifierPlist, nil, listController, title, prefBundle, NULL, NULL, listController, &bundleControllers);
    // The parser can replace this array. Retain it on the owning controller.
    [listController setValue:bundleControllers forKey:@"_bundleControllers"];

    if (!specs.count) return nil;

    if (isBundle) {
        if ([entry[PSBundleIsControllerKey] boolValue]) {
            for (PSSpecifier *specifier in specs) {
                [specifier setProperty:bundlePath forKey:PSLazilyLoadedBundleKey];
                [specifier setProperty:[NSBundle bundleWithPath:sourceBundlePath] forKey:@"pl_bundle"];
                if (!specifier.name) specifier.name = title;
            }
        }
    } else {
        Class customClass = NSClassFromString(@"PLCustomListController");
        Class localizedClass = NSClassFromString(@"PLLocalizedListController");
        BOOL isLocalizedBundle = ![sourceBundlePath.lastPathComponent isEqualToString:@"Preferences"];

        Class detailClass = isLocalizedBundle && localizedClass ? localizedClass : customClass;
        if (detailClass) {

            PSSpecifier *specifier = specs.firstObject;
            [specifier setValue:detailClass forKey:@"detailControllerClass"];
            [specifier setProperty:prefBundle forKey:@"pl_bundle"];

            if (![specifier.properties[PSTitleKey] isEqualToString:title]) {
                [specifier setProperty:title forKey:@"pl_alt_plist_name"];
                if (!specifier.name) specifier.name = title;
            }
        }
    }

    return specs;
}


@implementation TSPackageUtility {

}

#pragma mark - Member Methods

+ (NSArray<PSSpecifier *> *)loadTweakSpecifiersInController:(PSListController *)controller {
    NSMutableArray *preferenceSpecifiers = [NSMutableArray new];
    NSString *preferencesPath = ROOT_PATH_NS(@"/Library/PreferenceLoader/Preferences");
    if (!preferencesPath) return @[];
    NSArray *preferenceBundlePaths = [NSFileManager.defaultManager subpathsOfDirectoryAtPath:preferencesPath error:nil];
    NSMutableArray *searchableItems = [NSMutableArray new];

    for (NSString *item in [preferenceBundlePaths sortedArrayUsingSelector:@selector(compare:)])
    {
        if (![item.pathExtension.lowercaseString isEqualToString:@"plist"]) continue;
        @try {

        NSString *plistPath = [preferencesPath stringByAppendingPathComponent:item];
        NSDictionary *plist = DICTIONARY_WITH_PLIST(plistPath);

        if (![plist[@"entry"] isKindOfClass:NSDictionary.class]) continue;
        if (!PREFERENCE_FILTER_PASSES_ENVIRONMENT_CHECKS(plist[@"filter"] ?: plist[@"pl_filter"])) continue;
        if (!PREFERENCE_FILTER_PASSES_ENVIRONMENT_CHECKS(plist[@"entry"][@"pl_filter"])) continue;

        NSString *bundlePath = [plistPath stringByDeletingLastPathComponent];
        NSString *title = [item.lastPathComponent stringByDeletingPathExtension];
        // Use capabilities of the loaded library, never dpkg package filenames.
        NSArray *itemSpecifiers = [controller respondsToSelector:@selector(specifiersFromEntry:sourcePreferenceLoaderBundlePath:title:)]
            ? [controller specifiersFromEntry:plist[@"entry"] sourcePreferenceLoaderBundlePath:bundlePath title:title]
            : SPECIFIERS_FROM_ENTRY(plist[@"entry"], bundlePath, title, controller);
        if (!itemSpecifiers || ([itemSpecifiers isKindOfClass:NSArray.class] && !itemSpecifiers.count)) itemSpecifiers = SPECIFIERS_FROM_ENTRY(plist[@"entry"], bundlePath, title, controller);
        if (![itemSpecifiers isKindOfClass:NSArray.class]) continue;

        if (itemSpecifiers && itemSpecifiers.count) {

            for (PSSpecifier *specifier in itemSpecifiers)
            {
                if (![specifier isKindOfClass:PSSpecifier.class]) continue;
                if (![specifier.name isKindOfClass:NSString.class] || !specifier.name.length) specifier.name = title;
                if (![specifier.identifier isKindOfClass:NSString.class] || !specifier.identifier.length) {
                    specifier.identifier = [item stringByAppendingFormat:@"#%lu", (unsigned long)[itemSpecifiers indexOfObjectIdenticalTo:specifier]];
                }
                if (![[specifier propertyForKey:PSIconImageKey] isKindOfClass:UIImage.class]) {

                    [specifier setProperty:[UIImage imageNamed:@"tweak"] forKey:PSIconImageKey];
                }

                CSSearchableItemAttributeSet *attributeSet = [[CSSearchableItemAttributeSet alloc] initWithItemContentType:@"public.content"];
                attributeSet.title = specifier.name;
                attributeSet.contentDescription = [NSString stringWithFormat:@"Tweak Settings \u2192 %@", specifier.name];
                attributeSet.thumbnailData = UIImagePNGRepresentation([specifier propertyForKey:PSIconImageKey]);
                attributeSet.keywords = @[@"tweaks", @"packages", @"jailbreak", specifier.name];

                NSString *uniqueIdentifier = TSPreferenceURL(@[specifier.identifier]).absoluteString;
                CSSearchableItem *searchItem = [[CSSearchableItem alloc] initWithUniqueIdentifier:uniqueIdentifier domainIdentifier:@"com.creaturecoding.tweaksettings" attributeSet:attributeSet];
                [searchableItems addObject:searchItem];
                [preferenceSpecifiers addObject:specifier];
            }


        }
        } @catch (NSException *exception) {
            NSLog(@"TweakSettings: skipped %@: %@", item, exception.reason);
        }
    }

    if (preferenceSpecifiers.count) {

        [preferenceSpecifiers sortUsingDescriptors:@[
                [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)]]
        ];
    }

    static NSUInteger indexGeneration = 0;
    NSUInteger generation = ++indexGeneration;
    [CSSearchableIndex.defaultSearchableIndex deleteSearchableItemsWithDomainIdentifiers:@[@"com.creaturecoding.tweaksettings"] completionHandler:^(NSError *error) {
        MAIN_QUEUE(^{
            if (!error && generation == indexGeneration) [CSSearchableIndex.defaultSearchableIndex indexSearchableItems:searchableItems completionHandler:nil];
        });
    }];

    return preferenceSpecifiers;
}

+ (PSViewController *)controllerForSpecifier:(PSSpecifier *)specifier inController:(PSListController *)parentController {

    if (!specifier || !parentController) return nil;
    @try {
    // libprefs' controller factory assumes UIKit already performed the lazy load.
    // Our deep-link and split-view paths invoke the factory directly.
    if ([specifier respondsToSelector:@selector(performControllerLoadAction)]) [specifier performControllerLoadAction];
    else if ([specifier propertyForKey:PSLazilyLoadedBundleKey] && [parentController respondsToSelector:@selector(lazyLoadBundle:)]) {
        [parentController lazyLoadBundle:specifier];
    }
    if ([parentController respondsToSelector:@selector(controllerForSpecifier:)]) {

        id controller = [parentController controllerForSpecifier:specifier];
        if ([controller isKindOfClass:PSViewController.class]) return controller;
        if (controller) return nil;
    }

    Class detailClass = [specifier respondsToSelector:@selector(detailControllerClass)]
            ? [specifier detailControllerClass]
            : [specifier valueForKey:@"detailControllerClass"];

    if ([detailClass isSubclassOfClass:PSViewController.class]) {

        id controller = [detailClass alloc];
        controller = ([controller respondsToSelector:@selector(initForContentSize:)])
                ? [controller initForContentSize:UIScreen.mainScreen.bounds.size]
                : [controller init];

        if (controller && [controller isKindOfClass:PSViewController.class]) {

            [controller setRootController:parentController.rootController];
            [controller setParentController:parentController];
            [controller setSpecifier:specifier];
        }

        return controller;
    }

    } @catch (NSException *exception) {
        NSLog(@"TweakSettings: cannot open %@: %@", specifier.name, exception.reason);
    }
    return nil;
}

@end

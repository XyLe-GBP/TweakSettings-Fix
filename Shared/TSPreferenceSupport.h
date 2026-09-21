#pragma once
#import <Foundation/Foundation.h>
#include <math.h>

static inline BOOL TSPreferenceFilterMatchesVersion(id filter, double version) {
    if (!filter) return YES;
    if (![filter isKindOfClass:NSDictionary.class]) return NO;
    id bounds = filter[@"CoreFoundationVersion"];
    if (!bounds) return YES;
    if (![bounds isKindOfClass:NSArray.class] || [bounds count] > 2) return NO;
    double values[2] = {0, 0};
    for (NSUInteger i = 0; i < [bounds count]; i++) {
        id value = bounds[i];
        if ([value isKindOfClass:NSNumber.class]) values[i] = [value doubleValue];
        else if ([value isKindOfClass:NSString.class]) {
            NSScanner *scanner = [NSScanner scannerWithString:value];
            if (![scanner scanDouble:&values[i]] || !scanner.isAtEnd) return NO;
        } else return NO;
        if (!isfinite(values[i])) return NO;
    }
    return ([bounds count] == 0 || version >= values[0]) &&
           ([bounds count] < 2 || version < values[1]);
}

static inline NSURL *TSPreferenceURL(NSArray<NSString *> *identifiers) {
    NSMutableArray *encoded = [NSMutableArray array];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    for (id identifier in identifiers) {
        if (![identifier isKindOfClass:NSString.class] || ![identifier length]) return nil;
        [encoded addObject:[identifier stringByAddingPercentEncodingWithAllowedCharacters:allowed]];
    }
    return [NSURL URLWithString:[@"tweaks:root=" stringByAppendingString:[encoded componentsJoinedByString:@"/"]]];
}

static inline NSArray<NSString *> *TSPreferenceIdentifiers(NSURL *url) {
    NSString *text = url.absoluteString;
    if (![url.scheme.lowercaseString isEqualToString:@"tweaks"] || text.length > 8192) return nil;
    NSRange colon = [text rangeOfString:@":"];
    if (colon.location == NSNotFound) return nil;
    NSString *path = [text substringFromIndex:colon.location + 1];
    if (![path hasPrefix:@"root="]) return nil;
    path = [path substringFromIndex:5];
    if (!path.length) return @[];
    if ([path rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]].location != NSNotFound) return nil;
    NSArray *components = [path componentsSeparatedByString:@"/"];
    if (components.count > 64) return nil;
    NSMutableArray *identifiers = [NSMutableArray array];
    for (NSString *component in components) {
        NSString *identifier = component.stringByRemovingPercentEncoding;
        if (!identifier.length) return nil;
        [identifiers addObject:identifier];
    }
    return identifiers;
}

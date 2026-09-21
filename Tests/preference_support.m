#import "../Shared/TSPreferenceSupport.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        NSArray *identifiers = @[@"A/B", @"日本語 & # ? = %", @"Sub pane"];
        NSURL *url = TSPreferenceURL(identifiers);
        assert([TSPreferenceIdentifiers(url) isEqual:identifiers]);
        assert([TSPreferenceIdentifiers(TSPreferenceURL(@[])) isEqual:@[]]);
        assert([TSPreferenceIdentifiers([NSURL URLWithString:@"TWEAKS:root=Test"]) isEqual:@[@"Test"]]);
        assert(TSPreferenceIdentifiers([NSURL URLWithString:@"https://example.com/root=Test"]) == nil);
        assert(TSPreferenceIdentifiers([NSURL URLWithString:@"tweaks:wrong=Test"]) == nil);
        assert(TSPreferenceIdentifiers([NSURL URLWithString:@"tweaks:root=A//B"]) == nil);
        assert(TSPreferenceIdentifiers([NSURL URLWithString:@"tweaks:root=A?B"]) == nil);
        assert([TSPreferenceIdentifiers(TSPreferenceURL(@[@"A#B"])) isEqual:@[@"A#B"]]);
        assert(TSPreferenceIdentifiers(nil) == nil);
        assert(TSPreferenceURL(@[@""]) == nil);
        assert(TSPreferenceURL((id)@[@1]) == nil);
        assert(TSPreferenceFilterMatchesVersion(nil, 2000));
        assert(TSPreferenceFilterMatchesVersion(@{}, 2000));
        assert(TSPreferenceFilterMatchesVersion(@{@"CoreFoundationVersion": @[]}, 2000));
        assert(TSPreferenceFilterMatchesVersion(@{@"CoreFoundationVersion": @[@2000]}, 2000));
        assert(!TSPreferenceFilterMatchesVersion(@{@"CoreFoundationVersion": @[@2000]}, 1999));
        assert(TSPreferenceFilterMatchesVersion(@{@"CoreFoundationVersion": @[@1900, @2100]}, 2000));
        assert(!TSPreferenceFilterMatchesVersion(@{@"CoreFoundationVersion": @[@1900, @2000]}, 2000));
        assert(TSPreferenceFilterMatchesVersion(@{@"CoreFoundationVersion": @[@"1900.5", @"2100"]}, 2000));
        for (id malformed in @[@[], @1, @"filter", NSNull.null,
                               @{@"CoreFoundationVersion": @1},
                               @{@"CoreFoundationVersion": @[@"garbage"]},
                               @{@"CoreFoundationVersion": @[@"100x"]},
                               @{@"CoreFoundationVersion": @[NSNull.null]},
                               @{@"CoreFoundationVersion": @[@1, @2, @3]}]) {
            assert(!TSPreferenceFilterMatchesVersion(malformed, 2000));
        }
        puts("Preference filters and deep-link round trips: passed");
    }
}

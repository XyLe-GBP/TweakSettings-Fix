//
// Created by Dana Buehre on 11/21/21.
//

#import <UIKit/UIKit.h>
#import "TSChangelogController.h"
#import <Preferences/PSSpecifier.h>


@implementation TSChangelogController {

    NSArray *_releases;
    NSString *_loadError;
    NSURLSessionDataTask *_loadTask;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self _loadChangelog];
}

#pragma mark - PSListController

- (NSMutableArray *)specifiers {

    if (!_specifiers) {

        if (_releases) {

            NSMutableArray *specifiers = [NSMutableArray new];

            for (NSDictionary *release in _releases) {

                [specifiers addObject:[PSSpecifier groupSpecifierWithName:release[@"version"]]];

                for (NSString *change in release[@"changes"]) {

                    [specifiers addObject:[PSSpecifier preferenceSpecifierNamed:change target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
                }
            }

            _specifiers = specifiers;
        }

        else if (_loadError) {
            _specifiers = @[[PSSpecifier preferenceSpecifierNamed:_loadError target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]].mutableCopy;
        }
        else {

            _specifiers = @[[PSSpecifier preferenceSpecifierNamed:nil target:nil set:nil get:nil detail:nil cell:PSSpinnerCell edit:nil]].mutableCopy;
        }
    }

    return _specifiers;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    return cell;
}

#pragma mark - Private Methods

- (void)_loadChangelog {
    if (_loadTask || _releases) return;
    _loadError = nil;
    _specifiers = nil;
    [self reloadSpecifiers];
    NSURL *url = [NSURL URLWithString:@"https://api.creaturecoding.com/info/package?id=tweaksettings&key=changelog"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    __weak typeof(self) weakSelf = self;
    _loadTask = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        id json = data && !error && status >= 200 && status < 300 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSMutableArray *releases = [NSMutableArray array];
        if ([json isKindOfClass:NSArray.class]) {
            for (id release in json) {
                if (![release isKindOfClass:NSDictionary.class] || ![release[@"version"] isKindOfClass:NSString.class] || ![release[@"changes"] isKindOfClass:NSArray.class]) continue;
                NSMutableArray *changes = [NSMutableArray array];
                for (id change in release[@"changes"]) if ([change isKindOfClass:NSString.class]) [changes addObject:change];
                [releases addObject:@{@"version": release[@"version"], @"changes": changes}];
            }
        }
        MAIN_QUEUE(^{
            typeof(self) self = weakSelf;
            if (!self) return;
            self->_loadTask = nil;
            self->_releases = releases.count ? releases : nil;
            self->_loadError = releases.count ? nil : NSLocalizedString(@"CHANGELOG_LOAD_FAILED", nil);
            self->_specifiers = nil;
            [self reloadSpecifiers];
        });
    }];
    [_loadTask resume];
}

- (void)dealloc {
    [_loadTask cancel];
}

@end

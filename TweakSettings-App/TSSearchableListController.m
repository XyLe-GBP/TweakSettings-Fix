//
//  TSSearchableListController.m
//  TweakSettings
//
//  Created by Dana Buehre on 5/16/21.
//
//

#import <Preferences/PSSpecifier.h>
#import "TSSearchableListController.h"
#import "TSUserDefaults.h"

@interface TSSearchableListController ()

@end

@implementation TSSearchableListController {

    UISearchController *_searchController;
    BOOL _firstLoadComplete;
}

- (instancetype)init {

    if (self = [super init]) {

        _showOnLoad = YES;
    }

    return self;
}

- (instancetype)initForContentSize:(CGSize)contentSize {

    if (self = [super init]) {

        _showOnLoad = YES;
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.hidesNavigationBarDuringPresentation = NO;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.delegate = self;
    _searchController.delegate = self;
    self.definesPresentationContext = YES;

    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = _searchController;
        self.navigationController.navigationBar.prefersLargeTitles = TSUserDefaults.sharedDefaults.useLargeTitlesOnRootList;
    } else {
        self.table.tableHeaderView = _searchController.searchBar;
    }

    self.unfilteredSpecifiers = self.specifiers.mutableCopy;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (!_firstLoadComplete) {

        if (@available(iOS 11, *)) {
            self.navigationItem.hidesSearchBarWhenScrolling = NO;
            [self.navigationController.navigationBar sizeToFit];
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];


    if (!_firstLoadComplete) {

        if (@available(iOS 11, *)) {
            self.navigationItem.hidesSearchBarWhenScrolling = !TSUserDefaults.sharedDefaults.alwaysShowSearchBar;
        }

        self->_firstLoadComplete = YES;
    }
}

#pragma mark - UISearchResultsUpdating

- (void)refreshSearchResults {
    // Preference lists are small; synchronous filtering avoids stale background results
    // overwriting a newer query or a freshly reloaded package list.
    NSString *text = _searchController.searchBar.text;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@", text ?: @""];
    self.specifiers = text.length ? [self.unfilteredSpecifiers filteredArrayUsingPredicate:predicate].mutableCopy : self.unfilteredSpecifiers.mutableCopy;
    [self.table reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self refreshSearchResults];
}

- (void)didDismissSearchController:(UISearchController *)searchController {
    self.specifiers = self.unfilteredSpecifiers.mutableCopy;
    [self.table reloadData];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    [self refreshSearchResults];
}

@end

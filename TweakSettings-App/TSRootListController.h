//
//  TSRootListController.h
//  TweakSettings
//
//  Created by Dana Buehre on 5/16/21.
//
//

#import "TSSearchableListController.h"

@interface TSRootListController : TSSearchableListController <UIGestureRecognizerDelegate>

@property (nonatomic, assign) BOOL rootListLoaded;

@end

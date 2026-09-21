//
//  TSActionType.m
//  TweakSettings
//
//  Created by Dana Buehre on 5/30/21.
//
//

#import <UIKit/UIKit.h>
#import "TSUtilityActionManager.h"
#import "Localizable.h"
#import "TSAppDelegate.h"
#import "rootless.h"
#import <spawn.h>
#import <sys/wait.h>
#import <fcntl.h>
#import <errno.h>
#import <sysexits.h>
#import "../Shared/TSUtilitySupport.h"

NSString *const TSActionTypeRespring = @"respring";
NSString *const TSActionTypeSafemode = @"safemode";
NSString *const TSActionTypeUICache = @"uicache";
NSString *const TSActionTypeLDRestart = @"ldrestart";
NSString *const TSActionTypeReboot = @"reboot";
NSString *const TSActionTypeUserspaceReboot = @"usreboot";
NSString *const TSActionTypeTweakInject = @"tweakinject";

struct TaskResult ExecuteAction(NSString *actionType) {
    struct TaskResult result = {.status = EX_USAGE, .output = nil, .error = nil};
    if (!TSIsKnownAction(actionType.UTF8String)) {
        result.error = @"Unknown action.";
        return result;
    }
    int descriptors[2];
    if (pipe(descriptors) != 0) {
        result.status = errno;
        result.error = [NSString stringWithUTF8String:strerror(errno)];
        return result;
    }
    fcntl(descriptors[0], F_SETFD, FD_CLOEXEC);
    fcntl(descriptors[1], F_SETFD, FD_CLOEXEC);
    posix_spawn_file_actions_t fileActions;
    int status = posix_spawn_file_actions_init(&fileActions);
    BOOL initialized = status == 0;
    if (!status) status = posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    if (!status) status = posix_spawn_file_actions_adddup2(&fileActions, descriptors[1], STDOUT_FILENO);
    if (!status) status = posix_spawn_file_actions_adddup2(&fileActions, descriptors[1], STDERR_FILENO);
    if (!status) status = posix_spawn_file_actions_addclose(&fileActions, descriptors[0]);
    if (!status) status = posix_spawn_file_actions_addclose(&fileActions, descriptors[1]);
    NSString *path = ROOT_PATH_NS(@"/usr/bin/tweaksettings-utility");
    if (!path) status = ENOENT;
    NSString *argument = [@"--" stringByAppendingString:actionType];
    char *arguments[] = {(char *)path.fileSystemRepresentation, (char *)argument.UTF8String, NULL};
    char *environment[] = {"PATH=/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin", "LANG=C", NULL};
    pid_t pid = -1;
    if (!status) status = posix_spawn(&pid, path.fileSystemRepresentation, &fileActions, NULL, arguments, environment);
    if (initialized) posix_spawn_file_actions_destroy(&fileActions);
    close(descriptors[1]);
    if (status) {
        close(descriptors[0]);
        result.status = status;
        result.error = [NSString stringWithUTF8String:strerror(status)];
        return result;
    }
    // Drain stdout and stderr together before waiting: a full pipe must not deadlock the child.
    NSMutableData *output = [NSMutableData data];
    char buffer[4096];
    ssize_t count;
    while ((count = read(descriptors[0], buffer, sizeof(buffer))) != 0) {
        if (count < 0) {
            if (errno == EINTR) continue;
            break;
        }
        NSUInteger remaining = 65536 - output.length;
        if (remaining) [output appendBytes:buffer length:MIN((NSUInteger)count, remaining)];
    }
    close(descriptors[0]);
    int waitStatus = 0;
    pid_t waited;
    do { waited = waitpid(pid, &waitStatus, 0); } while (waited < 0 && errno == EINTR);
    result.status = waited < 0 ? errno : WIFEXITED(waitStatus) ? WEXITSTATUS(waitStatus) : 128 + WTERMSIG(waitStatus);
    result.output = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
    if (result.status) result.error = result.output.length ? result.output : [NSString stringWithFormat:@"Action failed (status %d).", result.status];
    return result;
}

NSString *TitleForActionType(NSString *type) {
    if ([type isEqualToString:TSActionTypeRespring]) return NSLocalizedString(RESPRING_TITLE_KEY, nil);
    if ([type isEqualToString:TSActionTypeSafemode]) return NSLocalizedString(SAFEMODE_TITLE_KEY, nil);
    if ([type isEqualToString:TSActionTypeUICache]) return NSLocalizedString(UICACHE_TITLE_KEY, nil);
    if ([type isEqualToString:TSActionTypeLDRestart]) return NSLocalizedString(LDRESTART_TITLE_KEY, nil);
    if ([type isEqualToString:TSActionTypeReboot]) return NSLocalizedString(REBOOT_TITLE_KEY, nil);
    if ([type isEqualToString:TSActionTypeUserspaceReboot]) return NSLocalizedString(USREBOOT_TITLE_KEY, nil);
    if ([type isEqualToString:TSActionTypeTweakInject]) return NSLocalizedString(TWEAKINJECT_TITLE_KEY, nil);
    return nil;
}

NSString *SubtitleForActionType(NSString *type) {
    if ([type isEqualToString:TSActionTypeRespring]) return NSLocalizedString(RESPRING_SUBTITLE_KEY, nil);
    if ([type isEqualToString:TSActionTypeSafemode]) return NSLocalizedString(SAFEMODE_SUBTITLE_KEY, nil);
    if ([type isEqualToString:TSActionTypeUICache]) return NSLocalizedString(UICACHE_SUBTITLE_KEY, nil);
    if ([type isEqualToString:TSActionTypeLDRestart]) return NSLocalizedString(LDRESTART_SUBTITLE_KEY, nil);
    if ([type isEqualToString:TSActionTypeReboot]) return NSLocalizedString(REBOOT_SUBTITLE_KEY, nil);
    if ([type isEqualToString:TSActionTypeUserspaceReboot]) return NSLocalizedString(USREBOOT_SUBTITLE_KEY, nil);
    if ([type isEqualToString:TSActionTypeTweakInject]) return NSLocalizedString(TWEAKINJECT_SUBTITLE_KEY, nil);
    return nil;
}

BOOL CanRunWithoutConfirmation(NSString *actionType) {
    return TSIsKnownAction(actionType.UTF8String) &&
        ![actionType isEqualToString:TSActionTypeReboot] &&
        ![actionType isEqualToString:TSActionTypeLDRestart] &&
        ![actionType isEqualToString:TSActionTypeUserspaceReboot] &&
        ![actionType isEqualToString:TSActionTypeTweakInject];
}

void HandleActionForType(NSString *actionType) {
    // All callers are UI handlers. Serialize actions and keep process I/O off the main thread.
    static BOOL actionRunning = NO;
    if (actionRunning || !TSIsKnownAction(actionType.UTF8String)) return;
    actionRunning = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        struct TaskResult result = ExecuteAction(actionType);
        dispatch_async(dispatch_get_main_queue(), ^{
            actionRunning = NO;
            if (result.status != 0) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"ACTION_FAILED_TITLE", nil) message:result.error preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(ALERT_DISMISS_TITLE_KEY, nil) style:UIAlertActionStyleCancel handler:nil]];
                [APP_DELEGATE presentViewController:alert];
            }
        });
    });
}

UIAlertController *ActionAlertForType(NSString *actionType) {
    if (!TSIsKnownAction(actionType.UTF8String)) return nil;
    NSString *title = TitleForActionType(actionType);
    NSString *message = [NSString stringWithFormat:NSLocalizedString(ALERT_ACTION_MESSAGE_KEY, nil), SubtitleForActionType(actionType)];
    UIAlertController *controller = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [controller addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        HandleActionForType(actionType);
    }]];
    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(ALERT_CANCEL_TITLE_KEY, nil) style:UIAlertActionStyleCancel handler:nil]];
    return controller;
}

static NSArray<NSString *> *AvailableActions(void) {
    NSArray *actions = @[TSActionTypeRespring, TSActionTypeSafemode, TSActionTypeUICache, TSActionTypeLDRestart,
                         TSActionTypeReboot, TSActionTypeUserspaceReboot, TSActionTypeTweakInject];
    return [actions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *action, NSDictionary *bindings) {
        return TSActionIsAvailable(action.UTF8String);
    }]];
}

UIAlertController *ActionListAlert(void) {
    UIAlertController *controller = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *type in AvailableActions()) {
        [controller addAction:[UIAlertAction actionWithTitle:TitleForActionType(type) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [APP_DELEGATE handleActionForType:type];
        }]];
    }
    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(ALERT_CANCEL_TITLE_KEY, nil) style:UIAlertActionStyleCancel handler:nil]];
    return controller;
}

UIMenu *ActionListMenu(void) {
    NSMutableArray *actions = [NSMutableArray array];
    for (NSString *type in AvailableActions()) {
        [actions addObject:[UIAction actionWithTitle:TitleForActionType(type) image:nil identifier:nil handler:^(__kindof UIAction *action) {
            [APP_DELEGATE handleActionForType:type];
        }]];
    }
    return [UIMenu menuWithTitle:@"" children:actions];
}

#pragma once
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include "../TweakSettings-App/rootless.h"

static inline bool TSIsDopamine(void) {
    return access(ROOT_PATH("/.installed_dopamine"), F_OK) == 0 &&
           access(ROOT_PATH("/basebin/jbctl"), X_OK) == 0;
}

static inline bool TSIsKnownAction(const char *action) {
    if (!action) return false;
    const char *actions[] = {"respring", "safemode", "uicache", "ldrestart",
                             "reboot", "usreboot", "tweakinject"};
    for (unsigned i = 0; i < sizeof(actions) / sizeof(actions[0]); i++) {
        if (strcmp(action, actions[i]) == 0) return true;
    }
    return false;
}

static inline bool TSActionIsAvailable(const char *action) {
    if (!TSIsKnownAction(action)) return false;
    if (!strcmp(action, "usreboot") || !strcmp(action, "tweakinject")) return TSIsDopamine();
    if (!strcmp(action, "ldrestart")) return !TSIsDopamine() && access(ROOT_PATH("/usr/bin/ldrestart"), X_OK) == 0;
    if (!strcmp(action, "respring")) return TSIsDopamine() || access(ROOT_PATH("/usr/bin/sbreload"), X_OK) == 0 || access(ROOT_PATH("/usr/bin/killall"), X_OK) == 0;
    if (!strcmp(action, "safemode")) return access(ROOT_PATH("/usr/bin/killall"), X_OK) == 0;
    if (!strcmp(action, "uicache")) return access(ROOT_PATH("/usr/bin/uicache"), X_OK) == 0;
    return access(ROOT_PATH("/usr/sbin/reboot"), X_OK) == 0;
}

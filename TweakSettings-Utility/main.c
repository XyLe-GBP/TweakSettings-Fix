#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>
#include <unistd.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#if __has_include(<libproc.h>)
#include <libproc.h>
#else
// libproc is exported by libSystem on iOS, but omitted from Apple's public SDK.
#include <stdint.h>
#define PROC_PIDPATHINFO_MAXSIZE 4096
int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
#endif
#include "../Shared/TSUtilitySupport.h"

static int fail(const char *operation) {
    fprintf(stderr, "tweaksettings-utility: %s: %s\n", operation, strerror(errno));
    return EX_OSERR;
}

static bool authorized_parent(void) {
    char parentPath[PROC_PIDPATHINFO_MAXSIZE] = {0};
    char expectedPath[PATH_MAX], actualPath[PATH_MAX];
    struct stat expected, actual;
    if (proc_pidpath(getppid(), parentPath, sizeof(parentPath)) <= 0 ||
        !realpath(ROOT_PATH("/Applications/TweakSettings.app/TweakSettings"), expectedPath) ||
        !realpath(parentPath, actualPath) || strcmp(expectedPath, actualPath) != 0 ||
        stat(expectedPath, &expected) != 0 || stat(actualPath, &actual) != 0) return false;
    return S_ISREG(expected.st_mode) && expected.st_uid == 0 &&
           (expected.st_mode & (S_IWGRP | S_IWOTH)) == 0 &&
           expected.st_dev == actual.st_dev && expected.st_ino == actual.st_ino;
}

static int execute(const char *path, const char *argument, const char *secondArgument) {
    char *args[] = {(char *)path, (char *)argument, (char *)secondArgument, NULL};
    // Do not pass the caller's PATH, shell startup settings, or DYLD variables to root tools.
    char *environment[] = {"PATH=/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                           "HOME=/var/root", "LANG=C", NULL};
    execve(path, args, environment);
    return fail(path);
}

static int toggle_injection(void) {
    const char *path = ROOT_PATH("/basebin/.safe_mode");
    struct stat info;
    bool wasDisabled = lstat(path, &info) == 0;
    if (wasDisabled) {
        if (!S_ISREG(info.st_mode)) {
            fprintf(stderr, "tweaksettings-utility: invalid safe-mode marker\n");
            return EX_DATAERR;
        }
        if (unlink(path) != 0) return fail("enable tweak injection");
    } else {
        if (errno != ENOENT) return fail("read tweak injection state");
        int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0644);
        if (fd < 0) return fail("disable tweak injection");
        if (close(fd) != 0) return fail("close safe-mode marker");
    }
    // This is Dopamine's own userspace-reboot entry point.
    return execute(ROOT_PATH("/basebin/jbctl"), "reboot_userspace", NULL);
}

int main(int argc, char **argv) {
    if (argc == 1 || (argc == 2 && strcmp(argv[1], "--help") == 0)) {
        puts("tweaksettings-utility: --respring --safemode --uicache --ldrestart --reboot --usreboot --tweakinject");
        return EX_OK;
    }
    if (argc != 2 || strncmp(argv[1], "--", 2) != 0 || !TSIsKnownAction(argv[1] + 2)) {
        fputs("tweaksettings-utility: invalid action\n", stderr);
        return EX_USAGE;
    }
    if (!authorized_parent()) {
        fputs("tweaksettings-utility: only the installed TweakSettings app may request actions\n", stderr);
        return EX_NOPERM;
    }
    if (geteuid() != 0 || setgroups(0, NULL) != 0 || setgid(0) != 0 || setuid(0) != 0) {
        fputs("tweaksettings-utility: cannot obtain root credentials; reinstall the package\n", stderr);
        return EX_NOPERM;
    }
    umask(022);
    const char *action = argv[1] + 2;
    if (!TSActionIsAvailable(action)) {
        fputs("tweaksettings-utility: action unavailable on this jailbreak\n", stderr);
        return EX_UNAVAILABLE;
    }
    if (!strcmp(action, "respring")) {
        if (TSIsDopamine()) return execute(ROOT_PATH("/basebin/jbctl"), "respring", NULL);
        if (access(ROOT_PATH("/usr/bin/sbreload"), X_OK) == 0) return execute(ROOT_PATH("/usr/bin/sbreload"), NULL, NULL);
        return execute(ROOT_PATH("/usr/bin/killall"), "backboardd", NULL);
    }
    if (!strcmp(action, "safemode")) return execute(ROOT_PATH("/usr/bin/killall"), "-SEGV", "SpringBoard");
    if (!strcmp(action, "uicache")) return execute(ROOT_PATH("/usr/bin/uicache"), "-a", NULL);
    if (!strcmp(action, "reboot")) return execute(ROOT_PATH("/usr/sbin/reboot"), NULL, NULL);
    if (!strcmp(action, "ldrestart")) return execute(ROOT_PATH("/usr/bin/ldrestart"), NULL, NULL);
    if (!strcmp(action, "usreboot")) return execute(ROOT_PATH("/basebin/jbctl"), "reboot_userspace", NULL);
    return toggle_injection();
}

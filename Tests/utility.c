// Exercise the real helper with mocked OS calls. No root tools are executed.
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>
#include <unistd.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <libproc.h>
#include <assert.h>
#include <stdbool.h>
#include "../TweakSettings-App/rootless.h"

static bool dopamine = true, parentValid = true, marker = false, markerSymlink = false;
static bool credentialFailure = false, writeFailure = false;
static uid_t effectiveUID = 0, ownerUID = 0;
static mode_t executableMode = S_IFREG | 0755;
static int execCount;
static char lastPath[PATH_MAX], lastArg[80], lastArg2[80];

char *libroot_dyn_jbrootpath(const char *path, char *resolved) {
    strlcpy(resolved, path, PATH_MAX);
    return resolved;
}
static int mock_access(const char *path, int mode) {
    (void)mode;
    if (strstr(path, "installed_dopamine") || strstr(path, "/basebin/jbctl")) return dopamine ? 0 : -1;
    return 0;
}
static int mock_proc_pidpath(int pid, void *buffer, uint32_t size) {
    (void)pid;
    return (int)strlcpy(buffer, parentValid ? "/private/preboot/test/Applications/TweakSettings.app/TweakSettings" : "/bin/sh", size);
}
static char *mock_realpath(const char *path, char *resolved) {
    // Model /var/jb resolving to the same executable under preboot.
    strlcpy(resolved, strstr(path, "TweakSettings.app") ? "/private/preboot/test/Applications/TweakSettings.app/TweakSettings" : path, PATH_MAX);
    return resolved;
}
static int mock_stat(const char *path, struct stat *info) {
    (void)path;
    memset(info, 0, sizeof(*info));
    info->st_mode = executableMode;
    info->st_uid = ownerUID;
    info->st_ino = 1;
    info->st_dev = 1;
    return 0;
}
static int mock_lstat(const char *path, struct stat *info) {
    (void)path;
    if (!marker) { errno = ENOENT; return -1; }
    memset(info, 0, sizeof(*info));
    info->st_mode = markerSymlink ? S_IFLNK | 0644 : S_IFREG | 0644;
    return 0;
}
static int mock_open(const char *path, int flags, ...) {
    (void)path;
    assert((flags & (O_EXCL | O_NOFOLLOW)) == (O_EXCL | O_NOFOLLOW));
    if (writeFailure) { errno = EACCES; return -1; }
    marker = true;
    return 42;
}
static int mock_unlink(const char *path) {
    (void)path;
    if (writeFailure) { errno = EACCES; return -1; }
    marker = false;
    return 0;
}
static int mock_close(int fd) { assert(fd == 42); return 0; }
static uid_t mock_geteuid(void) { return effectiveUID; }
static int mock_setgroups(int count, const gid_t *groups) { (void)count; (void)groups; return credentialFailure ? -1 : 0; }
static int mock_setgid(gid_t gid) { assert(gid == 0); return 0; }
static int mock_setuid(uid_t uid) { assert(uid == 0); return 0; }
static mode_t mock_umask(mode_t mask) { assert(mask == 022); return 022; }
static int mock_execve(const char *path, char *const args[], char *const env[]) {
    execCount++;
    strlcpy(lastPath, path, sizeof(lastPath));
    strlcpy(lastArg, args[1] ?: "", sizeof(lastArg));
    strlcpy(lastArg2, args[1] && args[2] ? args[2] : "", sizeof(lastArg2));
    assert(strcmp(env[1], "HOME=/var/root") == 0);
    assert(env[3] == NULL);
    errno = ENOENT;
    return -1;
}
#define access mock_access
#define proc_pidpath mock_proc_pidpath
#define realpath mock_realpath
#define stat(path, info) mock_stat(path, info)
#define lstat mock_lstat
#define open mock_open
#define close mock_close
#define unlink mock_unlink
#define geteuid mock_geteuid
#define setgroups mock_setgroups
#define setgid mock_setgid
#define setuid mock_setuid
#define umask mock_umask
#define execve mock_execve
#define main utility_main
#include "../TweakSettings-Utility/main.c"
#undef main

static int run(const char *action) {
    char *args[] = {"tweaksettings-utility", (char *)action, NULL};
    return utility_main(action ? 2 : 1, args);
}
int main(void) {
    assert(run(NULL) == EX_OK);
    assert(run("--help") == EX_OK);
    assert(run("--unknown") == EX_USAGE);
    assert(run("--respring;echo bad") == EX_USAGE);
    assert(run("--") == EX_USAGE);
    assert(run("respring") == EX_USAGE);
    assert(execCount == 0);
    parentValid = false; assert(run("--respring") == EX_NOPERM); parentValid = true;
    ownerUID = 501; assert(run("--respring") == EX_NOPERM); ownerUID = 0;
    executableMode |= S_IWOTH; assert(run("--respring") == EX_NOPERM); executableMode &= ~S_IWOTH;
    effectiveUID = 501; assert(run("--respring") == EX_NOPERM); effectiveUID = 0;
    credentialFailure = true; assert(run("--respring") == EX_NOPERM); credentialFailure = false;
    assert(execCount == 0);
    assert(run("--respring") == EX_OSERR);
    assert(!strcmp(lastPath, "/basebin/jbctl") && !strcmp(lastArg, "respring"));
    assert(run("--usreboot") == EX_OSERR && !strcmp(lastArg, "reboot_userspace"));
    assert(run("--safemode") == EX_OSERR && !strcmp(lastArg, "-SEGV") && !strcmp(lastArg2, "SpringBoard"));
    assert(run("--uicache") == EX_OSERR && !strcmp(lastArg, "-a"));
    assert(run("--ldrestart") == EX_UNAVAILABLE);
    assert(run("--tweakinject") == EX_OSERR && marker);
    assert(run("--tweakinject") == EX_OSERR && !marker);
    int before = execCount;
    writeFailure = true; assert(run("--tweakinject") == EX_OSERR && !marker); writeFailure = false;
    marker = markerSymlink = true; assert(run("--tweakinject") == EX_DATAERR);
    marker = markerSymlink = false;
    assert(execCount == before);
    dopamine = false;
    assert(run("--usreboot") == EX_UNAVAILABLE);
    assert(run("--tweakinject") == EX_UNAVAILABLE);
    assert(!TSActionIsAvailable("--respring"));
    assert(!TSIsKnownAction(NULL));
    puts("Helper authorization, action dispatch, permissions and failure handling: passed");
}

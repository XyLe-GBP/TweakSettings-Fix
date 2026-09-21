#pragma once

// Resolve the runtime jailbreak root, including Dopamine's preboot root.
#include <libroot.h>
#define ROOT_PATH(path) JBROOT_PATH_CSTRING(path)
#define ROOT_PATH_VAR(path) JBROOT_PATH_CSTRING(path)
#define ROOT_PATH_NS(path) JBROOT_PATH_NSSTRING(path)
#define ROOT_PATH_NS_VAR(path) JBROOT_PATH_NSSTRING(path)

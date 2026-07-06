#include "rea/builtins/thread.h"

#include "backend_ast/builtin.h"
#include "backend_ast/thread_wrappers.h"

void reaRegisterThreadBuiltins(void) {
    registerVmBuiltin("thread_spawn_named", builtinThreadSpawnNamedWrapper,
                      BUILTIN_TYPE_FUNCTION, "thread_spawn_named", FX_PROC);
    registerVmBuiltin("thread_pool_submit", builtinThreadPoolSubmitWrapper,
                      BUILTIN_TYPE_FUNCTION, "thread_pool_submit", FX_PROC);
    registerVmBuiltin("thread_set_name", vmBuiltinThreadSetName,
                      BUILTIN_TYPE_FUNCTION, "thread_set_name", FX_PROC);
    registerVmBuiltin("thread_lookup", vmBuiltinThreadLookup,
                      BUILTIN_TYPE_FUNCTION, "thread_lookup", FX_PROC);
    registerVmBuiltin("thread_pause", vmBuiltinThreadPause,
                      BUILTIN_TYPE_FUNCTION, "thread_pause", FX_PROC);
    registerVmBuiltin("thread_resume", vmBuiltinThreadResume,
                      BUILTIN_TYPE_FUNCTION, "thread_resume", FX_PROC);
    registerVmBuiltin("thread_cancel", vmBuiltinThreadCancel,
                      BUILTIN_TYPE_FUNCTION, "thread_cancel", FX_PROC);
    registerVmBuiltin("thread_get_result", vmBuiltinThreadGetResult,
                      BUILTIN_TYPE_FUNCTION, "thread_get_result", FX_PROC);
    registerVmBuiltin("thread_get_status", vmBuiltinThreadGetStatus,
                      BUILTIN_TYPE_FUNCTION, "thread_get_status", FX_PROC);
    registerVmBuiltin("thread_stats", vmBuiltinThreadStats,
                      BUILTIN_TYPE_FUNCTION, "thread_stats", FX_PROC);
}

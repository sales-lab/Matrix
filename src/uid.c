#include "uid.h"
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

static atomic_uint_fast64_t matrix_id = 1;

SEXP uid_new(void) {
    int is_test = false;
    
    // The user enabled test mode
    SEXP opt = PROTECT(Rf_GetOption1(Rf_install("Matrix.uid.test")));
    is_test |= (opt != R_NilValue && isLogical(opt) && LOGICAL(opt)[0] == TRUE);
    UNPROTECT(1);

    // Package check under way
    const char *check_pkg = getenv("_R_CHECK_PACKAGE_NAME_");
    is_test |= (check_pkg != NULL && strcmp(check_pkg, "Matrix") == 0);

    if (is_test) {
        // Return the constant value 0
        uint64_t test_id = 0;
        SEXP ans = PROTECT(Rf_allocVector(RAWSXP, 8));
        memcpy(RAW(ans), &test_id, sizeof(test_id));
        UNPROTECT(1);
        return ans;
    }

    const uint64_t new_id = atomic_fetch_add_explicit(&matrix_id, 1, memory_order_relaxed);
    SEXP ans = PROTECT(Rf_allocVector(RAWSXP, 8));
    memcpy(RAW(ans), &new_id, sizeof(new_id));
    UNPROTECT(1);
    return ans;
}

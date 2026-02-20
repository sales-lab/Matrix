#include "tracing.h"
#include <unistd.h>

static tracing_state_t tracing_state;

static _Thread_local execution_context_t *current_context = NULL;

SEXP tracing_init(SEXP filepath_sexp) {
    if (TYPEOF(filepath_sexp) != STRSXP || Rf_length(filepath_sexp) == 0) {
        error("filepath must be a non-empty character string");
    }

    atomic_store(&tracing_state.global_clock, 0);
    tracing_state.main_thread_id = thrd_current();
    tracing_state.last_pid = getpid();

    mtx_init(&tracing_state.lock, mtx_plain);
    const char *filepath = CHAR(STRING_ELT(filepath_sexp, 0));
    tracing_state.filepath = strdup(filepath);
    tracing_state.log_file = fopen(filepath, "ab");

    return R_NilValue;
}

SEXP tracing_shutdown(void) {
    if (tracing_state.log_file != NULL) {
        fclose(tracing_state.log_file);
        tracing_state.log_file = NULL;
    }
    free(tracing_state.filepath);
    mtx_destroy(&tracing_state.lock);
    return R_NilValue;
}

static execution_context_t *tracing_get_context(void) {
    if (current_context == NULL) {
        current_context = malloc(sizeof(execution_context_t));
        if (current_context == NULL) {
            error("Failed to allocate memory for execution context");
        }

        current_context->active_span_id = 0;
        current_context->root_span_id = 0;
        current_context->depth = 0;
        current_context->is_main_thread = (thrd_current() == tracing_state.main_thread_id);
        uint64_t seed = (uint64_t)thrd_current() ^ (uint64_t)current_context;
        current_context->prng_state = seed;
    }
    return current_context;
}

static void tracing_reinit(pid_t pid) {
    mtx_lock(&tracing_state.lock);
    if (pid != tracing_state.last_pid) {
        tracing_state.last_pid = pid;
        if (tracing_state.log_file != NULL) {
            fclose(tracing_state.log_file);
            tracing_state.log_file = fopen(tracing_state.filepath, "ab");
        }
    }
    mtx_unlock(&tracing_state.lock);
}

static void tracing_write_record(const span_scope_t *scope, uint8_t type, const void *payload, uint32_t size) {
    if (tracing_state.log_file == NULL) {
        return;
    }

    uint64_t gsn = atomic_fetch_add(&tracing_state.global_clock, 1);

    pid_t current_pid = getpid();
    if (current_pid != tracing_state.last_pid) {
        tracing_reinit(current_pid);
    }

    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    uint64_t timestamp = (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;

    uint32_t thread_id = (uint32_t)thrd_current();

    record_header_t header = {
        gsn,
        timestamp,
        thread_id,
        scope->this_span_id,
        scope->prev_span_id,
        type,
        size
    };

    mtx_lock(&tracing_state.lock);

    fwrite(&header, sizeof(record_header_t), 1, tracing_state.log_file);
    fwrite(payload, size, 1, tracing_state.log_file);
    fflush(tracing_state.log_file);

    mtx_unlock(&tracing_state.lock);
}

span_scope_t tracing_start_span_c(const char *op_name, const char *call_site) {
    execution_context_t *ctx = tracing_get_context();
    span_scope_t scope;
    scope.prev_span_id = ctx->active_span_id;
    scope.depth = ctx->depth;
    ctx->depth++;

    uint64_t x = ctx->prng_state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    ctx->prng_state = x;
    scope.this_span_id = x;
    ctx->active_span_id = scope.this_span_id;

    size_t op_name_len = (op_name != NULL) ? strlen(op_name) : 0;
    size_t call_site_len = (call_site != NULL) ? strlen(call_site) : 0;
    size_t payload_size = op_name_len + 1 + call_site_len;

    char *payload = NULL;
    if (payload_size > 0) {
        payload = R_alloc(payload_size, 1);
        if (op_name != NULL) {
            strcpy(payload, op_name);
        }
        if (call_site != NULL) {
            strcpy(payload + op_name_len + 1, call_site);
        }
    }

    tracing_write_record(&scope, EVENT_TYPE_START, payload, (uint32_t)payload_size);

    return scope;
}

void tracing_end_span_c(span_scope_t scope) {
    execution_context_t *ctx = tracing_get_context();

    if (scope.depth != ctx->depth) {
        ctx->depth = scope.depth;
    }

    tracing_write_record(&scope, EVENT_TYPE_END, NULL, 0);
    ctx->active_span_id = scope.prev_span_id;
}

SEXP tracing_start_span_r(SEXP op_name, SEXP call_site) {
    const char *op_name_str = NULL;
    const char *call_site_str = NULL;

    if (TYPEOF(op_name) == STRSXP && Rf_length(op_name) > 0) {
        op_name_str = CHAR(STRING_ELT(op_name, 0));
    }

    if (TYPEOF(call_site) == STRSXP && Rf_length(call_site) > 0) {
        call_site_str = CHAR(STRING_ELT(call_site, 0));
    }

    span_scope_t scope = tracing_start_span_c(op_name_str, call_site_str);

    SEXP result = PROTECT(Rf_allocVector(RAWSXP, sizeof(span_scope_t)));
    memcpy(RAW(result), &scope, sizeof(span_scope_t));
    UNPROTECT(1);
    return result;
}

SEXP tracing_end_span_r(SEXP scope) {
    if (TYPEOF(scope) != RAWSXP || Rf_length(scope) != sizeof(span_scope_t)) {
        error("scope must be a raw vector of length %zu", sizeof(span_scope_t));
    }

    span_scope_t *scope_ptr = (span_scope_t *)RAW(scope);
    tracing_end_span_c(*scope_ptr);

    return R_NilValue;
}

static void extract_uid(SEXP matrix_sexp, uint64_t *uid_out) {
    SEXP uid_slot = PROTECT(GET_SLOT(matrix_sexp, Matrix_uidSym));
    if (TYPEOF(uid_slot) != RAWSXP || Rf_length(uid_slot) != 8) {
        error("uid slot must be a length-8 raw vector");
    }
    memcpy(uid_out, RAW(uid_slot), sizeof(uint64_t));
    UNPROTECT(1);
}

SEXP tracing_log_operation(SEXP scope, SEXP input_matrices, SEXP output_matrices) {
    if (TYPEOF(scope) != RAWSXP || Rf_length(scope) != sizeof(span_scope_t)) {
        error("scope must be a raw vector of length %zu", sizeof(span_scope_t));
    }

    span_scope_t *scope_ptr = (span_scope_t *)RAW(scope);

    if (TYPEOF(input_matrices) != VECSXP) {
        error("input_matrices must be a list");
    }

    size_t input_count = Rf_length(input_matrices);
    if (input_count == 0) {
        error("input_matrices must contain at least one matrix");
    }

    uint64_t *input_uids = malloc(sizeof(uint64_t) * input_count);
    if (input_uids == NULL) {
        error("failed to allocate memory for input UIDs");
    }

    for (size_t i = 0; i < input_count; i++) {
        extract_uid(VECTOR_ELT(input_matrices, i), &input_uids[i]);
    }

    size_t output_count = 0;
    uint64_t *output_uids = NULL;
    if (output_matrices != R_NilValue) {
        if (TYPEOF(output_matrices) != VECSXP) {
            free(input_uids);
            error("output_matrices must be a list or NULL");
        }
        output_count = Rf_length(output_matrices);
        if (output_count > 0) {
            output_uids = malloc(sizeof(uint64_t) * output_count);
            if (output_uids == NULL) {
                free(input_uids);
                error("failed to allocate memory for output UIDs");
            }
            for (size_t i = 0; i < output_count; i++) {
                extract_uid(VECTOR_ELT(output_matrices, i), &output_uids[i]);
            }
        }
    }

    uint32_t payload_size = sizeof(uint64_t) * input_count + sizeof(uint32_t) + sizeof(uint64_t) * output_count;

    uint8_t *payload = malloc(payload_size);
    if (payload == NULL) {
        free(input_uids);
        if (output_uids != NULL) free(output_uids);
        error("failed to allocate memory for payload");
    }

    uint8_t *ptr = payload;

    memcpy(ptr, input_uids, sizeof(uint64_t) * input_count);
    ptr += sizeof(uint64_t) * input_count;

    memcpy(ptr, &output_count, sizeof(uint32_t));
    ptr += sizeof(uint32_t);

    if (output_uids != NULL && output_count > 0) {
        memcpy(ptr, output_uids, sizeof(uint64_t) * output_count);
    }

    free(input_uids);
    if (output_uids != NULL) free(output_uids);

    tracing_write_record(scope_ptr, EVENT_TYPE_OPERATION, payload, payload_size);
    free(payload);

    return R_NilValue;
}

void tracing_scope_add_input(tracing_scope_t *ts, SEXP matrix) {
    if (!IS_S4_OBJECT(matrix)) return;
    if (ts->input_count >= MAX_TRACING_INPUTS) return;

    SEXP uid_slot = PROTECT(GET_SLOT(matrix, Matrix_uidSym));
    if (TYPEOF(uid_slot) != RAWSXP || Rf_length(uid_slot) != 8) {
        UNPROTECT(1);
        return;
    }
    memcpy(&ts->input_uids[ts->input_count++], RAW(uid_slot), sizeof(uint64_t));
    UNPROTECT(1);
}

void tracing_scope_add_output(tracing_scope_t *ts, SEXP matrix) {
    if (!IS_S4_OBJECT(matrix)) {
        return;
    }

    if (ts->output_count >= MAX_TRACING_OUTPUTS) {
        return;
    }

    SEXP uid_slot = PROTECT(GET_SLOT(matrix, Matrix_uidSym));
    if (TYPEOF(uid_slot) != RAWSXP || Rf_length(uid_slot) != 8) {
        UNPROTECT(1);
        return;
    }
    memcpy(&ts->output_uids[ts->output_count++], RAW(uid_slot), sizeof(uint64_t));
    UNPROTECT(1);
}

void tracing_scope_log(tracing_scope_t *ts) {
    if (ts->logged) return;
    ts->logged = true;

    if (ts->input_count == 0) {
        return;
    }

    if (ts->output_count == 0) {
        return;
    }

    uint32_t payload_size = sizeof(uint64_t) * ts->input_count + sizeof(uint32_t) + sizeof(uint64_t) * ts->output_count;
    uint8_t payload[payload_size];

    uint8_t *ptr = payload;

    memcpy(ptr, ts->input_uids, sizeof(uint64_t) * ts->input_count);
    ptr += sizeof(uint64_t) * ts->input_count;

    uint32_t output_count = (uint32_t)ts->output_count;
    memcpy(ptr, &output_count, sizeof(uint32_t));
    ptr += sizeof(uint32_t);

    memcpy(ptr, ts->output_uids, sizeof(uint64_t) * ts->output_count);

    tracing_write_record(&ts->scope, EVENT_TYPE_OPERATION, payload, payload_size);
}

void tracing_scope_cleanup(tracing_scope_t *ts) {
    if (!ts->logged) {
        tracing_scope_log(ts);
    }
    tracing_end_span_c(ts->scope);
}

int tracing_is_enabled(void) {
    return (tracing_state.log_file != NULL) ? 1 : 0;
}

SEXP tracing_log_new_object(SEXP class_name, SEXP uid_sexp) {
    if (TYPEOF(class_name) != STRSXP || Rf_length(class_name) != 1) {
        error("class_name must be a single character string");
    }
    
    if (TYPEOF(uid_sexp) != RAWSXP || Rf_length(uid_sexp) != 8) {
        error("uid must be a length-8 raw vector");
    }
    
    const char *class_str = CHAR(STRING_ELT(class_name, 0));
    size_t class_len = strlen(class_str);
    
    uint32_t payload_size = sizeof(uint64_t) + sizeof(uint32_t) + class_len;
    uint8_t *payload = malloc(payload_size);
    if (payload == NULL) {
        error("failed to allocate memory for payload");
    }
    
    uint8_t *ptr = payload;
    
    memcpy(ptr, RAW(uid_sexp), sizeof(uint64_t));
    ptr += sizeof(uint64_t);
    
    memcpy(ptr, &class_len, sizeof(uint32_t));
    ptr += sizeof(uint32_t);
    
    memcpy(ptr, class_str, class_len);
    
    execution_context_t *ctx = tracing_get_context();
    span_scope_t scope = {
        .this_span_id = ctx->active_span_id,
        .prev_span_id = ctx->root_span_id,
        .depth = ctx->depth
    };
    tracing_write_record(&scope, EVENT_TYPE_NEW_OBJECT, payload, payload_size);
    
    free(payload);
    return R_NilValue;
}

SEXP tracing_log_metadata(SEXP uid_sexp, SEXP nrow, SEXP ncol, SEXP nnz) {
    if (TYPEOF(uid_sexp) != RAWSXP || Rf_length(uid_sexp) != 8) {
        error("uid must be a length-8 raw vector");
    }
    
    if (TYPEOF(nrow) != INTSXP || Rf_length(nrow) != 1) {
        error("nrow must be a single integer");
    }
    
    if (TYPEOF(ncol) != INTSXP || Rf_length(ncol) != 1) {
        error("ncol must be a single integer");
    }
    
    if (TYPEOF(nnz) != INTSXP || Rf_length(nnz) != 1) {
        error("nnz must be a single integer");
    }
    
    uint32_t payload_size = sizeof(uint64_t) + 3 * sizeof(uint64_t);
    uint8_t *payload = malloc(payload_size);
    if (payload == NULL) {
        error("failed to allocate memory for payload");
    }
    
    uint8_t *ptr = payload;
    
    memcpy(ptr, RAW(uid_sexp), sizeof(uint64_t));
    ptr += sizeof(uint64_t);
    
    uint64_t nr = (uint64_t)INTEGER(nrow)[0];
    uint64_t nc = (uint64_t)INTEGER(ncol)[0];
    uint64_t nz = (uint64_t)INTEGER(nnz)[0];
    
    memcpy(ptr, &nr, sizeof(uint64_t));
    ptr += sizeof(uint64_t);
    
    memcpy(ptr, &nc, sizeof(uint64_t));
    ptr += sizeof(uint64_t);
    
    memcpy(ptr, &nz, sizeof(uint64_t));
    
    static span_scope_t dummy_scope = {0, 0, 0};
    tracing_write_record(&dummy_scope, EVENT_TYPE_METADATA, payload, payload_size);
    
    free(payload);
    return R_NilValue;
}

SEXP tracing_log_subscript(SEXP scope_sexp, SEXP input_uid_sexp, SEXP row_indices_sexp, SEXP col_indices_sexp) {
    if (TYPEOF(scope_sexp) != RAWSXP || Rf_length(scope_sexp) != sizeof(span_scope_t)) {
        error("scope must be a raw vector of length %zu", sizeof(span_scope_t));
    }
    
    if (TYPEOF(input_uid_sexp) != RAWSXP || Rf_length(input_uid_sexp) != 8) {
        error("input_uid must be a length-8 raw vector");
    }
    
    if (TYPEOF(row_indices_sexp) != INTSXP) {
        error("row_indices must be an integer vector");
    }
    
    if (TYPEOF(col_indices_sexp) != INTSXP) {
        error("col_indices must be an integer vector");
    }
    
    span_scope_t *scope_ptr = (span_scope_t *)RAW(scope_sexp);
    
    uint64_t input_uid;
    memcpy(&input_uid, RAW(input_uid_sexp), sizeof(uint64_t));
    
    int row_count = Rf_length(row_indices_sexp);
    int col_count = Rf_length(col_indices_sexp);
    
    uint32_t payload_size = sizeof(uint64_t) + sizeof(uint32_t) + sizeof(uint32_t) +
                            sizeof(uint32_t) * row_count + sizeof(uint32_t) * col_count;
    uint8_t *payload = malloc(payload_size);
    if (payload == NULL) {
        error("failed to allocate memory for payload");
    }
    
    uint8_t *ptr = payload;
    
    memcpy(ptr, &input_uid, sizeof(uint64_t));
    ptr += sizeof(uint64_t);
    
    memcpy(ptr, &row_count, sizeof(uint32_t));
    ptr += sizeof(uint32_t);
    
    for (int i = 0; i < row_count; i++) {
        int row_val = INTEGER(row_indices_sexp)[i];
        memcpy(ptr, &row_val, sizeof(uint32_t));
        ptr += sizeof(uint32_t);
    }
    
    memcpy(ptr, &col_count, sizeof(uint32_t));
    ptr += sizeof(uint32_t);
    
    for (int i = 0; i < col_count; i++) {
        int col_val = INTEGER(col_indices_sexp)[i];
        memcpy(ptr, &col_val, sizeof(uint32_t));
        ptr += sizeof(uint32_t);
    }
    
    tracing_write_record(scope_ptr, EVENT_TYPE_SUBSCRIPT, payload, payload_size);
    
    free(payload);
    return R_NilValue;
}


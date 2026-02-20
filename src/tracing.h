#ifndef MATRIX_TRACING_H
#define MATRIX_TRACING_H

#include <stdio.h>
#include <string.h>
#include <threads.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <Rinternals.h>
#include "Mdefines.h"

#define __stringify(x) #x
#define __xstringify(x) __stringify(x)

typedef struct {
    atomic_uint_fast64_t global_clock;
    mtx_t lock;
    thrd_t main_thread_id;
    pid_t last_pid;
    char *filepath;
    FILE *log_file;
} tracing_state_t;

typedef struct {
    uint64_t active_span_id;
    uint64_t root_span_id;
    uint32_t depth;
    bool is_main_thread;
    uint64_t prng_state;
} execution_context_t;

typedef struct {
    uint64_t this_span_id;
    uint64_t prev_span_id;
    uint32_t depth;
} span_scope_t;

#pragma pack(push, 1)
typedef struct {
    uint64_t gsn;
    uint64_t timestamp;
    uint32_t thread_id;
    uint64_t span_id;
    uint64_t parent_id;
    uint8_t event_type;
    uint32_t payload_size;
} record_header_t;
#pragma pack(pop)

#define MAX_TRACING_INPUTS 32
#define MAX_TRACING_OUTPUTS 32

typedef struct {
    span_scope_t scope;
    uint64_t input_uids[MAX_TRACING_INPUTS];
    size_t input_count;
    uint64_t output_uids[MAX_TRACING_OUTPUTS];
    size_t output_count;
    bool logged;
} tracing_scope_t;

extern SEXP Matrix_uidSym;

#define EVENT_TYPE_START 0
#define EVENT_TYPE_END 1
#define EVENT_TYPE_NEW_OBJECT 2
#define EVENT_TYPE_METADATA 3
#define EVENT_TYPE_OPERATION 4
#define EVENT_TYPE_SUBSCRIPT 5

SEXP tracing_init(SEXP filepath);
span_scope_t tracing_start_span_c(const char *op_name, const char *call_site);
void tracing_end_span_c(span_scope_t scope);
SEXP tracing_start_span_r(SEXP op_name, SEXP call_site);
SEXP tracing_end_span_r(SEXP scope);
SEXP tracing_log_new_object(SEXP class_name, SEXP uid_sexp);
SEXP tracing_log_metadata(SEXP uid_sexp, SEXP nrow, SEXP ncol, SEXP nnz);
SEXP tracing_log_operation(SEXP scope, SEXP input_matrices, SEXP output_matrices);
SEXP tracing_log_subscript(SEXP scope, SEXP input_uid, SEXP row_indices, SEXP col_indices);
SEXP tracing_shutdown(void);
int tracing_is_enabled(void);

void tracing_scope_add_input(tracing_scope_t *ts, SEXP matrix);
void tracing_scope_add_output(tracing_scope_t *ts, SEXP matrix);
void tracing_scope_log(tracing_scope_t *ts);
void tracing_scope_cleanup(tracing_scope_t *ts);

#define TRACING_SETUP(func_name) \
    tracing_scope_t __attribute__((cleanup(tracing_scope_cleanup))) \
        _tracing_scope; \
    memset(&_tracing_scope, 0, sizeof(tracing_scope_t)); \
     _tracing_scope.scope = tracing_start_span_c(func_name, \
         __FILE__ ":" __xstringify(__LINE__))

#define TRACING_ADD_INPUT(obj) \
    tracing_scope_add_input(&_tracing_scope, (obj))

#define TRACING_ADD_OUTPUT(obj) \
    tracing_scope_add_output(&_tracing_scope, (obj))

#endif /* MATRIX_TRACING_H */

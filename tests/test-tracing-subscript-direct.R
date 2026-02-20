#!/usr/bin/env Rscript
library(Matrix)

log_file <- "tests/test-subscript-direct.log"

if (file.exists(log_file)) {
    invisible(file.remove(log_file))
}

enableMatrixTracing(log_file)

x <- Matrix(1:12, nrow=3, ncol=4)

cat("=== Test direct SUBSCRIPT event logging ===\n")

cat("Test 1: Scalar subscript (single element x[5])\n")
scope1 <- .Call("tracing_start_span_r", "subscript_scalar", "test.R:15")
uid1 <- x@uid
.Call("tracing_log_subscript", scope1, uid1, as.integer(5), integer(0))
.Call("tracing_end_span_r", scope1)

cat("Test 2: Vector subscript (row slice x[1:2, ])\n")
scope2 <- .Call("tracing_start_span_r", "subscript_vector", "test.R:19")
uid2 <- x@uid
.Call("tracing_log_subscript", scope2, uid2, 1:2, integer(0))
.Call("tracing_end_span_r", scope2)

cat("Test 3: 2D subscript (element x[1, 2])\n")
scope3 <- .Call("tracing_start_span_r", "subscript_element", "test.R:23")
uid3 <- x@uid
.Call("tracing_log_subscript", scope3, uid3, 1L, 2L)
.Call("tracing_end_span_r", scope3)

cat("Test 4: Full row and column slice x[1:2, 2:3]\n")
scope4 <- .Call("tracing_start_span_r", "subscript_slice", "test.R:27")
uid4 <- x@uid
.Call("tracing_log_subscript", scope4, uid4, 1:2, 2:3)
.Call("tracing_end_span_r", scope4)

disableMatrixTracing()

cat("\n=== Decoded log output ===\n")
system(paste0("python3 inst/scripts/tracing-decode.py ", log_file))

cat("\n=== Verification ===\n")
log_size <- file.size(log_file)[1]
cat("Log file size:", log_size, "bytes\n")

success <- FALSE
if (log_size > 0) {
    cat("Log file created successfully\n")
    
    decoded_output <- system(paste0("python3 inst/scripts/tracing-decode.py ", log_file, " 2>&1"), intern=TRUE)
    subscript_events <- grep('"event_type": "subscript"', decoded_output)
    cat("SUBSCRIPT events found:", length(subscript_events), "\n")
    
    if (length(subscript_events) >= 4) {
        cat("SUCCESS: All SUBSCRIPT events logged correctly\n")
        success <- TRUE
    } else {
        cat("ERROR: Expected at least 4 SUBSCRIPT events, got", length(subscript_events), "\n")
    }
} else {
    cat("ERROR: Log file is empty\n")
}

if (file.exists(log_file)) {
    invisible(file.remove(log_file))
}

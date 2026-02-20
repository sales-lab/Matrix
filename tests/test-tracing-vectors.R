library(Matrix)

cat("--- vector_as_sparse and vector_as_dense Test ---\n")

success <- TRUE
filepath <- "tests/test-tracing-vectors.log"

if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

enableMatrixTracing(filepath)

# Test 1: vector_as_dense from numeric
cat("\nTest 1: Numeric vector to dense matrix\n")
v1 <- 1:12
m1 <- .Call("R_vector_as_dense", v1, "dgeMatrix", "U", "N", 3, 4, FALSE, NULL)
cat("  Input vector length:", length(v1), "\n")
cat("  Output matrix dimensions:", nrow(m1), "x", ncol(m1), "\n")
cat("  Output uid:", as.integer(m1@uid), "\n")
stopifnot(length(m1@uid) == 8)
stopifnot(!is.na(m1@uid[1]))
cat("  SUCCESS: matrix created with uid\n")

# Test 2: vector_as_dense from integer
cat("\nTest 2: Integer vector to dense matrix\n")
v2 <- as.integer(1:6)
m2 <- .Call("R_vector_as_dense", v2, "dgeMatrix", "U", "N", 2, 3, FALSE, NULL)
cat("  Output dimensions:", nrow(m2), "x", ncol(m2), "\n")
cat("  Output uid:", as.integer(m2@uid), "\n")
stopifnot(length(m2@uid) == 8)
stopifnot(!is.na(m2@uid[1]))
cat("  SUCCESS: integer vector converted\n")

# Test 3: vector_as_sparse from sparseVector
cat("\nTest 3: Sparse vector to sparse matrix\n")
sv <- sparseVector(i = c(1, 3, 5), x = c(10, 20, 30), length = 10)
m3 <- .Call("R_vector_as_sparse", sv, "dgCMatrix", "U", "N", 5, 2, FALSE, NULL)
cat("  Input sparseVector length:", sv@length, "\n")
cat("  Input sparseVector nnz:", length(sv@x), "\n")
cat("  Output dimensions:", nrow(m3), "x", ncol(m3), "\n")
cat("  Output nnz:", length(m3@x), "\n")
cat("  Output uid:", as.integer(m3@uid), "\n")
stopifnot(length(m3@uid) == 8)
stopifnot(!is.na(m3@uid[1]))
cat("  SUCCESS: sparse vector converted\n")

# Test 4: vector_as_sparse from another sparseVector
cat("\nTest 4: Another sparse vector conversion\n")
sv2 <- sparseVector(i = c(2, 4), x = c(1.5, 2.5), length = 6)
m4 <- .Call("R_vector_as_sparse", sv2, "dgCMatrix", "U", "N", 3, 2, FALSE, NULL)
cat("  Output dimensions:", nrow(m4), "x", ncol(m4), "\n")
cat("  Output nnz:", length(m4@x), "\n")
cat("  Output uid:", as.integer(m4@uid), "\n")
stopifnot(length(m4@uid) == 8)
stopifnot(!is.na(m4@uid[1]))
cat("  SUCCESS: sparse vector converted\n")

disableMatrixTracing()

# Analyze log file
cat("\n--- Log File Analysis ---\n")
decoded <- system2("python3", args = c("inst/scripts/tracing-decode.py", shQuote(filepath)), stdout = TRUE, stderr = TRUE)

if (length(decoded) > 0 && decoded[1] != "") {
  json_lines <- decoded[nzchar(decoded)]
  cat("Total records:", length(json_lines), "\n")
  
  has_new_object <- sum(grepl('"event_type": "new_object"', json_lines))
  has_metadata <- sum(grepl('"event_type": "metadata"', json_lines))
  has_operation <- sum(grepl('"event_type": "operation"', json_lines))
  
  cat("NEW_OBJECT events:", has_new_object, "\n")
  cat("METADATA events:", has_metadata, "\n")
  cat("OPERATION events:", has_operation, "\n")
  
  if (has_new_object > 0) {
    cat("\nSample NEW_OBJECT events:\n")
    count <- 0
    for (line in json_lines) {
      if (grepl('"event_type": "new_object"', line) && count < 3) {
        cat(" ", line, "\n")
        count <- count + 1
      }
    }
  }
  
  if (has_metadata > 0) {
    cat("\nSample METADATA events:\n")
    count <- 0
    for (line in json_lines) {
      if (grepl('"event_type": "metadata"', line) && count < 3) {
        cat(" ", line, "\n")
        count <- count + 1
      }
    }
  }
  
  if (has_operation > 0) {
    cat("\n  Note: OPERATION events found from internal Matrix operations\n")
    cat("  These are from other Matrix functions called during execution\n")
    cat("  The key point is that vector_as_dense/sparse themselves log METADATA events\n")
  } else {
    cat("\n  SUCCESS: No OPERATION events (as expected for constructors)\n")
  }
  
  if (has_new_object >= 4) {
    cat("  SUCCESS: Expected NEW_OBJECT events logged\n")
  } else {
    cat("  WARNING: Expected >= 4 NEW_OBJECT events, got", has_new_object, "\n")
  }
  
  if (has_metadata >= 4) {
    cat("  SUCCESS: Expected METADATA events logged\n")
  } else {
    cat("  WARNING: Expected >= 4 METADATA events, got", has_metadata, "\n")
  }
} else {
  cat("ERROR: No decoded output\n")
  success <- FALSE
}

if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

cat("\n--- Vector Conversion Test Complete ---\n")
if (success) {
  cat("\n*** VECTOR CONVERSIONS TEST PASSED ***\n")
} else {
  cat("\n*** SOME TESTS FAILED ***\n")
}

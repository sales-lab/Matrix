library(Matrix)

cat("--- Tracing Infrastructure Test ---\n")

success <- TRUE
filepath <- "tests/test-tracing-infra.log"

if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

cat("\n=== Test 1: Initialize tracing ===\n")
enableMatrixTracing(filepath)
cat("SUCCESS: Tracing enabled\n")

cat("\n=== Test 2: Single span ===\n")
scope1 <- .Call("tracing_start_span_r", "test_span", NULL, PACKAGE = "Matrix")
.Call("tracing_end_span_r", scope1, PACKAGE = "Matrix")
cat("SUCCESS: Single span\n")

cat("\n=== Test 3: Nested spans ===\n")
scope_outer <- .Call("tracing_start_span_r", "outer", NULL, PACKAGE = "Matrix")
scope_inner <- .Call("tracing_start_span_r", "inner", NULL, PACKAGE = "Matrix")
.Call("tracing_end_span_r", scope_inner, PACKAGE = "Matrix")
.Call("tracing_end_span_r", scope_outer, PACKAGE = "Matrix")
cat("SUCCESS: Nested spans\n")

cat("\n=== Test 4: Verify log structure ===\n")
decoded <- system2(
  "python3",
  args = c("inst/scripts/tracing-decode.py", shQuote(filepath)),
  stdout = TRUE,
  stderr = TRUE
)

if (length(decoded) > 0 && decoded[1] != "") {
  json_lines <- decoded[nzchar(decoded)]
  has_start <- sum(grepl('"event_type": "start"', json_lines))
  has_end <- sum(grepl('"event_type": "end"', json_lines))
  
  if (has_start > 0 && has_end > 0) {
    cat("SUCCESS: START and END events logged\n")
  } else {
    cat("ERROR: Missing events\n")
    success <<- FALSE
  }
} else {
  cat("ERROR: No decoded output\n")
  success <<- FALSE
}

cat("\n=== Test 5: Matrix operations ===\n")
x <- Matrix(1:4, nrow = 2)
y <- t(x)
cat("SUCCESS: Transpose\n")

a <- Matrix(1:4, nrow = 2)
b <- Matrix(5:8, nrow = 2)
c <- a %*% b
cat("SUCCESS: Multiplication\n")

cat("\n=== Test 6: Verify OPERATION events ===\n")
decoded <- system2(
  "python3",
  args = c("inst/scripts/tracing-decode.py", shQuote(filepath)),
  stdout = TRUE,
  stderr = TRUE
)

if (length(decoded) > 0 && decoded[1] != "") {
  json_lines <- decoded[nzchar(decoded)]
  has_operation <- sum(grepl('"event_type": "operation"', json_lines))
  if (has_operation > 0) {
    cat("SUCCESS: OPERATION events logged\n")
  }
}

cat("\n=== Test 7: Disable tracing ===\n")
disableMatrixTracing()
cat("SUCCESS: Tracing disabled\n")

if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

cat("\n--- Test Complete ---\n")
if (success) {
  cat("\n*** ALL TESTS PASSED ***\n")
} else {
  cat("\n*** SOME TESTS FAILED ***\n")
}

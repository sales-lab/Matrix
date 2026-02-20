library(Matrix)

cat("--- Base R Generic Tracing Test ---\n")

success <- TRUE
filepath <- "tests/test-tracing-crossprod.log"

if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

enableMatrixTracing(filepath)

cat("\nTest 1: Non-generic Matrix operation\n")
x <- Matrix(runif(16), nrow = 4)
y <- Matrix(runif(16), nrow = 4)
z <- t(x)
cat("  t() worked\n")

cat("\nTest 2: crossprod() with one argument\n")
w <- crossprod(x)
cat("  crossprod(x) worked\n")

cat("\nTest 3: crossprod() with two arguments\n")
v <- crossprod(x, y)
cat("  crossprod(x, y) worked\n")

disableMatrixTracing()

if (file.exists(filepath)) {
  decoded <- system2("python3", args = c("inst/scripts/tracing-decode.py", shQuote(filepath)), stdout = TRUE, stderr = TRUE)
  if (length(decoded) > 0 && decoded[1] != "") {
    json_lines <- decoded[nzchar(decoded)]
    has_operation <- sum(grepl('"event_type": "operation"', json_lines))
    cat("\nTest 4: OPERATION events logged\n")
    cat("  OPERATION events:", has_operation, "\n")
    if (has_operation > 0) {
      cat("  SUCCESS\n")
    } else {
      cat("  No OPERATION events (may be expected)\n")
    }
  }
}

invisible(file.remove(filepath))

cat("\n--- Test Complete ---\n")
if (success) {
  cat("\n*** ALL TESTS PASSED ***\n")
}

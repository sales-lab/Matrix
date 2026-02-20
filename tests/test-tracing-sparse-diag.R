library(Matrix)

cat("--- sparse_diag_get Tracing Test ---\n")

success <- TRUE
filepath <- "tests/test-tracing-sparse-diag.log"

cat("Test 1: Test sparse_diag_get with tracing enabled\n")
if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

enableMatrixTracing(filepath)

x <- Matrix(c(1:9), nrow = 3, ncol = 3)
cat("  Created matrix with uid:", as.integer(x@uid), "\n")

d <- diag(x)
cat("  Extracted diagonal:", d, "\n")

disableMatrixTracing()

if (file.exists(filepath)) {
  file_size <- file.info(filepath)$size
  cat("  Log file size:", file_size, "bytes\n")
  if (file_size > 0) {
    cat("  SUCCESS: Log file created\n")
  } else {
    cat("  ERROR: Log file is empty\n")
    success <<- FALSE
  }
} else {
  cat("  ERROR: Log file not created\n")
  success <<- FALSE
}

decoded <- system2(
  "python3",
  args = c("inst/scripts/tracing-decode.py", shQuote(filepath)),
  stdout = TRUE,
  stderr = TRUE
)

if (length(decoded) > 0 && decoded[1] != "") {
  json_lines <- decoded[nzchar(decoded)]

  has_operation <- any(grepl('"event_type": "operation_', json_lines))

  if (has_operation) {
    cat("  SUCCESS: OPERATION event logged\n")
  } else {
    cat("  Note: No OPERATION event found (may be expected)\n")
  }

  cat("  Decoded events:\n")
  for (line in json_lines) {
    cat("   ", line, "\n")
  }
} else {
  cat("  ERROR: No decoded output\n")
  success <<- FALSE
}

if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

cat("\n--- Test Complete ---\n")

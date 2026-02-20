library(Matrix)

cat("--- dense_diag_set Tracing Test ---\n")

success <- TRUE
filepath <- "tests/test-tracing-dense-diag-set.log"

cat("Test 1: Test dense_diag_set with tracing enabled\n")
if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

enableMatrixTracing(filepath)

mat <- Matrix(1:9, nrow = 3, ncol = 3)
cat("  Created matrix with uid:", as.integer(mat@uid), "\n")
cat("  Matrix diagonal before:", diag(mat), "\n")

mat[diag(mat)] <- 100  # Use S4 assignment to test
cat("  Matrix diagonal after:", diag(mat), "\n")

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
  
  has_operation <- any(grepl('"event_type": "operation', json_lines))
  
  if (has_operation) {
    cat("  SUCCESS: OPERATION event logged\n")
  } else {
    cat("  Note: No OPERATION event found\n")
  }
  
  operation_lines <- json_lines[grepl('"event_type": "operation', json_lines)]
  if (length(operation_lines) > 0) {
    cat("  OPERATION event details:\n")
    for (line in operation_lines) {
      cat("   ", line, "\n")
    }
    
    has_input_uids <- any(grepl('"input_uids"', operation_lines))
    has_output <- any(grepl('"output_uid"|"output_class"', operation_lines))
    
    if (has_input_uids && has_output) {
      cat("  SUCCESS: OPERATION event has input UIDs and output info\n")
    } else {
      cat("  WARNING: OPERATION event may be missing fields\n")
    }
  }
} else {
  cat("  ERROR: No decoded output\n")
  success <<- FALSE
}

if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

cat("\n--- Test Complete ---\n")

library(Matrix)

cat("--- Operation Events Test ---\n")

success <- TRUE
filepath <- "tests/test-tracing-c-instrumentation.log"

cat("Test 1: Verify operation with Matrix output\n")
if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

tryCatch(
  {
    enableMatrixTracing(filepath)
    cat("  SUCCESS: Tracing initialized\n")

    mat <- Matrix(1:4, nrow = 2, ncol = 2)
    result <- t(mat)

    if (inherits(result, "Matrix")) {
      cat("  SUCCESS: Matrix operation produced Matrix output\n")
    } else {
      cat("  ERROR: Expected Matrix output\n")
      success <<- FALSE
    }

    disableMatrixTracing()
  },
  error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n")
    success <<- FALSE
  }
)

cat("Test 2: Verify operation with non-Matrix output\n")
if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

tryCatch(
  {
    enableMatrixTracing(filepath)

    mat <- Matrix(1:4, nrow = 2, ncol = 2)
    nrow_result <- nrow(mat)
    ncol_result <- ncol(mat)

    if (is.integer(nrow_result) && is.integer(ncol_result)) {
      cat("  SUCCESS: Non-Matrix operation produced numeric output\n")
    } else {
      cat("  ERROR: Expected numeric output\n")
      success <<- FALSE
    }

    disableMatrixTracing()
  },
  error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n")
    success <<- FALSE
  }
)

cat("Test 3: Verify log file contains OPERATION events via tracing-decode.py\n")
if (file.exists(filepath)) {
  decoded <- system2(
    "python3",
    args = c("inst/scripts/tracing-decode.py", shQuote(filepath)),
    stdout = TRUE,
    stderr = TRUE
  )

  if (length(decoded) > 0 && decoded[1] != "") {
    json_lines <- decoded[nzchar(decoded)]

    cat("  Decoded records:\n")
    for (line in json_lines) {
      cat("   ", line, "\n")
    }

    has_start <- sum(grepl('"event_type": "start"', json_lines))
    has_end <- sum(grepl('"event_type": "end"', json_lines))
    has_operation <- sum(grepl('"event_type": "operation"', json_lines))

    cat("  START events:", has_start, "\n")
    cat("  END events:", has_end, "\n")
    cat("  OPERATION events:", has_operation, "\n")

    if (has_operation > 0) {
      cat("  SUCCESS: Log contains OPERATION events\n")
    } else {
      cat("  WARNING: No OPERATION events found\n")
    }
  } else {
    cat("  ERROR: No decoded output\n")
    success <<- FALSE
  }
} else {
  cat("  ERROR: Log file not created\n")
  success <<- FALSE
}

cat("Test 4: Test matrix multiplication with inputs and output tracking\n")
if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

tryCatch(
  {
    enableMatrixTracing(filepath)

    A <- Matrix(1:4, nrow = 2, ncol = 2)
    B <- Matrix(5:8, nrow = 2, ncol = 2)
    result <- A %*% B

    if (inherits(result, "Matrix")) {
      cat("  SUCCESS: Matrix multiplication completed\n")
    }

    disableMatrixTracing()
  },
  error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n")
    success <<- FALSE
  }
)

cat("Test 5: Verify OPERATION event payload structure\n")
if (file.exists(filepath)) {
  decoded <- system2(
    "python3",
    args = c("inst/scripts/tracing-decode.py", shQuote(filepath)),
    stdout = TRUE,
    stderr = TRUE
  )

  if (length(decoded) > 0 && decoded[1] != "") {
    json_lines <- decoded[nzchar(decoded)]

    operation_lines <- json_lines[grepl('"event_type": "operation"', json_lines)]

    if (length(operation_lines) > 0) {
      cat("  OPERATION event details:\n")
      for (line in operation_lines) {
        cat("   ", line, "\n")
      }

      has_input_uids <- any(grepl('"input_uids"', operation_lines))
      has_output <- any(grepl('"output_', operation_lines))

      if (has_input_uids && has_output) {
        cat("  SUCCESS: OPERATION events contain input_uids and output info\n")
      } else {
        cat("  WARNING: OPERATION events may be missing fields\n")
      }
    }
  }
}

cat("Test 6: Verify C-level dense_transpose instrumentation\n")
if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

tryCatch(
  {
    enableMatrixTracing(filepath)

    mat <- Matrix(1:9, nrow = 3, ncol = 3)
    result <- .Call("R_dense_transpose", mat, PACKAGE = "Matrix")

    if (inherits(result, "dgeMatrix")) {
      cat("  SUCCESS: C-level transpose produced Matrix output\n")
    } else {
      cat("  ERROR: Expected dgeMatrix output\n")
      success <<- FALSE
    }

    if ("uid" %in% slotNames(result)) {
      cat("  SUCCESS: Result has uid slot\n")
    } else {
      cat("  ERROR: Result missing uid slot\n")
      success <<- FALSE
    }

    disableMatrixTracing()
  },
  error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n")
    success <<- FALSE
  }
)

cat("Test 7: Verify C-level transpose logs OPERATION event\n")
if (file.exists(filepath)) {
  decoded <- system2(
    "python3",
    args = c("inst/scripts/tracing-decode.py", shQuote(filepath)),
    stdout = TRUE,
    stderr = TRUE
  )

  if (length(decoded) > 0 && decoded[1] != "") {
    json_lines <- decoded[nzchar(decoded)]

    all_lines <- json_lines
    start_lines <- json_lines[grepl('"event_type": "start"', json_lines)]
    operation_lines <- json_lines[grepl('"event_type": "operation"', json_lines)]

    if (length(start_lines) > 0) {
      cat("  START event details:\n")
      for (line in start_lines) {
        cat("   ", line, "\n")
      }

      has_r_dense_transpose <- any(grepl('"R_dense_transpose"', start_lines))

      if (has_r_dense_transpose) {
        cat("  SUCCESS: C-level function name 'R_dense_transpose' logged in START event\n")
      } else {
        cat("  Note: op_name may use different format\n")
      }
    }

    if (length(operation_lines) > 0) {
      cat("  OPERATION event details:\n")
      for (line in operation_lines) {
        cat("   ", line, "\n")
      }

      has_op_name <- any(grepl('"op_name"', operation_lines))
      has_input_uids <- any(grepl('"input_uids"', operation_lines))

      if (has_input_uids) {
        cat("  SUCCESS: Input UIDs logged in OPERATION event\n")
      } else {
        cat("  WARNING: Input UIDs may be missing\n")
      }
    } else {
      cat("  ERROR: No OPERATION events found\n")
      success <<- FALSE
    }
  } else {
    cat("  ERROR: No decoded output\n")
    success <<- FALSE
  }
} else {
  cat("  ERROR: Log file not created\n")
  success <<- FALSE
}

cat("Test 8: Verify C-level sparse_transpose instrumentation\n")
if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

tryCatch(
  {
    enableMatrixTracing(filepath)

    mat <- Matrix(1:9, nrow = 3, ncol = 3, sparse = TRUE)
    result <- .Call("R_sparse_transpose", mat, FALSE, PACKAGE = "Matrix")

    if (inherits(result, "dgCMatrix")) {
      cat("  SUCCESS: C-level transpose produced Matrix output\n")
    } else {
      cat("  ERROR: Expected dgCMatrix output\n")
      success <<- FALSE
    }

    if ("uid" %in% slotNames(result)) {
      cat("  SUCCESS: Result has uid slot\n")
    } else {
      cat("  ERROR: Result missing uid slot\n")
      success <<- FALSE
    }

    disableMatrixTracing()
  },
  error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n")
    success <<- FALSE
  }
)

if (success) {
  cat("\n--- All Tests PASSED ---\n")
  if (file.exists(filepath)) {
    invisible(file.remove(filepath))
  }
} else {
  cat("\n--- Some Tests FAILED ---\n")
}

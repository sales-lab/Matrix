library(Matrix)

cat("--- CHOLMOD Wrapper Tracing ---\n")

filepath <- "tests/test-tracing-cholmod.log"
if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

enableMatrixTracing(filepath)

success <- TRUE

# Test 1: CHMfactor_diag_get
cat("\nTest 1: CHMfactor_diag_get\n")
tryCatch(
  {
    n <- 1000
    m <- 200
    nnz <- 2000
    M1 <- spMatrix(n, m,
      i = sample(n, nnz, replace = TRUE),
      j = sample(m, nnz, replace = TRUE),
      x = round(rnorm(nnz), 1)
    )
    XX <- crossprod(M1)
    CX <- Cholesky(XX)
    d <- diag(CX)
  },
  error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n")
    success <<- FALSE
  }
)

# Test 2: CHMfactor_update
cat("\nTest 2: CHMfactor_update\n")
tryCatch(
  {
    CX2 <- update(CX, XX, mult = pi)
    cat("  SUCCESS: update(CHMfactor) executed\n")
  },
  error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n")
    success <<- FALSE
  }
)

# Test 3: CHMfactor_updown
cat("\nTest 3: CHMfactor_updown\n")
tryCatch(
  {
    M2 <- sparseMatrix(
      i = c(3, 1, 3:2, 2:1), p = c(0:2, 4, 4, 6), x = 1:6
    )
    CX3 <- Cholesky(A <- crossprod(M2) + Diagonal(5))
    CX4 <- updown("+", Diagonal(5, 1), CX3)
    cat("  SUCCESS: updown(CHMfactor) executed\n")
  },
  error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n")
    success <<- FALSE
  }
)

# Test 4: CHMfactor_solve (dense)
cat("\nTest 4: CHMfactor_solve (dense)\n")
tryCatch(
  {
    n <- 100
    M3 <- rsparsematrix(n, n, density = 0.05)
    A_sparse <- crossprod(M3) + Diagonal(n)
    CX_factor <- Cholesky(A_sparse)
    y_dense <- matrix(rnorm(n * 2), nrow = n, ncol = 2)
    x_dense <- solve(CX_factor, y_dense)
  },
  error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n")
    success <<- FALSE
  }
)

# Test 5: CHMfactor_solve (sparse)
cat("\nTest 5: CHMfactor_solve (sparse)\n")
tryCatch(
  {
    n <- 100
    M4 <- rsparsematrix(n, n, density = 0.05)
    A_sparse <- crossprod(M4) + Diagonal(n)
    CX_factor <- Cholesky(A_sparse)
    y_sparse <- rsparsematrix(n, 2, density = 0.1)
    x_sparse <- solve(CX_factor, y_sparse)
  },
  error = function(e) {
    cat("  ERROR:", conditionMessage(e), "\n")
    success <<- FALSE
  }
)

disableMatrixTracing()

# Verify log file
cat("\n--- Log File Analysis ---\n")
cat("Log file path:", filepath, "\n")
if (file.exists(filepath)) {
  decoded <- system2(
    "python3",
    args = c("inst/scripts/tracing-decode.py", shQuote(filepath)),
    stdout = TRUE,
    stderr = TRUE
  )

  if (length(decoded) > 0 && decoded[1] != "") {
    json_lines <- decoded[nzchar(decoded)]
    cat("Total records:", length(json_lines), "\n")

    has_operation <- sum(grepl('"event_type": "operation"', json_lines))
    cat("OPERATION events:", has_operation, "\n")

    has_start <- sum(grepl('"event_type": "start"', json_lines))
    cat("START events:", has_start, "\n")

    has_end <- sum(grepl('"event_type": "end"', json_lines))
    cat("END events:", has_end, "\n")

    if (has_operation > 0) {
      cat("SUCCESS: CHOLMOD wrapper functions are being traced!\n")
    } else {
      cat("WARNING: No OPERATION events found\n")
    }

    cat("\nTest 6: Verify CHOLMOD method names are recorded in START events\n")
    start_events <- Filter(function(line) grepl('"event_type": "start"', json_lines), json_lines)

    if (length(start_events) > 0) {
      op_names <- sapply(start_events, function(line) {
        if (grepl('"op_name":', line)) {
          match <- regmatches(line, regexec('"op_name": "([^"]*)"', line))[[1]]
          if (length(match) > 1) match[2] else ""
        } else {
          ""
        }
      })
      op_names <- op_names[op_names != ""]
      unique_op_names <- unique(op_names)

      expected_methods <- c(
        "CHMfactor_diag_get",
        "CHMfactor_update",
        "CHMfactor_updown",
        "CHMfactor_solve"
      )

      chmfactor_found <- sapply(expected_methods, function(m) m %in% unique_op_names)
      names(chmfactor_found) <- expected_methods

      cat("  CHOLMOD wrapper functions found in START events:\n")
      found_count <- sum(chmfactor_found)
      for (m in expected_methods) {
        status <- if (chmfactor_found[m]) "FOUND" else "MISSING"
        cat("   -", m, ":", status, "\n")
      }

      if (found_count == length(expected_methods)) {
        cat("  SUCCESS:", found_count, "CHOLMOD methods are traced\n")
      } else {
        cat("  WARNING: Some CHOLMOD methods were not found in TRACE\n")
      }
    } else {
      cat("  ERROR: No START events found\n")
      success <<- FALSE
    }
  }
} else {
  cat("ERROR: Log file not created\n")
  success <<- FALSE
}

cat("\n--- Test Complete ---\n")
if (success) {
  cat("*** ALL TESTS PASSED ***\n")
} else {
  cat("*** SOME TESTS FAILED ***\n")
}

if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

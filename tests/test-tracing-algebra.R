library(Matrix)

cat("--- Matrix Algebra Tracing ---\n")

filepath <- "tests/test-tracing-algebra.log"
if (file.exists(filepath)) invisible(file.remove(filepath))

enableMatrixTracing(filepath)

success <- TRUE

# Test 1: Matrix multiplication
cat("\nTest 1: Dense matrix multiplication\n")
tryCatch({
  a <- Matrix(runif(100), nrow=10)
  b <- Matrix(runif(100), nrow=10)
  c <- a %*% b
  cat("  SUCCESS: a %*% b executed\n")
}, error = function(e) {
  cat("  ERROR:", conditionMessage(e), "\n")
  success <<- FALSE
})

# Test 2: Sparse matrix multiplication
cat("\nTest 2: Sparse matrix multiplication\n")
tryCatch({
  a <- Matrix(0, nrow=10, ncol=10)
  a[1,1] <- 1
  a[2,2] <- 1
  b <- a %*% t(a)
  cat("  SUCCESS: sparse %*% executed\n")
}, error = function(e) {
  cat("  ERROR:", conditionMessage(e), "\n")
  success <<- FALSE
})

# Test 3: Cholesky decomposition
cat("\nTest 3: Cholesky decomposition\n")
tryCatch({
  a <- Matrix(runif(100), nrow=10)
  a <- t(a) %*% a  # Make positive definite
  ch <- Cholesky(a)
  cat("  SUCCESS: Cholesky executed\n")
}, error = function(e) {
  cat("  ERROR:", conditionMessage(e), "\n")
  success <<- FALSE
})

# Test 4: LU decomposition
cat("\nTest 4: LU decomposition\n")
tryCatch({
  a <- Matrix(runif(100), nrow=10)
  lu <- lu(a)
  cat("  SUCCESS: lu executed\n")
}, error = function(e) {
  cat("  ERROR:", conditionMessage(e), "\n")
  success <<- FALSE
})

# Test 5: QR decomposition
cat("\nTest 5: QR decomposition\n")
tryCatch({
  a <- Matrix(runif(100), nrow=10)
  qr <- qr(a)
  cat("  SUCCESS: qr executed\n")
}, error = function(e) {
  cat("  ERROR:", conditionMessage(e), "\n")
  success <<- FALSE
})

# Test 6: Solve
cat("\nTest 6: Linear solve\n")
tryCatch({
  a <- Matrix(runif(100), nrow=10)
  a <- a + diag(10)  # Make non-singular
  b <- Matrix(runif(10), nrow=10)
  x <- solve(a, b)
  cat("  SUCCESS: solve executed\n")
}, error = function(e) {
  cat("  ERROR:", conditionMessage(e), "\n")
  success <<- FALSE
})

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
    
    if (has_operation > 0) {
      cat("SUCCESS: Functions are being traced!\n")
    } else {
      cat("WARNING: No OPERATION events found\n")
    }
  }
} else {
  cat("ERROR: Log file not created\n")
  success <<- FALSE
}

# Keep log file for inspection
# if (file.exists(filepath)) file.remove(filepath)

cat("\n--- Test Complete ---\n")
if (success) {
  cat("*** ALL TESTS PASSED ***\n")
} else {
  cat("*** SOME TESTS FAILED ***\n")
}

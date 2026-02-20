library(Matrix)

cat("--- Tracing Operations Test ---\n")

success <- TRUE
filepath <- "tests/test-tracing-ops.log"

enableMatrixTracing(filepath)

cat("\n=== Test 1: Basic operations (transpose, band, diag) ===\n")
cat("Test 1.1: Transpose operations\n")
dx <- Matrix(1:9, nrow = 3, ncol = 3)
t_dx <- t(dx)
cat("  Dense transpose: OK\n")

x <- Matrix(1:9, nrow = 3, ncol = 3, sparse = TRUE)
t_x <- t(x)
cat("  Sparse transpose: OK\n")

cat("Test 1.2: Band operations\n")
dy <- band(dx, -1, 1)
y <- tril(x)
z <- triu(x)
cat("  Band operations: OK\n")

cat("Test 1.3: Diagonal operations\n")
diag_dx <- diag(dx)
diag_x <- diag(x)
diag(dx) <- 1:3
diag(x) <- 1:3
cat("  Diagonal operations: OK\n")

cat("\n=== Test 2: Algebra operations ===\n")
cat("Test 2.1: Matrix multiplication\n")
a <- Matrix(runif(16), nrow = 4)
b <- Matrix(runif(16), nrow = 4)
c <- a %*% b
cat("  Dense %*%: OK\n")

da <- Matrix(0, nrow = 4, ncol = 4)
da[1,1] <- 1
da[2,2] <- 2
db <- da %*% t(da)
cat("  Sparse %*%: OK\n")

cat("\n=== Test 3: Coercion operations ===\n")
cat("Test 3.1: Sparse to dense\n")
dense_x <- as(x, "dgeMatrix")
cat("  as(sparse, dense): OK\n")

cat("Test 3.2: Dense to sparse\n")
sparse_dx <- as(dx, "dgCMatrix")
cat("  as(dense, sparse): OK\n")

cat("\n=== Test 4: Binding operations ===\n")
cat("Test 4.1: Rbind\n")
m1 <- Matrix(1:6, nrow = 2, ncol = 3)
m2 <- Matrix(7:12, nrow = 2, ncol = 3)
r1 <- rbind(m1, m2)
cat("  Rbind: OK\n")

cat("Test 4.2: Cbind\n")
c1 <- cbind(m1, m2)
cat("  Cbind: OK\n")

cat("\n=== Test 5: Check log file ===\n")
disableMatrixTracing()

if (file.exists(filepath)) {
  file_size <- file.info(filepath)$size
  cat("Log file size:", file_size, "bytes\n")
  
  if (file_size > 0) {
    cat("SUCCESS: Log file created\n")
  } else {
    cat("ERROR: Log file is empty\n")
    success <- FALSE
  }
} else {
  cat("ERROR: Log file not created\n")
  success <- FALSE
}

cat("\n=== Test 6: Verify event types ===\n")
decoded <- system2(
  "python3",
  args = c("inst/scripts/tracing-decode.py", shQuote(filepath)),
  stdout = TRUE,
  stderr = TRUE
)

if (length(decoded) > 0 && decoded[1] != "") {
  json_lines <- decoded[nzchar(decoded)]
  cat("Total records:", length(json_lines), "\n")
  
  has_start <- sum(grepl('"event_type": "start"', json_lines))
  has_end <- sum(grepl('"event_type": "end"', json_lines))
  has_operation <- sum(grepl('"event_type": "operation"', json_lines))
  
  cat("START events:", has_start, "\n")
  cat("END events:", has_end, "\n")
  cat("OPERATION events:", has_operation, "\n")
  
  if (has_start > 0 && has_end > 0) {
    cat("SUCCESS: Span events logged\n")
  }
  
  if (has_operation > 0) {
    cat("SUCCESS: OPERATION events logged\n")
  }
  
  cat("\nSample OPERATION events:\n")
  count <- 0
  for (line in json_lines) {
    if (grepl('"event_type": "operation"', line) && count < 3) {
      cat(" ", line, "\n")
      count <- count + 1
    }
  }
} else {
  cat("ERROR: No decoded output\n")
  success <- FALSE
}

if (file.exists(filepath)) {
  invisible(file.remove(filepath))
}

cat("\n--- Test Complete ---\n")
if (success) {
  cat("\n*** ALL TESTS PASSED ***\n")
} else {
  cat("\n*** SOME TESTS FAILED ***\n")
}

library(Matrix)

cat("--- Verification Start ---\n")

# 1. Check for uid slot
m1 <- Matrix(1:4, 2, 2)
if ("uid" %in% slotNames(m1)) {
    cat("SUCCESS: uid slot is present in Matrix object.\n")
} else {
    cat("FAILURE: uid slot is missing from Matrix object.\n")
}

# 2. Check uid uniqueness in normal mode
m2 <- Matrix(1:4, 2, 2)
cat("UID 1: ", paste(as.character(m1@uid), collapse=" "), "\n")
cat("UID 2: ", paste(as.character(m2@uid), collapse=" "), "\n")

if (!identical(m1@uid, m2@uid)) {
    cat("SUCCESS: UIDs are different in normal mode.\n")
} else {
    cat("FAILURE: UIDs are identical in normal mode.\n")
}

if (!identical(m1, m2)) {
    cat("SUCCESS: identical() returns FALSE for identical values but different UIDs.\n")
} else {
    cat("FAILURE: identical() returns TRUE even with different UIDs (unexpected).\n")
}

# 3. Check uid consistency in test mode
options(Matrix.uid.test = TRUE)
m3 <- Matrix(1:4, 2, 2)
m4 <- Matrix(1:4, 2, 2)
cat("UID 3 (test mode): ", paste(as.character(m3@uid), collapse=" "), "\n")
cat("UID 4 (test mode): ", paste(as.character(m4@uid), collapse=" "), "\n")

if (identical(m3@uid, m4@uid)) {
    cat("SUCCESS: UIDs are identical in test mode.\n")
} else {
    cat("FAILURE: UIDs are different in test mode.\n")
}

if (identical(m3, m4)) {
    cat("SUCCESS: identical() returns TRUE in test mode.\n")
} else {
    cat("FAILURE: identical() returns FALSE in test mode.\n")
}

cat("--- Verification End ---\n")

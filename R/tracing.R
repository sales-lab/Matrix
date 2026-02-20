the_tracing <- new.env(emptyenv())

log_matrix_info <- function(.Object) {
  NULL
}

enableMatrixTracing <- function(filepath) {
  if (isMatrixTracing()) {
    stop("Matrix tracing is already enabled")
  }

  if (!is.character(filepath) || length(filepath) != 1) {
    stop("'filepath' must be a length-1 character vector")
  }
  .Call("tracing_init", filepath, PACKAGE = "Matrix")

  generics <- discover_generics()
  store_discovered_generics(generics)
  trace_generics(generics)
  trace_functions()

  assign("tracing", TRUE, envir = the_tracing)
  message("Matrix S4 method tracing enabled")
}

discover_generics <- function() {
  loaded_pkgs <- loadedNamespaces()
  generics <- list_generics()
  out <- list()

  for (pkg in loaded_pkgs) {
    for (gen in generics) {
      if (!isGeneric(gen, where = asNamespace(pkg))) {
        next
      }

      methods <- try(findMethods(gen, where = asNamespace(pkg)), silent = TRUE)
      if (inherits(methods, "try-error") || length(methods) == 0) {
        next
      }

      sigs <- findMethodSignatures(methods = methods)

      for (i in seq_len(nrow(sigs))) {
        has_matrix_class <- FALSE
        for (j in seq_along(sigs[i, ])) {
          cls <- sigs[i, j]
          stopifnot(!is.na(cls) && cls != "")

          cld <- getClassDef(cls)
          if (
            !is.null(cld) &&
              (extends(cld, "Matrix") || extends(cld, "sparseVector"))
          ) {
            has_matrix_class <- TRUE
            break
          }
        }

        if (has_matrix_class) {
          sig <- as.list(sigs[i, ])

          out[[length(out) + 1]] <- list(
            generic = gen,
            signature = sig,
            package = pkg
          )
        }
      }
    }
  }

  out
}

list_generics <- function() {
  worker <- function(names) {
    unlist(lapply(names, \(n) {
      if (is(get(n), "groupGenericFunction")) {
        children <- worker(getGroupMembers(n))
        c(n, children)
      } else {
        n
      }
    }))
  }

  init <- getGenerics()@.Data
  unique(worker(init))
}

store_discovered_generics <- function(generics_list) {
  assign("discovered_generics", generics_list, envir = the_tracing)
}

trace_generics <- function(generics) {
  suppressMessages(
    for (entry in generics) {
      trace_function_call(entry$generic, entry$signature, entry$package)
    }
  )
}

trace_function_call <- function(gen_name, signature, package) {
  state <- new.env(emptyenv())

  entry_tracer <- function() {
    call_site <- NULL
    if (sys.nframe() >= 2) {
      parent_call <- sys.call(1)
      if (!is.null(parent_call)) {
        call_site <- paste(deparse(parent_call, width.cutoff = 500), collapse = " ")
      }
    }

    scope <- .Call("tracing_start_span_r", gen_name, call_site, PACKAGE = "Matrix")
    assign(".span_scope", scope, envir = state, inherits = FALSE)
  }

  exit_tracer <- function() {
    scope <- get(".span_scope", envir = state, inherits = FALSE)

    ret <- returnValue()

    penv <- sys.frame(-1)
    args <- as.list(penv, all.names = TRUE)
    if (exists("...", envir = penv, inherits = FALSE)) {
      dots <- eval(quote(list(...)), envir = penv)
      args[["..."]] <- NULL
      args <- c(args, dots)
    }

    input_matrices <- extract_matrix_objects(args)

    if (length(input_matrices) > 0) {
      output_matrices <- list()
      if (!is.null(ret)) {
        output_matrices <- extract_matrix_objects(if (is.list(ret)) ret else list(ret))
      }
      .Call("tracing_log_operation", scope, input_matrices, output_matrices, PACKAGE = "Matrix")
    }

    .Call("tracing_end_span_r", scope, PACKAGE = "Matrix")
  }

  suppressMessages(
    do.call(trace, list(
      what = gen_name,
      tracer = entry_tracer,
      exit = exit_tracer,
      signature = signature,
      where = asNamespace(package),
      print = FALSE
    ))
  )
}

extract_matrix_objects <- function(objs) {
  Filter(function(x) isS4(x) && (is(x, "Matrix") || is(x, "sparseVector")), objs)
}

trace_functions <- function() {
  funcs <- list_functions_from_matrix()
  for (func_name in funcs) {
    trace_function_call(func_name, NULL, "Matrix")
  }
}

list_functions_from_matrix <- function() {
  env <- asNamespace("Matrix")
  exports <- getNamespaceInfo(env, "exports")

  funs <- ls(exports, all.names = FALSE)

  Filter(
    \(fname) {
      f <- get(fname, envir = env)
      is.function(f) &&
        !inherits(f, c("standardGeneric", "groupGenericFunction"))
    },
    funs
  )
}

disableMatrixTracing <- function() {
  untrace_generics()
  untrace_functions()
  .Call("tracing_shutdown", PACKAGE = "Matrix")

  assign("tracing", FALSE, envir = the_tracing)
  message("Matrix S4 method tracing disabled")
}

untrace_generics <- function() {
  discovered <- get_discovered_generics()
  suppressMessages(
    for (entry in discovered) {
      untrace(entry$generic, entry$signature, asNamespace(entry$package))
    }
  )
}

untrace_functions <- function() {
  funcs <- list_functions_from_matrix()
  ns <- asNamespace("Matrix")
  suppressMessages(
    for (func_name in funcs) {
      untrace(func_name, NULL, ns)
    }
  )
}

get_discovered_generics <- function() {
  get0(
    "discovered_generics",
    envir = the_tracing,
    inherits = FALSE,
    ifnotfound = list()
  )
}

isMatrixTracing <- function() {
  get0("tracing", envir = the_tracing, inherits = FALSE, ifnotfound = FALSE)
}

matrix_tracing_log_metadata <- function(obj) {
  .Call("tracing_log_metadata", obj@uid, nrow(obj), ncol(obj), nnzero(obj),
    PACKAGE = "Matrix"
  )
}

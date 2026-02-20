# Matrix

This is a fork of the original [Matrix package](https://github.com/cran/Matrix) introducing an experimental tracing facility for matrix operations.

## Overview

This package adds a high-fidelity tracing system that provides **Observability** and **Data Lineage** for matrix operations. The tracing system enables users to reconstruct the causal graph of calculations by tracking:

- Matrix object lifecycle (creation, population, usage)
- Operation lineage (which matrices went in, which came out)
- Subscripting indices (for non-Matrix outputs)
- Thread-safe operation logging

## Status

**Experimental** — The tracing facility is under active development. Documentation is being written, but the core infrastructure is functional.

## Usage

Tracing is controlled via R-level instrumentation. See the tests directory for usage examples, particularly scripts with "tracing" in the name:

```bash
Rscript tests/test-tracing-*.R
```

#!/usr/bin/env Rscript

# Prepare a long-form Quarto module for dual html + revealjs rendering:
#   1. Wrap each prose paragraph in `::: {.narration}` (speaker notes on
#      slides via web_and_slides.lua, normal prose on the website).
#   2. Add the web_and_slides.lua filter to the front matter if it isn't there.
#   3. Ensure slide-friendly YAML: execute.echo and execute.output-location
#      (fragment) and revealjs.smaller = true, and remove revealjs.scrollable
#      (scrolling mid-talk is awkward; chunks reveal as fragments instead).
#   4. Report headings that will render awkwardly as revealjs slides.
# Code blocks, headings, images, fenced divs (callouts), lists, blockquotes
# and tables are left untouched.
#
# Usage: Rscript web_and_slides.R <input.qmd> [output.qmd]
#            [--filter=<path/to/web_and_slides.lua>] [--no-inject] [--no-settings]

library(readr)
library(stringr)
library(fs)

args   <- commandArgs(trailingOnly = TRUE)
flags  <- args[str_starts(args, "--")]
pos    <- args[!str_starts(args, "--")]
if (length(pos) < 1) stop("Usage: web_and_slides.R <input.qmd> [output.qmd] [--filter=...] [--no-inject] [--no-settings]")

input        <- pos[[1]]
output       <- if (length(pos) >= 2) pos[[2]] else input
inject       <- !("--no-inject" %in% flags)
set_settings <- !("--no-settings" %in% flags)
filter_arg   <- str_subset(flags, "^--filter=")
filter_path  <- if (length(filter_arg)) str_remove(filter_arg[[1]], "^--filter=") else "web_and_slides.lua"

lines <- read_lines(input)

# --- separate YAML front matter (kept verbatim) ------------------------------
if (length(lines) > 0 && str_detect(lines[[1]], "^---\\s*$")) {
  close_idx <- which(str_detect(lines[-1], "^---\\s*$"))[1] + 1
  if (is.na(close_idx)) stop("Unterminated YAML front matter")
  yaml <- lines[seq_len(close_idx)]
  body <- if (close_idx < length(lines)) lines[(close_idx + 1):length(lines)] else character()
} else {
  yaml <- character()
  body <- lines
}
fm_len_orig <- length(yaml)   # original front-matter length, before any edits below

# --- wrap prose paragraphs in .narration -------------------------------------
out     <- character()
para    <- character()
in_code <- FALSE
depth   <- 0L

last_blank <- function() length(out) == 0 || str_detect(tail(out, 1), "^\\s*$")

flush <- function() {
  if (length(para) == 0) return(invisible())
  if (!last_blank()) out[[length(out) + 1]] <<- ""
  out  <<- c(out, "::: {.narration}", para, ":::", "")
  para <<- character()
}

for (ln in body) {
  if (str_detect(ln, "^\\s*```")) {                  # code fence: toggle
    flush(); in_code <- !in_code; out <- c(out, ln); next
  }
  if (in_code) { out <- c(out, ln); next }
  if (str_detect(ln, "^:::+")) {                     # fenced div open/close
    flush()
    depth <- if (str_detect(ln, "^:::+\\s*$")) max(0L, depth - 1L) else depth + 1L
    out <- c(out, ln); next
  }
  if (depth > 0) { out <- c(out, ln); next }         # callout internals: leave
  if (str_detect(ln, "^\\s*$")) {                    # blank ends a paragraph
    flush(); if (!last_blank()) out <- c(out, ""); next
  }
  if (str_detect(ln, "^#{1,6}\\s") ||                # headings
      str_detect(ln, "^\\s*([-*+]|\\d+[.)])\\s") ||  # lists
      str_detect(ln, "^\\s*>") ||                    # blockquotes
      str_detect(ln, "^\\s*\\|") ||                  # tables
      str_detect(ln, "^\\s*!\\[.*\\]\\(.*\\)\\s*$")) {# standalone images
    flush(); out <- c(out, ln); next
  }
  para <- c(para, ln)                                # prose
}
flush()

# --- add narration.lua to front matter (relative to the output doc) ----------
inject_filter <- function(yaml, filter_path, output) {
  if (length(yaml) == 0) { warning("No YAML front matter; skipping filter injection"); return(yaml) }
  rel <- path_rel(path_abs(filter_path), start = path_dir(path_abs(output)))
  # remove any prior entry for our filters (single-line or pre-ast block form),
  # so re-runs migrate cleanly to the current registration
  names_re <- "(narrate|narration|fragmentcells|slidebreaks)\\.lua"
  drop <- str_detect(yaml, names_re)
  for (i in which(drop)) {
    if (str_detect(yaml[i], "^\\s*path:") && i > 1 && str_detect(yaml[i - 1], "^\\s*-\\s*at:"))
      drop[i - 1] <- TRUE
  }
  yaml <- yaml[!drop]
  # web_and_slides.lua must run before Quarto normalizes callouts into custom AST nodes,
  # otherwise the callout-isolation pass can't see them; pre-ast keeps them as divs
  entry <- c("  - at: pre-ast", paste0("    path: ", rel))
  fi <- which(str_detect(yaml, "^filters:\\s*"))[1]
  if (is.na(fi)) {
    close <- length(yaml)
    c(yaml[seq_len(close - 1)], "filters:", entry, yaml[close])
  } else if (str_detect(yaml[fi], "^filters:\\s*\\[")) {
    warning("Inline `filters: [...]` found; add web_and_slides.lua at pre-ast manually"); yaml
  } else {
    append(yaml, entry, after = fi)
  }
}
if (inject) yaml <- inject_filter(yaml, filter_path, output)

# --- ensure a nested `key: value` under a parent path (e.g. format>revealjs) --
indent_of <- function(line) {
  if (str_detect(line, "^\\s*$")) return(NA_integer_)
  str_length(str_extract(line, "^ *"))
}

ensure_nested <- function(yaml, path, key, value) {
  if (length(yaml) == 0) return(yaml)
  lo <- 2L; hi <- length(yaml); parent_indent <- -2L; header_idx <- NA_integer_
  for (pi in seq_along(path)) {
    p <- path[[pi]]; child_indent <- parent_indent + 2L; idx <- NA_integer_
    if (lo <= hi - 1L) for (i in lo:(hi - 1L)) {
      li <- yaml[[i]]
      if (!str_detect(li, "^\\s*$") && indent_of(li) == child_indent &&
          str_detect(li, paste0("^", strrep(" ", child_indent), p, ":"))) { idx <- i; break }
    }
    if (is.na(idx)) {                                # parent missing: build chain
      block <- character(); ind <- child_indent
      for (kk in path[pi:length(path)]) { block <- c(block, paste0(strrep(" ", ind), kk, ":")); ind <- ind + 2L }
      block <- c(block, paste0(strrep(" ", ind), key, ": ", value))
      return(append(yaml, block, after = hi - 1L))
    }
    # convert an inline scalar parent (e.g. `revealjs: default`) to a block header
    prefix  <- str_extract(yaml[[idx]], paste0("^\\s*", p, ":"))
    after   <- str_sub(yaml[[idx]], str_length(prefix) + 1L)
    cm      <- str_locate(after, "\\s+#.*$")         # trailing comment
    comment <- if (!is.na(cm[1, 1])) str_sub(after, cm[1, 1]) else ""
    code    <- if (!is.na(cm[1, 1])) str_sub(after, 1L, cm[1, 1] - 1L) else after
    val     <- str_trim(code)
    if (val == "default") {
      yaml[[idx]] <- paste0(prefix, comment)
    } else if (val != "") {
      warning("'", p, ": ", val, "' is a scalar; add ", key, " manually"); return(yaml)
    }
    header_idx <- idx; block_indent <- child_indent; e <- hi
    if (idx + 1L <= hi - 1L) for (j in (idx + 1L):(hi - 1L)) {
      if (!str_detect(yaml[[j]], "^\\s*$") && indent_of(yaml[[j]]) <= block_indent) { e <- j; break }
    }
    lo <- idx + 1L; hi <- e; parent_indent <- block_indent
  }
  child_indent <- parent_indent + 2L
  if (lo <= hi - 1L) for (i in lo:(hi - 1L)) {       # key already present?
    li <- yaml[[i]]
    if (!str_detect(li, "^\\s*$") && indent_of(li) == child_indent &&
        str_detect(li, paste0("^", strrep(" ", child_indent), key, ":"))) {
      m <- str_match(li, paste0("^(\\s*", key, ":\\s*)(\\S+)(.*)$"))
      if (!is.na(m[1, 1]) && m[1, 3] != value) {
        yaml[[i]] <- paste0(m[1, 2], value, m[1, 4]); message("  updated ", key, ": ", m[1, 3], " -> ", value)
      }
      return(yaml)
    }
  }
  append(yaml, paste0(strrep(" ", child_indent), key, ": ", value), after = header_idx)
}

# --- remove a nested key (e.g. drop revealjs.scrollable) if present ----------
remove_nested <- function(yaml, path, key) {
  if (length(yaml) == 0) return(yaml)
  lo <- 2L; hi <- length(yaml); parent_indent <- -2L
  for (p in path) {
    child_indent <- parent_indent + 2L; idx <- NA_integer_
    if (lo <= hi - 1L) for (i in lo:(hi - 1L)) {
      li <- yaml[[i]]
      if (!str_detect(li, "^\\s*$") && indent_of(li) == child_indent &&
          str_detect(li, paste0("^", strrep(" ", child_indent), p, ":"))) { idx <- i; break }
    }
    if (is.na(idx)) return(yaml)                   # parent absent: nothing to remove
    block_indent <- child_indent; e <- hi
    if (idx + 1L <= hi - 1L) for (j in (idx + 1L):(hi - 1L)) {
      if (!str_detect(yaml[[j]], "^\\s*$") && indent_of(yaml[[j]]) <= block_indent) { e <- j; break }
    }
    lo <- idx + 1L; hi <- e; parent_indent <- block_indent
  }
  child_indent <- parent_indent + 2L
  if (lo <= hi - 1L) for (i in lo:(hi - 1L)) {
    li <- yaml[[i]]
    if (!str_detect(li, "^\\s*$") && indent_of(li) == child_indent &&
        str_detect(li, paste0("^", strrep(" ", child_indent), key, ":"))) {
      return(yaml[-i])
    }
  }
  yaml
}

if (set_settings) {
  yaml <- ensure_nested(yaml, c("execute"),            "echo",            "true")
  yaml <- ensure_nested(yaml, c("execute"),            "output-location", "fragment")
  yaml <- ensure_nested(yaml, c("format", "revealjs"), "smaller",         "true")
  yaml <- remove_nested(yaml, c("format", "revealjs"), "scrollable")
}

# --- validate the edited front matter parses as YAML before writing ----------
validate_front_matter <- function(yaml) {
  if (length(yaml) < 2) return(invisible())
  if (!requireNamespace("yaml", quietly = TRUE)) {
    warning("Package 'yaml' not installed; skipping front-matter validation")
    return(invisible())
  }
  fm <- paste(yaml[-c(1, length(yaml))], collapse = "\n")   # drop the --- fences
  tryCatch(
    yaml::yaml.load(fm),
    error = function(e) stop("Edited front matter is not valid YAML (nothing written): ",
                             conditionMessage(e))
  )
  invisible()
}
validate_front_matter(yaml)

write_lines(c(yaml, out), output)

# --- report slide-unfriendly headings ----------------------------------------
report_headings <- function(yaml, body, offset, ref) {
  sl <- 2L                                           # revealjs default slide-level
  m  <- str_match(yaml, "^\\s*slide-level:\\s*(\\d+)")
  if (any(!is.na(m[, 2]))) sl <- as.integer(m[!is.na(m[, 2]), 2][1])

  in_code <- FALSE; depth <- 0L
  real <- rep(FALSE, length(body)); lvl <- integer(length(body))
  for (i in seq_along(body)) {
    ln <- body[[i]]
    if (str_detect(ln, "^\\s*```")) { in_code <- !in_code; next }
    if (in_code) next
    if (str_detect(ln, "^:::+")) {
      depth <- if (str_detect(ln, "^:::+\\s*$")) max(0L, depth - 1L) else depth + 1L; next
    }
    if (depth > 0) next
    h <- str_match(ln, "^(#{1,6})\\s+")
    if (!is.na(h[1])) { real[i] <- TRUE; lvl[i] <- str_length(h[2]) }
  }
  idx <- which(real)
  if (length(idx) == 0) return(invisible())

  has_content <- function(k) {
    i0 <- idx[k]; i1 <- if (k < length(idx)) idx[k + 1] else length(body) + 1
    seg <- if (i1 - 1 >= i0 + 1) body[(i0 + 1):(i1 - 1)] else character()
    d <- 0L
    for (ln in seg) {
      if (str_detect(ln, "^\\s*```")) return(TRUE)
      if (str_detect(ln, "^:::+")) { d <- if (str_detect(ln, "^:::+\\s*$")) max(0L, d-1L) else d+1L; next }
      if (d > 0) return(TRUE)
      if (!str_detect(ln, "^\\s*$") && !str_detect(ln, "^#{1,6}\\s")) return(TRUE)
    }
    FALSE
  }

  msgs <- character()
  for (k in seq_along(idx)) {
    i <- idx[k]; L <- lvl[i]; title <- str_remove(body[[i]], "^#{1,6}\\s+")
    # deep headings (L > sl) are promoted to slide level by web_and_slides.lua, so they
    # no longer fold in; only flag headings above the slide level that carry
    # content, which become centered title slides on revealjs.
    if (L < sl && has_content(k))
      msgs <- c(msgs, sprintf("  line %d  %s %s  -> centered title slide WITH content (probably unwanted)", offset + i, strrep("#", L), title))
  }
  if (length(msgs)) {
    message("Slide-structure check (slide-level = ", sl, ") — lines in ", ref, ":")
    message(paste(msgs, collapse = "\n"))
    message("These become centered title slides; move their content under a sub-heading or accept the divider.")
  }
}
# in-place: numbers match the written file; separate output: match the original input
if (path_abs(input) == path_abs(output)) {
  report_headings(yaml, out,  length(yaml), output)
} else {
  report_headings(yaml, body, fm_len_orig, input)
}

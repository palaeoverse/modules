#!/usr/bin/env Rscript

# Check each module's _sidebar.yml (see sync_sidebars.r and the README).
#
# Errors (fail the check):
#   - _sidebar.yml isn't valid YAML, or isn't a list of sidebar items
#   - an item uses `auto`, or gives `contents` as a string rather than a list
#     (sync_sidebars.r only rewrites explicit paths, so these would resolve
#     against the website root rather than the module)
#   - a listed page doesn't exist in the module
#
# Warnings (reported, but don't fail the check):
#   - a module with a _sidebar.yml has a web page that the sidebar doesn't list
#   - a module has more than one web page but no _sidebar.yml
#
# A "web page" is a .qmd that renders to html (or live-html); slides-only files
# (format: revealjs) don't count. Output is formatted as GitHub Actions
# annotations.
#
# Usage: Rscript .github/check_sidebars.r   (run from the repo root)

library(yaml)

errors   <- character(0)
warnings <- character(0)
report <- function(level, file, msg, line = 1) {
  out <- sprintf("::%s file=%s,line=%d::%s", level, file, line, msg)
  if (level == "error") errors <<- c(errors, out) else warnings <<- c(warnings, out)
}

# first line of `file` matching `pattern`, or 1 if none does
line_of <- function(file, pattern) {
  i <- grep(pattern, readLines(file, warn = FALSE), perl = TRUE)
  if (length(i)) i[[1]] else 1
}

# first line of a _sidebar.yml listing `path` as a whole entry, so "index.qmd"
# doesn't match "appendix/index.qmd"
line_of_path <- function(file, path) {
  line_of(file, sprintf("(^|[\\s\"'])\\Q%s\\E([\\s\"'#]|$)", path))   # \Q..\E: literal
}

front_matter <- function(path) {
  lines  <- readLines(path, warn = FALSE)
  fences <- which(trimws(lines) == "---")
  if (length(fences) < 2 || fences[[1]] != 1) return(list())
  meta <- tryCatch(yaml.load(paste(lines[2:(fences[[2]] - 1)], collapse = "\n")),
                   error = function(e) NULL)
  if (is.list(meta)) meta else list()
}

# html (or e.g. live-html) unless every format is a non-html one like revealjs
is_web_page <- function(path) {
  fmt <- front_matter(path)$format
  if (is.null(fmt)) return(TRUE)
  fmts <- if (is.list(fmt)) names(fmt) else as.character(fmt)
  any(grepl("html$", fmts))
}

# local paths referenced by a sidebar item (files and hrefs, recursively)
paths_in <- function(item, sb) {
  if (is.character(item)) return(item)
  if (!is.list(item)) {
    report("error", sb, sprintf("unexpected sidebar item: %s", deparse(item)))
    return(character(0))
  }
  if (!is.null(item$auto)) {
    report("error", sb, "`auto` isn't supported in _sidebar.yml; list the pages by name",
           line_of(sb, "^[\\s-]*auto\\s*:"))
  }
  if (is.character(item$contents)) {
    report("error", sb, sprintf(
      "`contents: %s` isn't supported in _sidebar.yml; give contents as a list of pages",
      item$contents[[1]]), line_of(sb, "^[\\s-]*contents\\s*:\\s*[^\\s#]"))
    item$contents <- NULL
  }
  c(item$href, unlist(lapply(item$contents, paths_in, sb)))
}

# does a listed path exist in the module? an .html path is fine if a .qmd
# renders to it, e.g. `href: index-slides.html` from `output-file: index-slides.html`
listed_path_exists <- function(path, module, qmds) {
  if (file.exists(file.path(module, path))) return(TRUE)
  if (!grepl("[.]html$", path)) return(FALSE)
  if (sub("[.]html$", ".qmd", path) %in% qmds) return(TRUE)
  out_file <- sprintf("output-file:\\s*[\"']?%s[\"']?\\s*$", basename(path))
  any(vapply(file.path(module, qmds[dirname(qmds) == dirname(path)]), function(q)
    any(grepl(out_file, readLines(q, warn = FALSE))), logical(1)))
}

modules <- list.dirs(".", full.names = FALSE, recursive = FALSE)
modules <- modules[!grepl("^[._]", modules)]   # skip _templates, .git, ...

for (m in modules) {
  qmds <- list.files(m, pattern = "[.]qmd$", recursive = TRUE)
  # Quarto doesn't render _-prefixed files or anything in a _-prefixed folder
  qmds <- qmds[!grepl("(^|/)_", qmds)]
  web  <- qmds[vapply(file.path(m, qmds), is_web_page, logical(1))]
  sb   <- file.path(m, "_sidebar.yml")

  if (!file.exists(sb)) {
    if (length(web) > 1) {
      report("warning", file.path(m, "index.qmd"), sprintf(
        "%s has %d web pages but no _sidebar.yml, so it won't get a sidebar",
        m, length(web)))
    }
    next
  }

  # keep YAML lists as R lists: by default `contents: [a.qmd]` would come back
  # as the string "a.qmd", indistinguishable from the unsupported `contents: a.qmd`
  items <- tryCatch(read_yaml(sb, handlers = list(seq = as.list)), error = function(e) {
    msg  <- conditionMessage(e)
    line <- regmatches(msg, regexec("line (\\d+)", msg))[[1]][2]   # the parser reports it
    report("error", sb, paste("invalid YAML:", msg), if (is.na(line)) 1 else as.integer(line))
    NULL
  })
  if (is.null(items)) next
  if (!is.list(items) || !is.null(names(items))) {
    report("error", sb, "must be a YAML list of pages and sections (each line starting with `- `)")
    next
  }

  listed <- unlist(lapply(items, paths_in, sb))
  listed <- sub("#.*$", "", listed[!grepl("://", listed)])   # drop URLs and #anchors
  listed <- sub("^[.]/", "", listed[nzchar(listed)])

  for (p in unique(listed)) {
    if (!listed_path_exists(p, m, qmds)) {
      report("error", sb, sprintf("lists %s, which doesn't exist in %s", p, m),
             line_of_path(sb, p))
    }
  }
  for (p in setdiff(web, listed)) {
    report("warning", sb, sprintf("doesn't list %s, so that page won't be in the sidebar", p))
  }
}

if (length(warnings) > 0) cat(warnings, sep = "\n")
if (length(errors) > 0) {
  cat(errors, sep = "\n")
  cat(sprintf("\n%d sidebar error(s).\n", length(errors)))
  quit(status = 1)
}
cat("All _sidebar.yml checks passed.\n")

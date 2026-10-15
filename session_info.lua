-- session_info.lua
--
-- Add a collapsible "Session info" block to the bottom of every module's
-- long-form page. Registered for the whole project in _quarto.yml.
--
-- Packages are detected with pak::scan_deps() on the module's directory (as in
-- required_packages.lua) and passed to sessioninfo::session_info().

local detect = [=[
f <- commandArgs(trailingOnly = TRUE)[[1]]
pkgs <- pak::scan_deps(dirname(f))$package
# drop base R packages and tooling used only for rendering
base_pkgs <- rownames(installed.packages(priority = "base"))
pkgs <- setdiff(unique(pkgs), c("R", base_pkgs, "knitr", "rmarkdown", "quarto"))
options(width = 80)
if (length(pkgs) > 0) {
  print(sessioninfo::session_info(pkgs = pkgs))
} else {
  print(sessioninfo::session_info(info = "platform"))
}
]=]

function Pandoc(doc)
  if quarto.doc.is_format("revealjs") or quarto.doc.input_file == quarto.utils.resolve_path("index.qmd") then return nil end

  local ok, out = pcall(pandoc.pipe, quarto.paths.rscript(), { "-", quarto.doc.input_file }, detect)
  if not ok then
    quarto.log.warning("session_info: could not get session info: " .. tostring(out))
    return nil
  end

  doc.blocks:extend({
    pandoc.RawBlock("html", "<hr><br><details>\n<summary>Session info</summary>"),
    pandoc.CodeBlock(out),
    pandoc.RawBlock("html", "</details>")
  })
  return doc
end

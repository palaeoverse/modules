-- required_packages.lua
--
-- Add a "Packages used in this module" callout to the top of every module's
-- long-form page. Registered for the whole project in _quarto.yml.
--
-- Packages are detected with pak::scan_deps() on the module's directory, so
-- library(), require(), pkg::fun(), etc. are all picked up, even in chunks
-- with `echo: false`.

local detect = [=[
f <- commandArgs(trailingOnly = TRUE)[[1]]
pkgs <- pak::scan_deps(dirname(f))$package
# drop base R packages and tooling used only for rendering
base_pkgs <- rownames(installed.packages(priority = "base"))
pkgs <- setdiff(unique(pkgs), c("R", base_pkgs, "knitr", "rmarkdown", "quarto"))
cat(sort(pkgs), sep = "\n")
]=]

function Pandoc(doc)
  if quarto.doc.is_format("revealjs") or quarto.doc.input_file == quarto.utils.resolve_path("index.qmd") then return nil end

  local ok, out = pcall(pandoc.pipe, quarto.paths.rscript(), { "-", quarto.doc.input_file }, detect)
  if not ok then
    quarto.log.warning("required_packages: could not detect packages: " .. tostring(out))
    return nil
  end

  local pkgs = {}
  for pkg in out:gmatch("[^\r\n]+") do pkgs[#pkgs + 1] = '"' .. pkg .. '"' end
  if #pkgs == 0 then return nil end

  local callout = quarto.Callout({
    type    = "note",
    title   = "Packages used in this module",
    content = { pandoc.CodeBlock("install.packages(c(" .. table.concat(pkgs, ", ") .. "))", { class = "r" }) }
  })
  doc.blocks:insert(1, callout)
  return doc
end

-- source_link.lua
--
-- Add a link to the module's .qmd source on palaeoverse/modules to the top of
-- every module's long-form page. Registered for the whole project in
-- _quarto.yml.
--
-- The source path is the input file relative to this filter's directory, which
-- is the root of the modules (here and in the website repo alike).
--
-- The branch defaults to main and can be overridden with the SOURCE_LINK_REF
-- environment variable (used by the PR preview workflow to link to the PR's
-- branch).

local repo = "https://github.com/palaeoverse/modules/blob/" .. (os.getenv("SOURCE_LINK_REF") or "main") .. "/"

function Pandoc(doc)
  if quarto.doc.is_format("revealjs") or quarto.doc.input_file == quarto.utils.resolve_path("index.qmd") then return nil end

  -- canonical path of the filter's directory (resolve_path() can contain "..")
  local root = pandoc.system.with_working_directory(quarto.utils.resolve_path("."), pandoc.system.get_working_directory)
  local rel = pandoc.path.make_relative(quarto.doc.input_file, root):gsub("\\", "/")

  doc.blocks:insert(1, pandoc.Para(pandoc.Link(
    { pandoc.RawInline("html", '<i class="bi bi-github"></i> '), pandoc.Str("View source file") },
    repo .. rel, "", { style = "color: #90989f;", target = "_blank" }
  )))
  return doc
end

-- narrate.lua
-- Combined filter for dual html + revealjs Quarto modules:
--   * Div    : `::: {.narration}` -> speaker notes on revealjs, plain prose elsewhere.
--   * Pandoc : on revealjs, headings below the slide level are promoted so each
--              becomes its own slide, the slide closes after each plot (so no two
--              plots share a slide and a plot's following prose stays with the
--              next plot -- unless only prose remains before the next heading, in
--              which case it stays put rather than making a blank slide), and each
--              callout is unwrapped onto its own slide titled by its own heading
--              (no box, so any figure inside hoists and stretches; an untitled
--              callout keeps the section title). Split slides repeat the current
--              heading so they keep a title. Finally, any slide with 2+ cells is
--              expanded into an auto-animate build-up (one step per cell, cells
--              accumulating, notes advancing) so each step is a real slide whose
--              figure still hoists and auto-stretches. Other formats untouched.
-- Register at the `pre-ast` stage so callouts are still plain divs here (Quarto
-- normalizes them into custom AST nodes after that point).

function Div(el)
  if not el.classes:includes("narration") then
    return nil                                   -- leave every other div alone
  end
  if quarto.doc.is_format("revealjs") then
    el.classes = el.classes:filter(function(c) return c ~= "narration" end)
    el.classes:insert("notes")                   -- Pandoc emits <aside class="notes">
    return el
  end
  return el.content                              -- drop wrapper, keep prose inline
end

function Pandoc(doc)
  if not quarto.doc.is_format("revealjs") then
    return nil                                   -- leave the website (html) alone
  end

  local slide_level = 2                          -- revealjs default
  local sl = doc.meta["slide-level"]
  if sl then slide_level = tonumber(pandoc.utils.stringify(sl)) or 2 end

  local function is_callout(el)
    for _, c in ipairs(el.classes) do
      if c:match("^callout") then return true end
    end
    return false
  end

  local function has_plot(cell)                  -- a rendered figure/display output
    for _, child in ipairs(cell.content) do
      if child.t == "Div" and child.classes:includes("cell-output-display") then
        return true
      end
    end
    return false
  end

  -- unwrap callouts to plain blocks (recursively, for nested callouts) so their
  -- content sits directly on the slide -- a de-boxed callout behaves like normal
  -- slide content, and any figure inside hoists and auto-stretches. Headings at
  -- or above the slide level are demoted so a nested title can't split the slide;
  -- the leading heading is re-promoted to the slide title by the caller.
  local function unwrap_callouts(blocks)
    local flat = pandoc.List()
    for _, b in ipairs(blocks) do
      if b.t == "Div" and is_callout(b) then
        flat:extend(unwrap_callouts(b.content))
      elseif b.t == "Header" and b.level <= slide_level then
        local h = b:clone(); h.level = slide_level + 1; flat:insert(h)
      else
        flat:insert(b)
      end
    end
    return flat
  end

  -- is there any visible code cell before the next slide boundary, starting at
  -- block index `from`? A heading, rule, or callout is a boundary (a callout
  -- self-titles onto its own slide), so a trailing note only breaks if a plain
  -- cell -- not a callout -- lands on the new slide first.
  local function content_before_boundary(from)
    for j = from, #doc.blocks do
      local b = doc.blocks[j]
      if b.t == "Header" or b.t == "HorizontalRule" then return false end
      if b.t == "Div" and is_callout(b) then return false end
      if b.t == "Div" and b.classes:includes("cell") then return true end
    end
    return false
  end

  local out            = pandoc.List()
  local pending        = false                   -- a break is owed before the next slide content
  local filled         = false                   -- this slide already holds a visible cell/callout
  local current_header = nil                     -- most recent slide title, repeated on splits

  -- a break that keeps the current title: a fresh heading, else a plain rule
  local function slide_break()
    if current_header then
      local h = current_header:clone()
      h.level = slide_level                       -- render as a content-slide title
      h.identifier = ""                           -- let Quarto assign a fresh unique id
      return h
    end
    return pandoc.HorizontalRule()
  end

  for i = 1, #doc.blocks do
    local blk = doc.blocks[i]
    if blk.t == "Header" then
      if blk.level > slide_level then blk.level = slide_level end   -- deep headings -> own slide
      if blk.level <= slide_level then pending = false; filled = false end
      current_header = blk
      out:insert(blk)
    elseif blk.t == "HorizontalRule" then
      pending = false; filled = false
      out:insert(blk)
    elseif blk.t == "Div" and is_callout(blk) then
      -- give the callout its own slide titled by its own heading (promoted to the
      -- slide level, so the heading is itself the slide boundary); content is
      -- unwrapped so any figure inside hoists and stretches
      local content = unwrap_callouts(blk.content)
      if #content > 0 and content[1].t == "Header" then
        local title = content[1]:clone()
        title.level = slide_level                                                -- callout heading -> slide title
        title.identifier = ""
        content[1] = title
        out:extend(content)
      else
        if pending or filled then out:insert(slide_break()) end                  -- untitled callout keeps the section title
        out:extend(content)
      end
      filled = true; pending = true                                              -- alone; close the slide after
    elseif blk.t == "Div" and blk.classes:includes("cell") then
      if pending then out:insert(slide_break()); pending = false; filled = false end
      filled = true
      if has_plot(blk) then pending = true end                                   -- close the slide after a plot
      out:insert(blk)
    else
      -- prose/notes: honor a plot's pending break only if a cell/callout still
      -- follows before the next heading -- so the prose introduces the next
      -- slide. If only notes remain, breaking would make a blank titled slide,
      -- so keep them on the current slide instead.
      if pending then
        if content_before_boundary(i + 1) then out:insert(slide_break()); filled = false end
        pending = false
      end
      out:insert(blk)
    end
  end

  -- second pass: expand any slide holding 2+ cells into an auto-animate build-up
  -- -- one step per cell, cells accumulating, notes advancing with each new cell.
  -- Each step is a real slide, so its figure still hoists and auto-stretches
  -- (unlike a fragment). Single-cell and cell-free slides pass through unchanged.
  local function is_cell(b) return b.t == "Div" and b.classes:includes("cell") end

  local function strip_ids(cell)                 -- clone a cell with ids blanked (it is duplicated across steps)
    local c = cell:clone()
    c.identifier = ""
    return pandoc.walk_block(c, {
      Div       = function(d)  d.identifier  = ""; return d  end,
      CodeBlock = function(cb) cb.identifier = ""; return cb end,
    })
  end

  local function emit_slide(delim, body, dest)
    local segs, notes = {}, pandoc.List()         -- notes accumulates until the next cell
    for _, b in ipairs(body) do
      if is_cell(b) then
        segs[#segs + 1] = { notes = notes, cell = b }; notes = pandoc.List()
      else
        notes:insert(b)
      end
    end                                            -- leftover `notes` = trailing, after the last cell

    -- nothing to build up, or no heading to carry the auto-animate flag: emit as-is
    if #segs < 2 or delim == nil or delim.t ~= "Header" then
      if delim then dest:insert(delim) end
      for _, b in ipairs(body) do dest:insert(b) end
      return
    end

    for k = 1, #segs do
      local h = delim:clone()
      h.identifier = ""                            -- fresh id per step
      h.attributes["auto-animate"] = "true"
      dest:insert(h)
      for j = 1, k do dest:insert(strip_ids(segs[j].cell)) end     -- cells 1..k accumulate
      for _, n in ipairs(segs[k].notes) do dest:insert(n) end      -- notes for the cell just revealed
      if k == #segs then
        for _, n in ipairs(notes) do dest:insert(n) end            -- trailing notes on the last step
      end
    end
  end

  local expanded, delim, body = pandoc.List(), nil, pandoc.List()
  for _, b in ipairs(out) do
    -- a slide boundary is a rule or a heading at/above the slide level; deeper
    -- headings (e.g. an unwrapped callout's title) stay within the slide
    if b.t == "HorizontalRule" or (b.t == "Header" and b.level <= slide_level) then
      emit_slide(delim, body, expanded); delim = b; body = pandoc.List()
    else
      body:insert(b)
    end
  end
  emit_slide(delim, body, expanded)                -- flush the last slide

  return pandoc.Pandoc(expanded, doc.meta)
end

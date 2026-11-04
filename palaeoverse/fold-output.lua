local function wrap(div)
  return {
    pandoc.RawBlock("html", "<details><summary>Output</summary>"),
    div,
    pandoc.RawBlock("html", "</details>")
  }
end

function Div(el)
  -- Opt-in: only chunks with the class "fold-output"
  if el.classes:includes("cell") and el.classes:includes("fold-output") then
    return el:walk({
      Div = function(d)
        if d.classes:includes("cell-output") then
          return wrap(d)
        end
      end
    })
  end
end
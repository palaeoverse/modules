# Turns one Lighthouse JSON report into the Markdown section for a page, used by
# "accessibility.yml". Takes the page path and the .qmd it came from as --arg.
#
# Usage: jq -r --arg page <html> --arg src <qmd> -f lighthouse-report.jq report.json

def items: (.details.items // []);

"### `" + $page + "` <sub>rendered from `" + $src + "`</sub>",
"",
"Accessibility score: **" +
  (if .categories.accessibility.score == null then "n/a"
   else ((.categories.accessibility.score * 100) | round | tostring) + " / 100"
   end) + "**",
"",
( [.audits[] | select(.score != null and .score < 1)] as $failed
  | if ($failed | length) == 0 then
      ":white_check_mark: No accessibility issue detected."
    else
      ( $failed[]
        | "<details><summary><b>" + .title + "</b> — " +
            ((items | length) | tostring) + " element(s)</summary>",
          "",
          .description,
          "",
          ( items[:5][] | "```html\n" + (.node.snippet // "") + "\n```" ),
          ( if (items | length) > 5
            then "_… and " + (((items | length) - 5) | tostring) + " more element(s)._"
            else empty
            end ),
          "</details>"
      )
    end
),
""

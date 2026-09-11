# Palaeoverse Modules

Directory of teaching modules built by the Palaeoverse team.

# Building a module

Every module should contain Quarto (.qmd) content that renders a long-form website page (for async learning) plus a reveal.js slide deck (for live teaching). There are many ways to accomplish this; we've outlined and templated the three strategies that we think work well below. Pick one of them and start from its template in
[`_templates`](_templates):

| | Strategy | Start from |
| --- | --- | --- |
| 1 | **One file, slide layout by filter.** A single `index.qmd` registers the [`web_and_slides.lua`](web_and_slides.lua) filter, which turns your prose into speaker notes and breaks the remaining content into slides for you (ideal if you are new to Quarto). | [`template_single_file.qmd`](_templates/template_single_file.qmd) |
| 2 | **One file, interleaved by hand.** A single `index.qmd` using plain Quarto conditional content (ideal if you are comfortable with Quarto syntax and don't have too many customizations). | [`template_single_file_interleaved.qmd`](_templates/template_single_file_interleaved.qmd) |
| 3 | **Two separate files.** A long-form document and a slide deck, maintained side by side (ideal if you really need customized content for both formats). | [`template_long_format.qmd`](_templates/template_long_format.qmd) + [`template_slides.qmd`](_templates/template_slides.qmd) |

Strategies 1 and 2 render one file to both formats, so Quarto links the page and
the deck for you under "Other Formats". Strategy 3 renders two independent
documents, so the long-form file has to point at the deck itself with an
`other-links:` entry (see the template for an example).

## 1. One file, slide layout by the Lua filter

_Best when the page and the deck say the same things in the same order._

Write `index.qmd` once, marking prose with `.narration` and the occasional
divergence with `.slides-only` / `.html-only`; the filter does the rest (see
[Authoring a module](#authoring-a-module) below for the classes and the slide
layout it applies). You can get there two ways:

- **Tag as you go.** Copy [`template_single_file.qmd`](_templates/template_single_file.qmd)
  and write with the blocks from the start.
- **Write long-form first, then convert.** Draft the module as an ordinary
  written tutorial (see [`template_single_file_draft.qmd`](_templates/template_single_file_draft.qmd) for an example)
  and run `web_and_slides.r` over it once:

  ```sh
  Rscript web_and_slides.r mymodule/index.qmd.orig mymodule/index.qmd
  quarto render mymodule/index.qmd
  ```

  Then clean up by hand: act on any headings the script flagged, and add
  `.slides-only` / `.html-only` blocks where the outputs should diverge.

The script is meant as a **single pass once the long-form version is finished**,
though in principle it can be run repeatedly. Once
you start hand-editing the converted file, keep editing that file. If you would
rather keep iterating on the prose, keep it alongside as `index.qmd.orig` and
regenerate.

Once the filter is registered and copied into the module directory, you get the
following automatic behavior:

 - slides close after each figure
 - deeper headings become their own slides
 - callouts keep their boxes (and collapsed callouts stay collapsed)
 - content on long slides is shrunk as needed
 - back-to-back code chunks are revealed one at a time

## 2. One file, interleaved by hand

_Best when you want the slides laid out exactly as you wrote it, with no filter in
the way._

Same single-file idea, but using Quarto's own conditional content instead of our
classes, so there is nothing to generate and nothing to register:

| Class | Behavior |
| --- | --- |
| `::: {.notes}` |  Quarto renders it as prose on the page and as speaker notes in the slide deck |
| `::: {.content-visible when-format="revealjs"}` | Content is only rendered on the slides, not on the page |
| `::: {.content-hidden when-format="revealjs"}` | Content is only rendered on the page, not on the slides |

In exchange for the control you take on the work the
filter was doing: slides do not close after a figure, deeper headings do not
become their own slides, callouts keep their boxes, and long slides need
`{.smaller}` or `{.scrollable}`. You can reveal your own content with `. . .`,
`::: {.fragment}` or `::: {.incremental}`.

## 3. Two separate files

_Best when the tutorial and the talk genuinely differ (e.g., different order,
different examples, different depth)._

Keep a long-form `index.qmd` and a separate slide deck whose `output-file:` is
`index-slides.html`, and maintain them independently. Nothing links them
automatically, so the long-form file needs the `other-links:` entry shown in
[`template_long_format.qmd`](_templates/template_long_format.qmd). Anything the
two share has to be kept in sync by hand.

# Authoring a module with the Lua filter

This section covers **strategy 1** in detail: the front matter is much the same
whichever strategy you pick, but the classes and the automation below come from
the two files at the root of this repo.

| File | Role |
| --- | --- |
| `web_and_slides.lua` | Pandoc/Quarto filter, applied at render time. Decides what appears on the website, what appears on the slides, and how the slides are broken up. |
| `web_and_slides.r` | One-shot authoring helper. Converts a finished long-form document into the tagged form the filter expects. |

## Front matter

Start from an existing module (`ggplot/index.qmd` is a good template). These
fields matter:

```yaml
---
title: "Plotting in R with ggplot2"
description: "Visualizing your data with the grammar of graphics"
author: "Will Gearty"
date: "2026-06-12"
categories: [r, tidyverse, dataviz]   # various tags
difficulty: Beginner                  # Beginner/Intermediate/Advanced
image: images/2d_density.png          # thumbnail for module
format:
  html: default
  revealjs:
    smaller: true
    output-file: index-slides.html    # the deck, alongside the page
execute:
  output-location: fragment           # slide output reveals on click
  echo: true
  freeze: auto                        # must be auto, not true
filters:
  - at: pre-ast
    path: web_and_slides_autogenerated.lua
---
```

`difficulty`, `categories` and `freeze: auto` are enforced by CI (see
[Technical summary](#technical-summary)). The `filters` entry is what activates
everything below; `web_and_slides.r` adds it for you, or you can copy it.

## Writing for two outputs

Three fenced-div (`:::`) classes control where content lands:

| Class | Website Tutorial | Slides |
| --- | --- | --- |
| `.narration` | normal prose | speaker notes |
| `.slides-only` | dropped | shown on the slide |
| `.html-only` | shown | dropped |

Anything not wrapped in one of these appears in both outputs. So the usual shape
of a module is: headings and code chunks shared by both outputs, the connecting
prose in `.narration` (a paragraph on the page, a note you talk from on the
slide), and the occasional `.slides-only` bullet summary or `.html-only` aside.

````markdown
## Making a scatter plot

::: {.narration}
On the website this is a paragraph of explanation. On the slides it is what you
say out loud while the plot is up.

Consecutive paragraphs can share one block.
:::

::: {.slides-only}
-   x is body mass
-   y is flipper length
:::

```{r}
ggplot(penguins) +
  aes(x = body_mass, y = flipper_len) +
  geom_point()
```
````

## Automated slide rendering via `web_and_slides.lua`

The following changes are applied to the reveal.js slides via our custom Lua filter:

- **Headings become slides:** `##` starts a slide as usual; `###` and deeper are
  promoted so each also gets its own slide, instead of piling onto the parent.
  A `#` heading becomes a centered divider slide, so don't put content under one.
- **One plot per slide:** The slide closes after each figure. Prose that follows
  a figure moves to the next slide (introducing it), unless nothing but prose
  remains before the next heading — then it stays put rather than making a blank
  slide. Split slides repeat the current heading, so they keep a title.
- **Callouts get their own slide:** A callout is un-boxed onto a slide of its
  own, titled by its own heading. Give a callout a `## Heading` as its first line
  (rather than `title="..."`) if you want that title on the slide; an untitled
  callout keeps the section title.
- **Collapsed callouts stay hidden:** A callout with `collapse="true"` keeps its
  box and title instead of being un-boxed, and its body is held back as a
  reveal.js fragment, so a solution is revealed on the next advance rather than
  given away. This applies wherever the callout sits, including inside a broader
  callout. (reveal.js ignores Quarto's own `collapse`, hence the fragment.)
- **Multi-chunk slides build up:** A slide holding two or more code chunks is
  expanded into an auto-animate sequence: one step per chunk, earlier chunks
  staying on screen, and the notes for each chunk advancing with it.

Preview both outputs with:

```sh
quarto render ggplot/index.qmd     # -> index.html and index-slides.html
```

## `web_and_slides.r` Helper

The `web_and_slides.r` helper file takes a long-form document and mechanically prepares it:

```sh
Rscript web_and_slides.r <input.qmd> [output.qmd]
    [--filter=<path/to/filter.lua>] [--no-inject] [--no-settings]
```

It does the following:

1. Wraps each set of consecutive prose paragraphs in a single
   `::: {.narration}` block. Headings, code chunks, lists, blockquotes,
   tables, standalone images, and existing fenced divs (including callouts and
   everything inside them) are left untouched.
2. Registers the filter in the front matter at the `pre-ast` stage, replacing any
   earlier registration. `--no-inject` skips this; `--filter=` names a different
   file.
3. Sets slide-friendly YAML (skip with `--no-settings`):
   - adds `execute.echo: true` (renders source code on slides)
   - adds `execute.output-location: fragment` (renders code results as separate chunk)
   - adds `format.revealjs.smaller: true` (text shrinks to fit on slides)
   - removes `format.revealjs.scrollable` (disables scrolling through slides)
4. Reports headings that will render awkwardly (e.g., `#` become centered title slides).
   You should fix these by hand.

The front matter is checked for valid YAML before anything is written. Needs the
`readr`, `stringr`, `yaml`, and `fs` packages.

With no `output.qmd` specified it rewrites the input in place.

# Additional references:

- Quarto tutorial ([with Positron](https://quarto.org/docs/get-started/hello/positron.html) | [with RStudio](https://quarto.org/docs/get-started/computations/rstudio.html))
- [Markdown basics in Quarto](https://quarto.org/docs/authoring/markdown-basics.html)
- [HTML basics in Quarto](https://quarto.org/docs/output-formats/html-basics.html)
- [Revealjs in Quarto](https://quarto.org/docs/presentations/revealjs/)
- [Quarto Listings](https://quarto.org/docs/websites/website-listings.html)

-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
--
-- What Écrivain needs that a stylesheet cannot do, in three passes after `common':
--
-- - the title block: the author and date become a block, since the page only hears of
--   the title;
-- - the seeds: each framed block (alert, code, table, figure) gets data-ecrivain-seed, 0
--   to 7, which picks its hand-drawn strokes and its tilt.  The seed comes from the id of
--   the nearest heading, the block's kind and its rank among its kind in that section,
--   never its text: typing inside a block does not redraw its frame, a new block disturbs
--   only its own section, and neighbours of a kind never share one;
-- - the whole blocks: what cannot be a whole number of writing lines (code, a table, a
--   picture or film, a drawing, a formula) goes in .ecrivain-snap, which the sheet rounds
--   up to the grid; a long listing or table is marked .ecrivain-long, a long quotation or
--   alert .ecrivain-long-bloc, since a box taller than a leaf could only go past every
--   leaf.

local stringify = pandoc.utils.stringify

local alert_kinds = { note = true, tip = true, warning = true, caution = true, important = true }

-- A listing or a table longer than this flows around the leaves' bands; the shortest leaf
-- holds 27 lines of 32 px, so 40 lines of 21 px would not fit it.
local long_lines = 36
local long_rows = 18
-- About fifteen lines at the narrowest measure a leaf has.
local long_letters = 1000

-- The block inside a wrapper, or the block itself.
local function unwrapped(block)
  if block.t == 'Div' and block.attributes.wrapper and #block.content == 1 then
    return block.content[1]
  end
  return block
end

local title_block = {
  Pandoc = function(doc)
    local lines = pandoc.Blocks({})
    for _, name in ipairs({ 'date', 'author' }) do
      if doc.meta[name] then
        local words = pandoc.Inlines(stringify(doc.meta[name]))
        lines:insert(pandoc.Para({ pandoc.Span(words, { class = 'ecrivain-' .. name }) }))
      end
    end
    if #lines > 0 then doc.blocks:insert(1, pandoc.Div(lines, { class = 'ecrivain-titre' })) end
    return doc
  end,
}

-- The walk that seeds the framed blocks of the section under the heading SECTION.
-- Three is odd, so successive ranks of a kind never share a seed of the eight.
local function seeding(section)
  local ranks = {}
  local function seed_of(kind)
    ranks[kind] = (ranks[kind] or 0) + 1
    local digest = pandoc.utils.sha1(section .. '|' .. kind)
    return tostring((tonumber(digest:sub(1, 6), 16) + 3 * ranks[kind]) % 8)
  end
  return {
    Table = function(block)
      block.attr.attributes['data-ecrivain-seed'] = seed_of('table')
      return block
    end,
    CodeBlock = function(block)
      if block.classes:includes('mermaid') then return nil end
      block.attributes['data-ecrivain-seed'] = seed_of('code')
      return block
    end,
    Figure = function(figure)
      figure.attr.attributes['data-ecrivain-seed'] = seed_of('figure')
      return figure
    end,
    Div = function(div)
      if not alert_kinds[div.classes[1]] then return nil end
      div.attributes['data-ecrivain-seed'] = seed_of('alert')
      return div
    end,
  }
end

local seeds = {
  Pandoc = function(doc)
    local out = pandoc.Blocks({})
    local filter = seeding('')
    for _, block in ipairs(doc.blocks) do
      local inner = unwrapped(block)
      if inner.t == 'Header' then filter = seeding(inner.identifier) end
      out:extend(pandoc.Blocks({ block }):walk(filter))
    end
    doc.blocks = out
    return doc
  end,
}

-- The child of .ecrivain-snap that holds BLOCK, marked long when LONG.
local function snapped(block, long)
  if long then block = pandoc.Div({ block }, { class = 'ecrivain-long' }) end
  return pandoc.Div({ block }, { class = 'ecrivain-snap' })
end

local function is_formula(inline)
  return inline.t == 'Math' and inline.mathtype == 'DisplayMath'
end

-- The blocks of the paragraph PARA with each formula on the grid by itself; a part that
-- follows a formula goes on with no fresh alinéa.
local function formulas_apart(para)
  local parts, words = pandoc.Blocks({}), pandoc.Inlines({})
  local function flush()
    while words[#words] and words[#words].t == 'Space' do words:remove() end
    if #words > 0 then
      local part = pandoc.Para(words)
      parts:insert(#parts > 0 and pandoc.Div({ part }, { class = 'ecrivain-suite' }) or part)
    end
    words = pandoc.Inlines({})
  end
  for _, inline in ipairs(para.content) do
    if is_formula(inline) then
      flush()
      parts:insert(snapped(pandoc.Para({ inline })))
    elseif #words > 0 or inline.t ~= 'Space' then
      words:insert(inline)
    end
  end
  flush()
  return parts
end

local function line_count(code)
  return select(2, code.text:gsub('\n', '\n')) + 1
end

-- What each kind of block needs to sit on the grid: the blocks for BLOCK, or nil for BLOCK
-- itself.  INNER is what its wrapper holds, or BLOCK.
local rules = {
  Para = function(block, inner)
    if not pandoc.List(inner.content):find_if(is_formula) then return nil end
    if block == inner then return formulas_apart(inner) end
    block.content = formulas_apart(inner)
    return nil
  end,
  -- Code with no language sits in .imprimeur-code, the next rule's.
  CodeBlock = function(block, inner)
    if #inner.classes == 0 then return nil end
    local diagram = inner.classes:includes('mermaid')
    return { snapped(block, not diagram and line_count(inner) > long_lines) }
  end,
  Div = function(block, inner)
    if inner.classes:includes('imprimeur-code') then
      return { snapped(block, line_count(inner.content[1]) > long_lines) }
    end
    if alert_kinds[inner.classes[1]] and #stringify(inner) > long_letters then
      inner.classes:insert('ecrivain-long-bloc')
    end
    return nil
  end,
  Table = function(block, inner)
    local rows = #inner.head.rows
    for _, body in ipairs(inner.bodies) do rows = rows + #body.body + #body.head end
    return { snapped(pandoc.Div({ block }), rows > long_rows) }
  end,
  BlockQuote = function(block, inner)
    if #stringify(inner) <= long_letters then return nil end
    return { pandoc.Div({ block }, { class = 'ecrivain-long-bloc' }) }
  end,
}

local whole_blocks = {
  Figure = function(figure)
    figure.content = pandoc.Blocks({ snapped(pandoc.Div(figure.content)) })
    return figure
  end,

  Blocks = function(blocks)
    local out = pandoc.Blocks({})
    for _, block in ipairs(blocks) do
      local inner = unwrapped(block)
      local rule = rules[inner.t]
      out:extend(rule and rule(block, inner) or { block })
    end
    return out
  end,
}

return { title_block, seeds, whole_blocks }

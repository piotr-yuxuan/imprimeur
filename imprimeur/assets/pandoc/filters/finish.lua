-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
--
-- The last filter of every render, after a skin's.  So a filter sets the title
-- and the language like any metadata, wraps a block or inserts one anywhere, and
-- never sees what is written here:
--
-- - each top-level block with no data-pos of its own takes, as an empty element
--   before it, the line first named on or inside it, in document order, by
--   data-imprimeur-line or data-pos; the page makes that a data-line on the block;
-- - no data-imprimeur-line stays, and the wrapper of an Org block goes unless a
--   filter gave it a class, so that the page holds what it would without filters;
-- - the title and the language precede the document, after a marker line, as one
--   line of JSON that Emacs reads and removes.  They come first because pandoc
--   writes some blocks, such as the footnotes, after the last one, and a document
--   cannot write before the first block.  The language then leaves the metadata,
--   as pandoc warns of any it has no translations for.

local stringify = pandoc.utils.stringify

local line_attribute = 'data-imprimeur-line'

-- The line first named in the block under walk, as digits.
local found = nil

-- The least line of POS, a data-pos value, whose ranges are not in line order.
local function first_line(pos)
  local least = nil
  for line in (pos or ''):gmatch('(%d+):%d+%-%d+:%d+') do
    if not least or tonumber(line) < tonumber(least) then least = line end
  end
  return least
end

local function visit(element)
  local attributes = element.attributes
  local written = attributes[line_attribute]
  found = found or (written and written:match('^%d+$')) or first_line(attributes['data-pos'])
  if not written then return nil end
  attributes[line_attribute] = nil
  if element.t == 'Div' and attributes.wrapper and #element.classes == 0 and #element.content <= 1 then
    return element.content
  end
  return element
end

local every_element = {
  traverse = 'topdown',
  Div = visit, Header = visit, CodeBlock = visit, Table = visit, Figure = visit,
  Span = visit, Code = visit, Link = visit, Image = visit,
}

return { {
  Pandoc = function(doc)
    local meta = doc.meta
    local blocks = pandoc.Blocks({})
    for _, block in ipairs(doc.blocks) do
      local own = block.attributes and block.attributes['data-pos']
      found = nil
      local walked = pandoc.Blocks({ block }):walk(every_element)
      if found and not own then
        blocks:insert(pandoc.RawBlock('html', '<div ' .. line_attribute .. '="' .. found .. '"></div>'))
      end
      blocks:extend(walked)
    end
    blocks:insert(1, pandoc.RawBlock('html', '<!--imprimeur-meta-->\n' .. pandoc.json.encode({
      title = stringify(meta.title or ''),
      lang = stringify(meta.lang or ''),
    })))
    meta.lang = nil
    return pandoc.Pandoc(blocks, meta)
  end,
} }

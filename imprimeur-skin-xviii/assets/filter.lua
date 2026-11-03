-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
--
-- What the XVIII skin needs that a stylesheet cannot do, after the shared filters
-- common, french and hyphenate:
--
-- - the first paragraph of a chapter or of a titled document takes a lettrine: an empty
--   frame that raises the capital without its diacritics, by data-xviii-forme, with the
--   document's own letter kept in the line for copying and searching.  The rest of the
--   first word takes a span, for small capitals.  Never after a sign;
-- - a heading of the first two levels takes an empty span, whose stop the sheet draws,
--   unless it ends in a sign;
-- - a picture alone in its paragraph, which common leaves without a figure as it has no
--   description, takes a class, and the sheet frames it;
-- - the sub-title, the author and the date become a block, since the page hears only of
--   the title.  A date that is a year from 1000 to 1899 stays the document's text, and
--   the imprint that the sheet draws is an attribute.
--
-- first_str and imprint parse what a document wrote; with_lettrine is judged by a table
-- of openers in the tests.

local stringify = pandoc.utils.stringify

-- The shape that a lettrine raises, by the letter that the document wrote.
local shape_of = {
  ['À'] = 'A', ['Â'] = 'A', ['Ä'] = 'A', ['Å'] = 'A', ['Ç'] = 'C', ['È'] = 'E',
  ['É'] = 'E', ['Ê'] = 'E', ['Ë'] = 'E', ['Î'] = 'I', ['Ï'] = 'I', ['Ô'] = 'O',
  ['Ö'] = 'O', ['Ù'] = 'U', ['Û'] = 'U', ['Ü'] = 'U', ['Ÿ'] = 'Y',
  ['Æ'] = 'Æ', ['Œ'] = 'Œ',
}
for code = 65, 90 do shape_of[string.char(code)] = string.char(code) end

-- The inlines that may hold the first word of a lettrine in their first text.
local holders = { Emph = true, Strong = true }

-- A combining mark, U+0300 to U+036F, in UTF-8: a decomposed É is an E and one.
local combining_marks = '^[\204\205][\128-\191]'

-- The block inside a wrapper, or the block itself.
local function unwrapped(block)
  if block and block.t == 'Div' and block.attributes.wrapper and #block.content == 1 then
    return block.content[1]
  end
  return block
end

-- The Str that holds BLOCK's first letter, when it is a paragraph, and whether it stands
-- in an emphasis or an inversion: a parser of what the document wrote.
local function first_str(block)
  local first = block and block.t == 'Para' and block.content[1]
  if not first then return nil end
  if first.t == 'Str' then return first, false end
  local wraps = holders[first.t] or (first.t == 'Span' and first.classes:includes('imprimeur-inversion'))
  if wraps and first.content[1] and first.content[1].t == 'Str' then return first.content[1], true end
  return nil
end

-- What a lettrine does to PARA, when it may take one: a frame raising the shape, then the
-- document's own text kept in the line.  The rest of a word passes into small capitals, and
-- the space after a word of one letter goes in with that letter.
local function with_lettrine(para)
  local str, wrapped = first_str(para)
  local letter = str and str.text:match(utf8.charpattern)
  local shape = letter and shape_of[letter]
  if not shape then return end
  local marked = letter .. (str.text:match(combining_marks, #letter + 1) or '')
  local rest, kept = str.text:sub(#marked + 1), { pandoc.Str(marked) }
  local inlines = para.content
  if wrapped then
    str.text = rest
  elseif rest ~= '' then
    inlines[1] = pandoc.Span({ pandoc.Str(rest) }, { class = 'xviii-premier-mot' })
  else
    inlines:remove(1)
    if inlines[1] and inlines[1].t == 'Space' then
      inlines:remove(1)
      table.insert(kept, pandoc.Space())
    end
  end
  para.content = pandoc.Inlines({
    pandoc.Span({}, pandoc.Attr('', { 'xviii-lettrine' }, { { 'data-xviii-forme', shape } })),
    pandoc.Span(kept, { class = 'xviii-lettrine-texte' }),
  }) .. inlines
end

local lettrines = {
  Blocks = function(blocks)
    for index = 2, #blocks do
      local previous = unwrapped(blocks[index - 1])
      if previous.t == 'Header' and previous.level == 1 then with_lettrine(unwrapped(blocks[index])) end
    end
    return blocks
  end,

  -- The filter common makes a lone first heading the title, so no heading stays before
  -- this paragraph.  Here, since Blocks sees the nested lists too.
  Pandoc = function(doc)
    if doc.meta.title then with_lettrine(unwrapped(doc.blocks[1])) end
    return doc
  end,
}

local stops = {
  Header = function(header)
    local words = stringify(header.content)
    if header.level > 2 or words:match('[%.%?!:;]$') or words:sub(-3) == '…' then return nil end
    header.content:insert(pandoc.Span({}, { class = 'xviii-point' }))
    return header
  end,
}

local lone_pictures = {
  Para = function(para)
    local image = #para.content == 1 and para.content[1]
    if image and image.t == 'Image' then
      image.classes:insert('xviii-seule')
      return para
    end
    return nil
  end,
}

local hundreds = { 'C', 'CC', 'CCC', 'CD', 'D', 'DC', 'DCC', 'DCCC' }
local tens = { [0] = '', 'X', 'XX', 'XXX', 'XL', 'L', 'LX', 'LXX', 'LXXX', 'XC' }
local units = { [0] = '', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX' }

-- DATE as an imprint sets it, M. DCC. LIX., when it is a year from 1000 to 1899, and
-- otherwise nil: a parser of what the document wrote.
local function imprint(date)
  local c, x, i = date:match('^1([0-8])(%d)(%d)$')
  if not c then return nil end
  local parts = { 'M' }
  if c ~= '0' then parts[#parts + 1] = hundreds[tonumber(c)] end
  if x ~= '0' or i ~= '0' then parts[#parts + 1] = tens[tonumber(x)] .. units[tonumber(i)] end
  return table.concat(parts, '. ') .. '.'
end

-- A line of the title block, in LINES, when VALUE says anything; return what it says.
local function title_line(lines, value, class)
  local text = stringify(value or '')
  if text ~= '' then
    lines:insert(pandoc.Para({ pandoc.Span({ pandoc.Str(text) }, { class = class }) }))
  end
  return text
end

local title_block = {
  Pandoc = function(doc)
    local lines = pandoc.Blocks({})
    title_line(lines, doc.meta.subtitle, 'xviii-sous-titre')
    title_line(lines, doc.meta.author, 'xviii-auteur')
    local roman = imprint(title_line(lines, doc.meta.date, 'xviii-date'))
    if roman then lines[#lines].content[1].attributes['data-xviii-imprint'] = roman end
    if #lines > 0 then doc.blocks:insert(1, pandoc.Div(lines, { class = 'xviii-titre' })) end
    return doc
  end,
}

return { lettrines, stops, lone_pictures, title_block }

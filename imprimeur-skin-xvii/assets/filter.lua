-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
--
-- What the XVII skin needs that a stylesheet cannot do, after the shared filters
-- common, french and hyphenate, in the order of the passes at the end of this file:
--
-- - each note is also written where it is called, as a manchette, and the sheet shows
--   that or the note at the end of its section.  A note called where no manchette can
--   stand, from a heading, a table, a figure or a verse, is marked, and keeps its place;
-- - a century holds the document's capitals in a span, and says its lower case by an
--   attribute, which is what a family of small capitals alone can show;
-- - a heading that ends in a sign of its own takes a class, and no full stop;
-- - a picture alone in its paragraph, which common leaves without a figure as it has no
--   description, takes a class, and the sheet frames it;
-- - the first paragraph of a chapter or of a titled document takes a block initial: an
--   empty span whose attribute holds the shape to show, without its diacritics, and a
--   class when EB Garamond Initials lacks that letter.  The document keeps its letter and
--   the rest of the first word in the line, at no size, where copying and searching read
--   them, and an attribute gives the capitals that the sheet draws;
-- - a numbered chapter's heading takes an empty span for its label, and an end-piece
--   closes each chapter;
-- - the title, sub-title, author, address and date become a title page.  A date that is a
--   year from 1000 to 1899 stays the document's text, and the imprint is an attribute;
-- - the s before a hyphen goes in a span, which the sheet keeps round: EB Garamond 12
--   counts a hyphen as a letter of its long s's context.
--
-- with_initial, initial_of, imprint, title_parts and names_line parse what a document
-- wrote, and are judged by tables in the tests.

local stringify = pandoc.utils.stringify

local soft_hyphen = '\u{AD}'

-- The shape that an initial shows, by the letter that the document wrote.
local shape_of = {
  ['À'] = 'A', ['Â'] = 'A', ['Ä'] = 'A', ['Å'] = 'A', ['Ç'] = 'C', ['È'] = 'E',
  ['É'] = 'E', ['Ê'] = 'E', ['Ë'] = 'E', ['Î'] = 'I', ['Ï'] = 'I', ['Ô'] = 'O',
  ['Ö'] = 'O', ['Ù'] = 'U', ['Û'] = 'U', ['Ü'] = 'U', ['Ÿ'] = 'Y',
  ['Æ'] = 'Æ', ['Œ'] = 'Œ',
}
for code = 65, 90 do shape_of[string.char(code)] = string.char(code) end

-- What EB Garamond Initials holds, by fc-query; the others stand in.
local engraved = {
  A = true, D = true, F = true, G = true, L = true, N = true, O = true, Q = true, T = true, X = true,
}

-- A combining mark, U+0300 to U+036F, in UTF-8: a decomposed É is an E and one.
local combining_marks = '^[\204\205][\128-\191]'

-- The inlines that may hold the first word of an initial in their first text.
local holders = { Emph = true, Strong = true }

-- Small words before which a title breaks into its two sizes, by language.  A word that
-- elides stands as its elision.
local title_breaks = {
  fr = { de = true, du = true, des = true, sur = true, pour = true, ["d'"] = true, ['d’'] = true },
  en = { of = true, on = true, ['for'] = true, ['in'] = true, a = true, the = true },
}

local conjunctions = { fr = ' et ', en = ' and ' }

-- The block inside a wrapper, or the block itself.
local function unwrapped(block)
  if block and block.t == 'Div' and block.attributes.wrapper and #block.content == 1 then
    return block.content[1]
  end
  return block
end

local function is_chapter(block)
  local inner = unwrapped(block)
  return inner and inner.t == 'Header' and inner.level == 1
end

-- A note that no manchette can show says so, for the sheet.
local function without_manchette(note)
  note.content:insert(1, pandoc.Plain({ pandoc.Span({}, { class = 'xvii-sans-manchette' }) }))
  return note, false
end

local function marked_notes(block)
  return block:walk({ Note = without_manchette }), false
end

-- BLOCK with a manchette beside each note it calls, however deep the call.
local function with_manchettes(block)
  return block:walk({
    Inlines = function(inlines)
      local out = pandoc.Inlines({})
      for _, inline in ipairs(inlines) do
        out:insert(inline)
        if inline.t == 'Note' then
          out:insert(pandoc.Span(pandoc.utils.blocks_to_inlines(inline.content),
            { class = 'xvii-manchette', role = 'note' }))
        end
      end
      return out
    end,
  }), false
end

local manchettes = {
  traverse = 'topdown',
  Table = marked_notes,
  Figure = marked_notes,
  Para = with_manchettes,
  Plain = with_manchettes,
  Note = without_manchette,
}

local centuries = {
  Span = function(span)
    local letters = span.content[1]
    if not (span.classes:includes('imprimeur-siecle') and letters and letters.t == 'Str') then return nil end
    span.attributes['data-xvii-basses'] = pandoc.text.lower(letters.text)
    span.content[1] = pandoc.Span({ letters }, { class = 'xvii-siecle-lettres' })
    return span
  end,
}

local stops = {
  Header = function(header)
    local words = stringify(header.content)
    if words:match('[%.%?!:;]$') or words:sub(-3) == '…' then
      header.classes:insert('xvii-ponctue')
      return header
    end
    return nil
  end,
}

local lone_pictures = {
  Para = function(para)
    local image = #para.content == 1 and para.content[1]
    if image and image.t == 'Image' then
      image.classes:insert('xvii-seule')
      return para
    end
    return nil
  end,
}

-- What TEXT, which opens a paragraph, shows as an initial, as inlines in its place; nil
-- when it starts with no capital: a parser of what the document wrote.
local function initial_of(text)
  local letter = text:match(utf8.charpattern)
  local shape = letter and shape_of[letter]
  if not shape then return nil end
  local marked = letter .. (text:match(combining_marks, #letter + 1) or '')
  local rest = text:sub(#marked + 1):gsub(soft_hyphen, '')
  local inlines = pandoc.Inlines({
    pandoc.Span({}, pandoc.Attr('', engraved[shape] and { 'xvii-initiale' } or { 'xvii-initiale', 'xvii-suppleante' },
      { { 'data-xvii-forme', shape } })),
    pandoc.Span({ pandoc.Str(marked) }, { class = 'xvii-lettre' }),
  })
  if rest ~= '' then
    inlines:insert(pandoc.Span({ pandoc.Str(rest) }, pandoc.Attr('', { 'xvii-premier-mot' },
      { { 'data-xvii-capitales', pandoc.text.upper(rest) } })))
  end
  return inlines
end

-- INLINES with an initial in place of their first letter, however it is emphasised, or nil.
local function with_initial(inlines)
  local first = inlines[1]
  local holds = first and (holders[first.t] or (first.t == 'Span' and first.classes:includes('imprimeur-inversion')))
  if holds then
    local content = with_initial(first.content)
    if not content then return nil end
    first.content = content
    inlines[1] = first
    return inlines
  end
  local initial = first and first.t == 'Str' and initial_of(first.text)
  if not initial then return nil end
  inlines:remove(1)
  return initial .. inlines
end

local initials = {
  Pandoc = function(doc)
    local blocks = doc.blocks
    for index, block in ipairs(blocks) do
      local para = unwrapped(block)
      local opens = is_chapter(blocks[index - 1]) or (index == 1 and doc.meta.title)
      local inlines = opens and para.t == 'Para' and with_initial(para.content)
      if inlines then
        para.content = inlines
        if block.t == 'Div' then
          block.classes:insert('xvii-lettrine')
        else
          blocks[index] = pandoc.Div({ para }, { class = 'xvii-lettrine' })
        end
      end
    end
    doc.blocks = blocks
    return doc
  end,
}

-- A heading that takes no number is no chapter, though it does close the one before.
local ornaments = {
  Pandoc = function(doc)
    local out, chapters = pandoc.Blocks({}), 0
    local end_piece = pandoc.Div({}, { class = 'xvii-cul-de-lampe' })
    for _, block in ipairs(doc.blocks) do
      if is_chapter(block) then
        if chapters > 0 then out:insert(end_piece) end
        local header = unwrapped(block)
        if not header.classes:includes('unnumbered') then
          header.content:insert(1, pandoc.Span({}, { class = 'xvii-chapitre' }))
          chapters = chapters + 1
        end
      end
      out:insert(block)
    end
    if chapters > 0 then out:insert(end_piece) end
    doc.blocks = out
    return doc
  end,
}

local hundreds = { 'C', 'CC', 'CCC', 'CD', 'D', 'DC', 'DCC', 'DCCC' }
local tens = { [0] = '', 'X', 'XX', 'XXX', 'XL', 'L', 'LX', 'LXX', 'LXXX', 'XC' }
local units = { [0] = '', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX' }

-- DATE as an imprint sets it, M. DC. XXXVII., when it is a year from 1000 to 1899, and
-- otherwise nil: a parser of what the document wrote.
local function imprint(date)
  local c, x, i = date:match('^1([0-8])(%d)(%d)$')
  if not c then return nil end
  local parts = { 'M' }
  if c ~= '0' then parts[#parts + 1] = hundreds[tonumber(c)] end
  if x ~= '0' or i ~= '0' then parts[#parts + 1] = tens[tonumber(x)] .. units[tonumber(i)] end
  return table.concat(parts, '. ') .. '.'
end

-- TITLE as what stands alone in the large size, and the rest, or nil for a rest, by the
-- small words of BREAKS: a parser of what the document wrote.
local function title_parts(title, breaks)
  local words = {}
  for word in title:gmatch('%S+') do words[#words + 1] = word end
  for index = 2, #words do
    local lowered = pandoc.text.lower(words[index])
    local elision = lowered:match("^d'") or lowered:match('^d’')
    if breaks[lowered] or breaks[elision] then
      return table.concat(words, ' ', 1, index - 1), table.concat(words, ' ', index)
    end
  end
  return title, nil
end

-- VALUE, a metadata value that may be a list, of names or of maps with a name, as one
-- line: stringify alone would run the names together.  A parser of what the document wrote.
local function names_line(value, conjunction)
  if pandoc.utils.type(value) ~= 'List' then return stringify(value or '') end
  local names = {}
  for _, one in ipairs(value) do names[#names + 1] = stringify(type(one) == 'table' and one.name or one) end
  if #names < 2 then return names[1] or '' end
  return table.concat(names, ', ', 1, #names - 1) .. conjunction .. names[#names]
end

-- A line of the title page, in LINES, when TEXT says anything.
local function title_line(lines, text, attributes)
  if text and text ~= '' then
    lines:insert(pandoc.Para({ pandoc.Span({ pandoc.Str(text) }, attributes) }))
  end
end

local title_page = {
  Pandoc = function(doc)
    local meta = doc.meta
    local lines = pandoc.Blocks({})
    local language = stringify(meta.lang or ''):sub(1, 2)
    local conjunction = conjunctions[language] or ', '
    -- A document with no language counts as English, as for the shared filter hyphenate.
    local head, tail = title_parts(stringify(meta.title or ''), title_breaks[language == '' and 'en' or language] or {})
    local date = stringify(meta.date or '')
    title_line(lines, head, { class = 'xvii-titre-tete' })
    title_line(lines, tail, { class = 'xvii-titre-suite' })
    title_line(lines, stringify(meta.subtitle or ''), { class = 'xvii-sous-titre' })
    title_line(lines, names_line(meta.author, conjunction), { class = 'xvii-auteur' })
    title_line(lines, names_line(meta.institute, conjunction), { class = 'xvii-adresse' })
    title_line(lines, date, { class = 'xvii-date', ['data-xvii-imprint'] = imprint(date) })
    if #lines > 0 then doc.blocks:insert(1, pandoc.Div(lines, { class = 'xvii-titre' })) end
    return doc
  end,
}

local round_s = {
  traverse = 'topdown',
  Link = function(link)
    if stringify(link.content) == link.target then return link, false end
    return nil
  end,
  Str = function(str)
    if not str.text:find('s-', 1, true) then return nil end
    local pieces, start = pandoc.Inlines({}), 1
    for at in str.text:gmatch('()s%-') do
      if at > start then pieces:insert(pandoc.Str(str.text:sub(start, at - 1))) end
      pieces:insert(pandoc.Span({ pandoc.Str('s') }, { class = 'xvii-s-rond' }))
      start = at + 1
    end
    pieces:insert(pandoc.Str(str.text:sub(start)))
    return pieces
  end,
}

return { manchettes, centuries, stops, lone_pictures, initials, ornaments, title_page, round_s }

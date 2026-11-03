-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
--
-- What the skin Tianlu needs that a stylesheet cannot do, after the shared filter common, in
-- the order of the passes at the end of this file.
--
-- For every document:
--
-- - language reads the document's language, for every word below;
-- - document_keys takes the seal, end seal, colophon and lunar date from Org's keywords,
--   as a Markdown document has them in its metadata;
-- - headnotes moves a headnote into the paragraph it glosses;
-- - plain_pictures makes a figure of a picture alone with no description, as a band has no
--   place for a picture in a column;
-- - display_maths and code_plates give a formula and a code block a plate, with a length
--   for the sheet's whole columns, and cut a code block every 18 lines;
-- - tables marks a wide table, which becomes a plate, and gives a tall one each column's
--   width in cells;
-- - diagram_captions takes 图： after a diagram, which common leaves;
-- - slots puts a slot around each plate;
-- - end_titles, title_block and colophon write what closes a juan, opens the document and
--   closes it.
--
-- For a document in Chinese, the pass chinese walks the blocks alone, so that the marks of a
-- title stay as written: ruby, quotation, runs, blanks, latin, latin_link, notes, ellipsis
-- and alerts turn the quotation marks, take out the spaces beside a Chinese character, mark
-- Latin and upright digits, and set notes as boxes of two lines in place.
--
-- ruby_open, headnote_inlines, caption_of and lunar_date parse what a document wrote, and
-- quotes_turned and numeral are rules of their own, judged by tables in the tests.

local stringify = pandoc.utils.stringify

local alert_titles = {
  traditional = { note = '按', tip = '提示', important = '要旨', warning = '注意', caution = '慎之' },
  simplified = { note = '注', tip = '提示', important = '重要', warning = '注意', caution = '警告' },
}

-- The first level and the second, as each side quotes.  A vertical corner bracket is
-- the mainland's single quotation mark in vertical text, and its double one the 『』.
local quote_marks = {
  traditional = { ['“'] = '「', ['”'] = '」', ['‘'] = '『', ['’'] = '』' },
  simplified = { ['“'] = '『', ['”'] = '』', ['‘'] = '「', ['’'] = '」' },
}

-- The language, which language reads first: 'simplified', 'traditional' or nil.
local script = nil

local language = {
  Pandoc = function(doc)
    local lang = stringify(doc.meta.lang or '')
    script = nil
    if lang:match('^zh') then script = 'traditional' end
    for _, prefix in ipairs({ '^zh%-CN', '^zh%-Hans', '^zh%-SG' }) do
      if lang:match(prefix) then script = 'simplified' end
    end
    return nil
  end,
}

local han_ranges = { { 0x2E80, 0x9FFF }, { 0xF900, 0xFAFF }, { 0xFE10, 0xFE4F }, { 0xFF00, 0xFFEF },
                     { 0x20000, 0x3FFFF } }

local function is_han(code)
  if not code then return false end
  for _, range in ipairs(han_ranges) do
    if code >= range[1] and code <= range[2] then return true end
  end
  return false
end

local tone_marks = { [0x02C7] = 'ˇ', [0x02CA] = 'ˊ', [0x02CB] = 'ˋ' }

-- Tone marks and the ellipsis count as Chinese in Chinese text.  A curly quotation mark
-- that stays is beside Latin alone: the quotation pass has turned the others.
local function is_chinese(code)
  return is_han(code) or tone_marks[code] ~= nil or code == 0x02D9 or code == 0x2026 or code == 0x00B7
end

-- TEXT's width, where a Chinese character counts HAN and another OTHER.
local function width_of(text, han, other)
  local width = 0
  for _, code in utf8.codes(text, true) do
    width = width + (is_han(code) and han or other)
  end
  return width
end

local function first_code(text)
  return text ~= '' and utf8.codepoint(text, 1, 1, true) or nil
end

local function last_code(text)
  if text == '' then return nil end
  return utf8.codepoint(text, utf8.offset(text, -1), nil, true)
end

local function html_escape(text)
  return (text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'))
end

local function unwrapped(block)
  if block and block.t == 'Div' and block.attributes.wrapper and #block.content == 1 then
    return block.content[1]
  end
  return block
end

local function meta_text(meta, key)
  return meta[key] and stringify(meta[key]) or nil
end

-- A note's own inlines: a note has blocks, and a short one a single paragraph.
local function note_inlines(note)
  local out = pandoc.Inlines({})
  for _, block in ipairs(note.content) do
    if block.content and block.t ~= 'BulletList' and block.t ~= 'OrderedList' then
      out:extend(block.content)
    end
  end
  return out
end

-- What the skin takes from Org's keywords, one each; any other stays out of the page.
local document_key_names = { SEAL = 'seal', ENDSEAL = 'endseal', COLOPHON = 'colophon', LUNAR = 'lunar' }

local document_keys = {
  Pandoc = function(doc)
    local kept = pandoc.Blocks({})
    for _, block in ipairs(doc.blocks) do
      local inner = unwrapped(block)
      local key, value = nil, nil
      if inner.t == 'RawBlock' and inner.format == 'org' then
        key, value = inner.text:match('^#%+(%u+):%s*(.-)%s*$')
      end
      if document_key_names[key] then
        doc.meta[document_key_names[key]] = pandoc.MetaString(value)
      else
        kept:insert(block)
      end
    end
    doc.blocks = kept
    return doc
  end,
}

-- The inlines of BLOCK when it is a headnote, or nil.  Org gives a block, and GitHub
-- Markdown raw HTML, whose inside is a document's own Markdown.
local function headnote_inlines(block)
  local inner = unwrapped(block)
  if inner.t == 'Div' and inner.classes:includes('headnote') then
    return note_inlines(inner)
  end
  if inner.t == 'RawBlock' and inner.format:match('html') then
    local text = inner.text:match('^%s*<div class="headnote">(.-)</div>%s*$')
    if text then
      local first = pandoc.read(text, 'commonmark').blocks[1]
      return first and first.content or nil
    end
  end
  return nil
end

-- A headnote goes into the paragraph it glosses, as a span the sheet takes out of the flow:
-- a box out of the flow keeps its place where the flow stood, and that is the band before,
-- in WebKit, when its paragraph opens the next band.
local headnotes = {
  Pandoc = function(doc)
    local out, pending = pandoc.Blocks({}), nil
    for _, block in ipairs(doc.blocks) do
      local note = headnote_inlines(block)
      local para = unwrapped(block)
      if note then
        pending = note
      else
        if pending and para.t == 'Para' then
          para.content:insert(1, pandoc.Span(pending, { class = 'tianlu-headnote' }))
          pending = nil
        end
        out:insert(block)
      end
    end
    doc.blocks = out
    return doc
  end,
}

local plain_pictures = {
  Para = function(para)
    local picture = #para.content == 1 and para.content[1]
    if picture and picture.t == 'Image' then
      return pandoc.Figure({ pandoc.Plain({ picture }) })
    end
    return nil
  end,
}

local function plate(blocks, name, property, length)
  return pandoc.Div(blocks, pandoc.Attr('', { 'tianlu-plate', name }, { { 'style', property .. ':' .. length } }))
end

local display_maths = {
  Para = function(para)
    local formula = #para.content == 1 and para.content[1]
    if not formula or formula.t ~= 'Math' or formula.mathtype ~= 'DisplayMath' then return nil end
    local visible = formula.text:gsub('\\%a+', 'x'):gsub('[{}_^ ]', '')
    return plate({ para }, 'tianlu-math', '--tianlu-cells', math.ceil((utf8.len(visible) or 1) * 0.55))
  end,
}

-- A band holds 18 lines of code, whatever the size; each piece has a plate of its own, and
-- the first alone keeps the block's line.
local code_plates = {
  CodeBlock = function(block)
    if block.classes:includes('mermaid') then return nil end
    local lines, longest = {}, 0
    for line in (block.text .. '\n'):gmatch('(.-)\n') do
      table.insert(lines, line)
      longest = math.max(longest, width_of(line, 2, 1))
    end
    local out = pandoc.Blocks({})
    for first = 1, #lines, 18 do
      local piece = block:clone()
      piece.text = table.concat(lines, '\n', first, math.min(first + 17, #lines))
      if first > 1 then
        piece.identifier = ''
        piece.attributes['data-imprimeur-line'] = nil
        piece.attributes['data-pos'] = nil
      end
      out:insert(plate({ piece }, 'tianlu-code', '--tianlu-code-columns', longest))
    end
    return out
  end,
}

-- Each cell of ROWS takes the width of its column, for a tall table.
local function with_widths(rows, widths)
  for _, row in ipairs(rows) do
    for index, cell in ipairs(row.cells) do
      cell.attributes.style = '--tianlu-cells:' .. math.ceil(widths[index])
    end
  end
  return rows
end

-- A table goes horizontal when its columns, in cells, exceed what a column of text holds:
-- 16 of the 20 or 21 cells, with the space between them.
local tables = {
  Table = function(tbl)
    local widths, total = {}, 0
    local function measure(row)
      for index, cell in ipairs(row.cells) do
        widths[index] = math.max(widths[index] or 0, width_of(stringify(pandoc.Blocks(cell.contents)), 1, 0.55))
      end
    end
    for _, row in ipairs(tbl.head.rows) do measure(row) end
    for _, body in ipairs(tbl.bodies) do
      for _, row in ipairs(body.body) do measure(row) end
    end
    for _, width in ipairs(widths) do total = total + width + 1 end
    if total > 16 then
      tbl.classes:insert('tianlu-wide')
      return tbl
    end
    tbl.classes:insert('tianlu-tall')
    local head = tbl.head
    head.rows = with_widths(head.rows, widths)
    tbl.head = head
    local bodies = tbl.bodies
    for _, body in ipairs(bodies) do body.body = with_widths(body.body, widths) end
    tbl.bodies = bodies
    return tbl
  end,
}

-- The text of a paragraph that opens with 图：, or nil.
local function caption_of(block)
  local para = unwrapped(block)
  local first = para.t == 'Para' and para.content[1]
  if not first or first.t ~= 'Str' or first.text:sub(1, #'图：') ~= '图：' then return nil end
  local text = pandoc.Inlines({ table.unpack(para.content, 2) })
  local rest = first.text:sub(#'图：' + 1)
  if rest ~= '' then text:insert(1, pandoc.Str(rest)) end
  return text
end

local diagram_captions = {
  Blocks = function(blocks)
    local out = pandoc.Blocks({})
    for _, block in ipairs(blocks) do
      local diagram = unwrapped(out[#out])
      local caption = diagram and diagram.t == 'CodeBlock' and diagram.classes:includes('mermaid')
        and caption_of(block)
      if caption then
        out[#out] = pandoc.Div({ pandoc.Div({ pandoc.Plain(caption) }, { class = 'caption' }), out[#out] },
          { class = 'captioned-content' })
      else
        out:insert(block)
      end
    end
    return out
  end,
}

local function is_plate(block)
  if block.t == 'Figure' then return true end
  if block.t == 'Table' then return block.classes:includes('tianlu-wide') end
  if block.t == 'CodeBlock' then return block.classes:includes('mermaid') end
  if block.t == 'Div' then
    return block.classes:includes('tianlu-plate') or block.classes:includes('captioned-content')
  end
  return false
end

-- A plate sits in a slot, a block as wide as the plate, which reserves the band: a float that
-- does not fit overflows the band, in both engines, where a block that does not fit moves to
-- the next band with the float inside it.  The slot's negative margin brings the text back, to
-- run on below the float.  A slot stands at the top level, in the place of a wrapper or of
-- common's div.imprimeur-code, as WebKit runs later text under a float in such a box.
local function slotted(blocks)
  local out = pandoc.Blocks({})
  for _, block in ipairs(blocks) do
    local inner = unwrapped(block)
    if inner.t == 'Div' and inner.classes:includes('imprimeur-code') then
      out:extend(slotted(inner.content))
    elseif is_plate(inner) then
      -- The plate's length, if it has one, goes up to the slot, which needs it.
      local length = inner.t == 'Div' and inner.attributes.style
      if length then inner.attributes.style = nil end
      local slot = pandoc.Div({ inner }, { class = 'tianlu-slot' })
      if length then slot.attributes.style = length end
      slot.attributes['data-pos'] = block.attributes['data-pos']
      out:insert(slot)
    else
      out:insert(block)
    end
  end
  return out
end

local slots = {
  Pandoc = function(doc)
    doc.blocks = slotted(doc.blocks)
    return doc
  end,
}

-- What a 注音 annotation needs of the sheet, on its ruby: the symbols, the tone mark apart
-- from them, and how many there are, for the mark to sit beside the last.  WebKit will not
-- position an rt, so the page draws the annotation from these, and the rt stays in the
-- document.  Another annotation, pinyin say, is left as it is.
local function ruby_open(annotation)
  local first = first_code(annotation)
  if not first or not ((first >= 0x3105 and first <= 0x312F) or first == 0x02D9) then return '<ruby>' end
  local mark = tone_marks[last_code(annotation)]
  local stack = mark and annotation:sub(1, -(#mark + 1)) or annotation
  return string.format('<ruby data-tianlu-zhuyin="%s" data-tianlu-tone="%s" style="--tianlu-zhuyin-count:%d">',
    html_escape(stack), mark or '', utf8.len(stack))
end

local ruby = {
  -- Org's @@html: gives the whole ruby as one raw inline.
  RawInline = function(raw)
    if not raw.format:match('html') then return nil end
    local text = raw.text:gsub('<ruby>(.-)<rt>(.-)</rt>', function(base, annotation)
      return ruby_open(annotation) .. base .. '<rt>' .. annotation .. '</rt>'
    end)
    return pandoc.RawInline(raw.format, text)
  end,

  -- GitHub Markdown gives its tags apart, with the annotation as a Str between them.
  Inlines = function(inlines)
    local opening = nil
    for index, inline in ipairs(inlines) do
      if inline.t == 'RawInline' and inline.text == '<ruby>' then opening = index end
      if opening and inline.t == 'RawInline' and inline.text == '<rt>' and inlines[index + 1] then
        inlines[opening] = pandoc.RawInline('html', ruby_open(stringify(inlines[index + 1])))
        opening = nil
      end
    end
    return inlines
  end,
}

-- What an inline shows at its start or end, as a code point, or nil.
local function edge_code(inline, last)
  local text = inline and (inline.t == 'Str' and inline.text or (inline.content and stringify(inline)))
  if not text then return nil end
  return last and last_code(text) or first_code(text)
end

local quote_kinds = { [0x201C] = 'double', [0x201D] = 'double', [0x2018] = 'single', [0x2019] = 'single' }
local curly = { double = { [true] = '“', [false] = '”' }, single = { [true] = '‘', [false] = '’' } }

-- TEXT with its curly marks turned, by alternation: pandoc's +smart cannot tell the direction
-- beside a Han character, and gives “丁“.  A double mark always turns; a single one only beside
-- a Han character, since between Latin letters it is an apostrophe.  BEFORE and AFTER are the
-- code points around the text, or nil; STATE holds the marks and the open levels.
local function quotes_turned(text, before, after, state)
  local codes = {}
  for _, code in utf8.codes(text, true) do table.insert(codes, code) end
  local out = {}
  for index, code in ipairs(codes) do
    local kind = quote_kinds[code]
    if kind and (kind == 'double' or is_han(codes[index - 1] or before) or is_han(codes[index + 1] or after)) then
      state[kind] = not state[kind]
      table.insert(out, state.marks[curly[kind][state[kind]]])
    else
      table.insert(out, utf8.char(code))
    end
  end
  return table.concat(out)
end

-- The pass that turns quotation marks, in the Str and in the Quoted of a reader's +smart.
local quotation = {
  Inlines = function(inlines)
    local marks = quote_marks[script]
    local out, state = pandoc.Inlines({}), { marks = marks }
    for index, inline in ipairs(inlines) do
      if inline.t == 'Str' then
        inline.text = quotes_turned(inline.text, edge_code(inlines[index - 1], true),
          edge_code(inlines[index + 1], false), state)
        out:insert(inline)
      elseif inline.t == 'Quoted' then
        local double = inline.quotetype == 'DoubleQuote'
        out:insert(pandoc.Str(marks[double and '“' or '‘']))
        out:extend(inline.content)
        out:insert(pandoc.Str(marks[double and '”' or '’']))
      else
        out:insert(inline)
      end
    end
    return out
  end,
}

-- A Str's text in runs of Chinese and of anything else.
local runs = {
  Str = function(str)
    local out, current, chinese = pandoc.Inlines({}), {}, nil
    for _, code in utf8.codes(str.text, true) do
      local this = is_chinese(code)
      if chinese ~= nil and this ~= chinese then
        out:insert(pandoc.Str(table.concat(current)))
        current = {}
      end
      chinese = this
      table.insert(current, utf8.char(code))
    end
    if #out == 0 then return nil end
    out:insert(pandoc.Str(table.concat(current)))
    return out
  end,
}

-- A blank goes beside a Chinese character, or with nothing beside it, as at the end of a list
-- item: Org's markup needs one in the source.
local blanks = {
  Inlines = function(inlines)
    local kept = pandoc.Inlines({})
    for index, inline in ipairs(inlines) do
      local blank = inline.t == 'Space' or inline.t == 'SoftBreak'
      local before, after = edge_code(inlines[index - 1], true), edge_code(inlines[index + 1], false)
      if not (blank and (not before or not after or is_chinese(before) or is_chinese(after))) then
        kept:insert(inline)
      end
    end
    return kept
  end,
}

-- A run of Latin words and their spaces becomes one span; one or two digits alone an upright
-- pair.
local latin = {
  Inlines = function(inlines)
    local out, run = pandoc.Inlines({}), {}
    local function flush()
      while #run > 0 and run[#run].t == 'Space' do table.remove(run) end
      if #run > 0 then
        local digits = stringify(pandoc.Inlines(run)):match('^%d%d?$')
        out:insert(pandoc.Span(run, { class = digits and 'tianlu-tcy' or 'tianlu-lat' }))
      end
      run = {}
    end
    for _, inline in ipairs(inlines) do
      if (inline.t == 'Str' and not is_chinese(first_code(inline.text))) or (#run > 0 and inline.t == 'Space') then
        table.insert(run, inline)
      else
        flush()
        out:insert(inline)
      end
    end
    flush()
    return out
  end,
}

-- A link of Latin alone takes the class itself: in WebKit a span with a font of its own inside
-- a link leaves the column's centre.  common's <wbr> stands between the pieces of an address.
local latin_link = {
  Link = function(link)
    local inner = pandoc.Inlines({})
    for _, inline in ipairs(link.content) do
      if inline.t == 'Span' and inline.classes:includes('tianlu-lat') then
        inner:extend(inline.content)
      elseif inline.t == 'RawInline' and inline.text == '<wbr>' then
        inner:insert(inline)
      else
        return nil
      end
    end
    if #inner == 0 then return nil end
    link.classes:insert('tianlu-lat')
    link.content = inner
    return link
  end,
}

-- A sub-column holds as many half-size cells as a column has cells, 20 or 21, so a box of two
-- sub-columns holds 40: a longer note takes several boxes.
local note_box_length = 40

local notes = {
  -- The boxes of a note, in cells.  A Str is cut where a box fills; any other inline, a link or
  -- a piece of code, stays whole and starts a new box if it does not fit.
  Note = function(note)
    local boxes, current, used = pandoc.Inlines({}), pandoc.Inlines({}), 0
    local function close()
      if #current == 0 then return end
      -- A little over: the estimate is low for wide Latin letters, and a box clips.
      boxes:insert(pandoc.Span(current, pandoc.Attr('', { 'tianlu-note' },
        { { 'style', '--tianlu-note-cells:' .. math.ceil(used * 1.05) } })))
      current, used = pandoc.Inlines({}), 0
    end
    for _, inline in ipairs(note_inlines(note)) do
      if inline.t == 'Str' then
        local piece = {}
        for _, code in utf8.codes(inline.text, true) do
          if used >= note_box_length then
            if #piece > 0 then current:insert(pandoc.Str(table.concat(piece))) end
            piece = {}
            close()
          end
          table.insert(piece, utf8.char(code))
          used = used + (is_han(code) and 1 or 0.55)
        end
        if #piece > 0 then current:insert(pandoc.Str(table.concat(piece))) end
      else
        local width = width_of(stringify(inline), 1, 0.55)
        if used + width > note_box_length then close() end
        current:insert(inline)
        used = used + width
      end
    end
    close()
    return boxes
  end,

  -- An inline formula, in a span with its estimated length, for the sheet to turn it.
  Math = function(formula)
    if formula.mathtype ~= 'InlineMath' then return nil end
    local visible = formula.text:gsub('\\%a+', 'x'):gsub('[{}_^ ]', '')
    return pandoc.Span({ formula }, pandoc.Attr('', { 'tianlu-imath' },
      { { 'style', '--tianlu-cells:' .. math.ceil((utf8.len(visible) or 1) * 0.62) } }))
  end,
}

-- The ellipsis, in a span of its own, which the sheet turns the same way in every face: the
-- Ministry's Song has no vertical form of it, so WebKit turns it and leaves it off the column's
-- centre, and Chromium lays down the vertical form of the faces that have one.
local ellipsis = {
  Str = function(str)
    local out, rest = pandoc.Inlines({}), str.text
    local first, last = rest:find('…', 1, true)
    while first do
      if first > 1 then out:insert(pandoc.Str(rest:sub(1, first - 1))) end
      out:insert(pandoc.Span(pandoc.Str('…'), { class = 'tianlu-ell' }))
      rest = rest:sub(last + 1)
      first, last = rest:find('…', 1, true)
    end
    if #out == 0 then return nil end
    if rest ~= '' then out:insert(pandoc.Str(rest)) end
    return out
  end,
}

local alerts = {
  Div = function(div)
    local title = div.content[1]
    local word = alert_titles[script][div.classes[1]]
    if word and title and title.t == 'Div' and title.classes:includes('title') then
      title.content = { pandoc.Para({ pandoc.Str(word) }) }
      return div
    end
    return nil
  end,
}

-- As a pass of the file's list would also walk the metadata, and turn a title's quotation
-- marks twice, these walk the blocks alone.
local chinese = {
  Pandoc = function(doc)
    if not script then return nil end
    for _, pass in ipairs({ ruby, quotation, runs, blanks, latin, latin_link, notes, ellipsis, alerts }) do
      doc.blocks = doc.blocks:walk(pass)
    end
    return doc
  end,
}

local numeral_digits = { '一', '二', '三', '四', '五', '六', '七', '八', '九' }

-- N in Chinese numerals, from 1 to 9999: 十二 but 一百一十二, and one 零 for a gap, as in
-- 一千零二十 and 二百零五.
local function numeral(n)
  local out, gap = {}, false
  for _, place in ipairs({ { 1000, '千' }, { 100, '百' }, { 10, '十' }, { 1, '' } }) do
    local digit = n // place[1] % 10
    if digit == 0 then
      gap = #out > 0
    else
      if gap then table.insert(out, '零') end
      gap = false
      if not (place[1] == 10 and digit == 1 and #out == 0) then table.insert(out, numeral_digits[digit]) end
      table.insert(out, place[2])
    end
  end
  return table.concat(out)
end

-- An end title before each new juan and at the end.
local end_titles = {
  Pandoc = function(doc)
    local title = meta_text(doc.meta, 'title') or ''
    local closing = script == 'simplified' and '终' or '終'
    local out, juan = pandoc.Blocks({}), 0
    local function end_title()
      if juan > 0 and title ~= '' then
        out:insert(pandoc.Div({ pandoc.Para({ pandoc.Str(title .. '卷第' .. numeral(juan) .. closing) }) },
          { class = 'tianlu-end-title' }))
      end
    end
    for _, block in ipairs(doc.blocks) do
      local inner = unwrapped(block)
      if inner.t == 'Header' and inner.level == 1 and not inner.classes:includes('unnumbered') then
        end_title()
        juan = juan + 1
      end
      out:insert(block)
    end
    end_title()
    doc.blocks = out
    return doc
  end,
}

-- A seal's text, two characters a column, read from the right.
local function seal_html(text, class)
  local chars = {}
  for _, code in utf8.codes(text, true) do table.insert(chars, utf8.char(code)) end
  local columns, per_column = {}, #chars > 2 and 2 or 1
  for index = 1, #chars, per_column do
    local column = table.concat(chars, '', index, math.min(index + per_column - 1, #chars))
    table.insert(columns, '<span>' .. html_escape(column) .. '</span>')
  end
  return '<span class="tianlu-seal ' .. class .. ' tianlu-seal-' .. #chars .. '" role="img" aria-label="'
    .. html_escape(text) .. '">' .. table.concat(columns) .. '</span>'
end

local title_block = {
  Pandoc = function(doc)
    local title = meta_text(doc.meta, 'title')
    if not title then return nil end
    local seal, author = meta_text(doc.meta, 'seal'), meta_text(doc.meta, 'author')
    local head = pandoc.Blocks({ pandoc.RawBlock('html', '<p class="tianlu-title">' .. html_escape(title) .. '</p>') })
    if seal then head:insert(pandoc.RawBlock('html', seal_html(seal, 'tianlu-seal-title'))) end
    if author then
      head:insert(pandoc.RawBlock('html', '<p class="tianlu-author">' .. html_escape(author) .. '</p>'))
    end
    doc.blocks:insert(1, pandoc.Div(head, { class = 'tianlu-title-block' }))
    return doc
  end,
}

local stem_parity, branch_parity = {}, {}
for index, name in ipairs({ '甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸' }) do
  stem_parity[name] = index % 2
end
for index, name in ipairs({ '子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥' }) do
  branch_parity[name] = index % 2
end

-- The lunar date of a colophon, as its author gives it, or nil: the year's stem and branch,
-- then the month and day, since a year of the cycle turns at the lunar new year and not on
-- 1 January, and only a lunar calendar knows that.  A stem and a branch of different parity
-- are no year of the sixty, and a year needs a date after it.
local function lunar_date(text)
  local stem, branch = (text or ''):match('^(' .. utf8.charpattern .. ')(' .. utf8.charpattern .. ').')
  local parity = stem and stem_parity[stem]
  return parity and parity == branch_parity[branch] and text or nil
end

-- The colophon: a plaque with the document's name, a date in the cycle if the author gave one
-- that reads as such, and the end seal.
local colophon = {
  Pandoc = function(doc)
    local name = meta_text(doc.meta, 'colophon')
    if not name then return nil end
    local lines = { '<p>' .. html_escape(name) .. '</p>' }
    local date = lunar_date(meta_text(doc.meta, 'lunar'))
    if date then
      table.insert(lines, '<p>' .. (script == 'simplified' and '岁次' or '歲次') .. html_escape(date) .. '</p>')
    end
    local endseal = meta_text(doc.meta, 'endseal')
    local seal = endseal and ('<p class="tianlu-seal-line">' .. seal_html(endseal, 'tianlu-seal-end') .. '</p>') or ''
    doc.blocks:insert(pandoc.RawBlock('html', '<div class="tianlu-colophon" style="--tianlu-colophon-lines:'
      .. #lines + (endseal and 1 or 0) .. '">' .. table.concat(lines) .. seal .. '</div>'))
    return doc
  end,
}

return { language, document_keys, headnotes, plain_pictures, display_maths, code_plates, tables,
         diagram_captions, slots, chinese, end_titles, title_block, colophon }

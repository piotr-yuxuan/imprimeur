-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
--
-- What the skin Yaqut needs that a stylesheet cannot do, after the shared filter common, in
-- the order of the passes at the end of this file:
--
-- - document_keys takes the colophon, the Hijri date and the seal from Org's keywords, as a
--   Markdown document has them in its metadata;
-- - in_text sets apart what the author encloses in ﴿ ﴾, for the colour face, and opens each
--   block that holds notes with their glosses, or sets a heading's before it, which the sheet
--   sets in the margin, while pandoc keeps the notes for the foot: the sheet shows one or the
--   other, by the page's width and the option notes;
-- - unwan writes the title block, which the sheet sets in the headpiece;
-- - colophon writes what closes the document: its words, its date and its seal.
--
-- year_of parses what a document wrote, and the tests judge it by a table, through pandoc.

local stringify = pandoc.utils.stringify

local function html_escape(text)
  return (text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'))
end

local function meta_text(meta, key)
  return meta[key] and stringify(meta[key]) or nil
end

-- What the skin takes from Org's keywords, one each; any other stays out of the page.
local document_key_names = { COLOPHON = 'colophon', HIJRI = 'hijri', SEAL = 'seal' }

local document_keys = {
  Pandoc = function(doc)
    local kept = pandoc.Blocks({})
    for _, block in ipairs(doc.blocks) do
      -- An Org keyword that Emacs anchored to a line comes in a wrapper.
      local inner = block
      if block.t == 'Div' and block.attributes.wrapper and #block.content == 1 then
        inner = block.content[1]
      end
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

local open_quran, close_quran = '﴿', '﴾'

-- Each run of inlines from a word that holds ﴿ to the first word that holds ﴾, in one list,
-- becomes a span, whole words alone, so that a conjunction before ﴿ goes with it; a run that
-- never closes stays as it was.
local quran = {
  Inlines = function(inlines)
    local out, run = pandoc.Inlines({}), nil
    for _, inline in ipairs(inlines) do
      local word = inline.t == 'Str' and inline.text or ''
      if not run and word:find(open_quran, 1, true) then run = pandoc.Inlines({}) end
      if run then
        run:insert(inline)
        if word:find(close_quran, 1, true) then
          out:insert(pandoc.Span(run, { class = 'yaqut-quran' }))
          run = nil
        end
      else
        out:insert(inline)
      end
    end
    if run then out:extend(run) end
    return out
  end,
}

-- A block of text that holds notes opens with their glosses, in one span that the sheet floats
-- into the margin: Chromium places two floats anchored on one line out of their order, and one
-- float a block keeps them in it.  A heading's go in a block just before it instead, as its text
-- is the title that a minitoc reads.  A note has blocks, and a short one a single paragraph; a
-- gloss is a line of text, so any other block keeps its words alone.
--
-- The glosses of the notes in ELEMENT, a block or a term's inlines, or nil when it holds none.
-- A picture's words are not entered: pandoc writes them as its alt text, where a note is lost,
-- and a figure's caption, which holds the same note, glosses it once.
local function glosses_of(element)
  local glosses = pandoc.Inlines({})
  element:walk({
    traverse = 'topdown',
    Image = function(image) return image, false end,
    Note = function(note)
      local gloss = pandoc.Inlines({})
      for _, inner in ipairs(note.content) do
        local words = pandoc.Inlines({})
        if inner.t == 'Para' or inner.t == 'Plain' then
          words = inner.content
        else
          -- stringify takes nothing of a code block.
          words:insert(pandoc.Str(stringify(inner:walk({
            CodeBlock = function(code) return pandoc.Para({ pandoc.Str(code.text) }) end,
          }))))
        end
        if #gloss > 0 then gloss:insert(pandoc.Space()) end
        gloss:extend(words)
      end
      glosses:insert(pandoc.Span(gloss, { class = 'yaqut-gloss' }))
    end,
  })
  return #glosses > 0 and glosses or nil
end

local function glossed(block)
  local glosses = glosses_of(block)
  if not glosses then return nil end
  if block.t == 'Header' then
    return { pandoc.Div(pandoc.Plain(glosses), { class = 'yaqut-hashiya' }), block }
  end
  local first = block.t == 'LineBlock' and block.content[1] or block.content
  first:insert(1, pandoc.Span(glosses, { class = 'yaqut-hashiya' }))
  return block
end

-- A term's glosses open the term; its definitions are blocks, which gloss their own.
local hashiya = {
  Para = glossed, Plain = glossed, Header = glossed, LineBlock = glossed,
  DefinitionList = function(list)
    for _, item in ipairs(list.content) do
      local glosses = glosses_of(pandoc.Inlines(item[1]))
      if glosses then item[1]:insert(1, pandoc.Span(glosses, { class = 'yaqut-hashiya' })) end
    end
    return list
  end,
}

-- As a pass of the file's list would also walk the metadata, and set a title's marks apart,
-- these walk the blocks alone.
local in_text = {
  Pandoc = function(doc)
    doc.blocks = doc.blocks:walk(quran):walk(hashiya)
    return doc
  end,
}

local unwan = {
  Pandoc = function(doc)
    local title = meta_text(doc.meta, 'title')
    if not title then return nil end
    local head = pandoc.Blocks({
      pandoc.RawBlock('html', '<p class="yaqut-unwan-title">' .. html_escape(title) .. '</p>'),
    })
    local author = meta_text(doc.meta, 'author')
    if author then
      head:insert(pandoc.RawBlock('html', '<p class="yaqut-author">' .. html_escape(author) .. '</p>'))
    end
    doc.blocks:insert(1, pandoc.Div(head, { class = 'yaqut-unwan' }))
    return doc
  end,
}

-- The digits that a year may be written in, ASCII, Arabic-Indic and Persian, by their code points.
local digits = {}
for _, zero in ipairs({ 0x30, 0x660, 0x6F0 }) do
  for code = zero, zero + 9 do digits[code] = true end
end

local year_sign = utf8.char(0x601)

-- TEXT, a Hijri date as its author wrote it, as the text before its year, the year, the last
-- run of digits, and the text after it; or nil when it holds no digit.  A year sign that the
-- author wrote before the year is the one the page sets, so it leaves the text before.
local function year_of(text)
  local first, last, inside = nil, nil, false
  for position, code in utf8.codes(text, true) do
    local digit = digits[code]
    if digit and not inside then first = position end
    if digit then last = position end
    inside = digit
  end
  if not first then return nil end
  local stop = utf8.offset(text, 2, last) - 1
  local before = text:sub(1, first - 1)
  if before:sub(-#year_sign) == year_sign then before = before:sub(1, -#year_sign - 1) end
  return before, text:sub(first, stop), text:sub(stop + 1)
end

-- The colophon: its words, set as a triangle by two shapes that the sheet floats beside them,
-- then its date, then the seal.  The date is the author's Hijri one with the year sign before
-- its year, or else the document's date, which the page writes in the Hijri calendar.
local colophon = {
  Pandoc = function(doc)
    local words, seal = meta_text(doc.meta, 'colophon'), meta_text(doc.meta, 'seal')
    if not (words or seal) then return nil end
    local parts = {}
    if words then
      local shape = '<span class="yaqut-colophon-shape" aria-hidden="true"></span>'
      table.insert(parts, '<p class="yaqut-colophon-text">' .. shape .. shape .. html_escape(words) .. '</p>')
      local before, year, after = year_of(meta_text(doc.meta, 'hijri') or '')
      -- The document's date, when it opens with YYYY-MM-DD, as ISO 8601 and Org's timestamps
      -- write it; whether that date exists is the page's to judge.
      local date = (meta_text(doc.meta, 'date') or ''):match('^%s*[<%[]?(%d%d%d%d%-%d%d%-%d%d)')
      if year then
        table.insert(parts, '<p class="yaqut-colophon-date">' .. html_escape(before) .. '<span class="yaqut-year">'
          .. year_sign .. html_escape(year) .. '</span>' .. html_escape(after) .. '</p>')
      elseif date then
        table.insert(parts, '<p class="yaqut-colophon-date"><time class="yaqut-hijri" datetime="' .. date .. '">'
          .. date .. '</time></p>')
      end
    end
    if seal then
      table.insert(parts, '<p class="yaqut-seal-line"><span class="yaqut-seal" role="img" aria-label="'
        .. html_escape(seal) .. '">' .. html_escape(seal) .. '</span></p>')
    end
    doc.blocks:insert(pandoc.RawBlock('html', '<div class="yaqut-colophon">' .. table.concat(parts) .. '</div>'))
    return doc
  end,
}

return { document_keys, in_text, unwan, colophon }

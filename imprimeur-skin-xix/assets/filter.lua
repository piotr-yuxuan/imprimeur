-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
--
-- What the XIX skin needs that a stylesheet cannot do, after the shared filters
-- common and french:
--
-- - the first paragraph of a chapter takes a lettrine, by a class that the sheet
--   reads: never after a sign, nor before an inline that is not text.  The sheet
--   draws the plain capital that data-capitale gives, and the text keeps the
--   document's letter with its marks, for copying and searching.  A capital with a
--   tail, Q or J, takes a class that keeps it to two lines.  The rest of the first
--   word takes a span, for small capitals;
-- - the author and the date become a block, since the page hears only of the title.

local stringify = pandoc.utils.stringify

-- The capital that a lettrine shows for each one with a diacritic, by its base letter.
-- A table, since pandoc's Lua has no Unicode decomposition: Latin-1 and Latin Extended-A.
local unaccented = {}
for base, accented in pairs({
  A = 'ÀÁÂÃÄÅĀĂĄ', C = 'ÇĆĈĊČ', D = 'Ď', E = 'ÈÉÊËĒĔĖĘĚ', G = 'ĜĞĠĢ', H = 'Ĥ', I = 'ÌÍÎÏĨĪĬĮİ', J = 'Ĵ',
  K = 'Ķ', L = 'ĹĻĽ', N = 'ÑŃŅŇ', O = 'ÒÓÔÕÖŌŎŐ', R = 'ŔŖŘ', S = 'ŚŜŞŠ', T = 'ŢŤ', U = 'ÙÚÛÜŨŪŬŮŰŲ',
  W = 'Ŵ', Y = 'ÝŶŸ', Z = 'ŹŻŽ',
}) do
  for _, code in utf8.codes(accented) do unaccented[utf8.char(code)] = base end
end

-- Capitals beyond A to Z that a lettrine shows as they are: letters, not diacritics.
local plain_letters = { ['Æ'] = true, ['Ø'] = true, ['Œ'] = true }

local tailed = { Q = true, J = true }

-- The inlines that may hold the first word of a lettrine in their first text.  The
-- filter french has already wrapped Mme or XIXe in a Span.
local holders = { Emph = true, Strong = true, Span = true }

-- A run of combining marks, U+0300 to U+036F, in UTF-8: a decomposed É is an E and one.
local combining_marks = '^[\204\205\128-\191]*'

-- The block inside a wrapper, or the block itself.
local function unwrapped(block)
  if block and block.t == 'Div' and block.attributes.wrapper and #block.content == 1 then
    return block.content[1]
  end
  return block
end

-- The capital that a lettrine shows for TEXT, a Str, and its marked first letter, or nil.
local function capital_of(text)
  local letter = text and text.t == 'Str' and text.text:match(utf8.charpattern)
  if not letter then return nil end
  local upper = pandoc.text.upper(letter)
  local capital = unaccented[upper] or upper
  if capital:match('^%u$') or plain_letters[capital] then
    return capital, letter .. text.text:match(combining_marks, #letter + 1)
  end
  return nil
end

-- PARA with the lettrine of CAPITAL in place of MARKED, which opens TEXT.
local function set_lettrine(para, text, capital, marked)
  local word = pandoc.Inlines({
    pandoc.Span({ pandoc.Span({ pandoc.Str(marked) }, { class = 'xix-lettre' }) },
      pandoc.Attr('', { 'xix-capitale' }, { { 'data-capitale', capital } })) })
  local rest = text.text:sub(#marked + 1)
  if rest ~= '' then word:insert(pandoc.Str(rest)) end
  local first = para.content[1]
  if first == text then
    para.content[1] = pandoc.Span(word, { class = 'xix-premier-mot' })
  else
    first.content:remove(1)
    word:extend(first.content)
    first.content = word
  end
end

local function opens_chapter(block)
  local heading = unwrapped(block)
  return heading and heading.t == 'Header' and heading.level == 1
end

local lettrines = {
  Blocks = function(blocks)
    for index, block in ipairs(blocks) do
      local para = unwrapped(block)
      if opens_chapter(blocks[index - 1]) and para.t == 'Para' and para.content[1] then
        local first = para.content[1]
        local text = holders[first.t] and first.content[1] or first
        local capital, marked = capital_of(text)
        if capital then
          set_lettrine(para, text, capital, marked)
          local wrapper = block.t == 'Div' and block or pandoc.Div({ block })
          wrapper.classes:insert('xix-lettrine')
          if tailed[capital] then wrapper.classes:insert('xix-queue') end
          blocks[index] = wrapper
        end
      end
    end
    return blocks
  end,
}

-- The block of the title page: the author and the date, in the page after the title.
local title_page = {
  Pandoc = function(doc)
    local lines = pandoc.Blocks({})
    for _, part in ipairs({ 'author', 'date' }) do
      if doc.meta[part] then
        lines:insert(pandoc.Para({ pandoc.Span({ pandoc.Str(stringify(doc.meta[part])) }, { class = 'xix-' .. part }) }))
      end
    end
    if doc.meta.title or #lines > 0 then
      doc.blocks:insert(1, pandoc.Div(lines, { class = 'xix-titre' }))
    end
    return doc
  end,
}

return { lettrines, title_page }

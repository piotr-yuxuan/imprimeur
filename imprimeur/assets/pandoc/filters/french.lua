-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
--
-- A shared filter for a skin that lists it as `french'.  It acts only when the
-- document's language starts with fr, and touches no code and no bare address:
--
-- - U+202F before ; ! ? and inside « », U+00A0 before :, wherever the source wrote
--   them with a space or not;
-- - straight quotes, which +smart reads as quotes, become guillemets, and inner
--   ones “ ”;
-- - the whole word of a -t- goes in span.imprimeur-inversion, which base.css keeps
--   on one line, as another sign would reach the clipboard and find;
-- - XXe, 1er, Mme and Mlle take a superscript, and a century sits in
--   span.imprimeur-siecle for the sheet;
-- - the title of an alert is said in French.

local stringify = pandoc.utils.stringify

local narrow, plain = '\u{202F}', '\u{A0}'

local blank = { Space = true, SoftBreak = true }

local alerts = { warning = 'Avertissement', tip = 'Conseil', caution = 'Attention' }

local function raised(base, letters)
  return { pandoc.Str(base), pandoc.Superscript({ pandoc.Str(letters) }) }
end

local function whole(base, letters)
  return { pandoc.Str(base .. letters) }
end

-- Each word that takes a span: three captures, what the span makes of the first
-- two, its class, and what follows it.
local rules = {
  { pattern = '^(.+)(%-t%-%l+)(%p*)$', make = whole, class = 'imprimeur-inversion' },
  { pattern = '^([IVX]+)(er?)(%p*)$', make = raised, class = 'imprimeur-siecle' },
  { pattern = '^(%d+)(er?)(%p*)$', make = raised, class = 'imprimeur-superieur' },
  { pattern = '^(M)(me)(%p*)$', make = raised, class = 'imprimeur-superieur' },
  { pattern = '^(M)(lle)(%p*)$', make = raised, class = 'imprimeur-superieur' },
}

-- An address shown as it is stays as it is.
local function keep_address(link)
  if stringify(link.content) == link.target then return link, false end
  return nil
end

local function curly(quoted)
  local inlines = pandoc.Inlines({ pandoc.Str('“') })
  inlines:extend(quoted.content)
  inlines:insert(pandoc.Str('”'))
  return inlines
end

local quotes = {
  traverse = 'topdown',
  Quoted = function(quoted)
    if quoted.quotetype ~= 'DoubleQuote' then return nil end
    local inlines = pandoc.Inlines({ pandoc.Str('«') })
    inlines:extend(pandoc.Inlines(quoted.content):walk({ Quoted = curly }))
    inlines:insert(pandoc.Str('»'))
    return inlines, false
  end,
}

local words = {
  traverse = 'topdown',
  Link = keep_address,
  Str = function(str)
    for _, rule in ipairs(rules) do
      local base, letters, rest = str.text:match(rule.pattern)
      if base then
        local span = pandoc.Span(rule.make(base, letters), { class = rule.class })
        return rest == '' and { span } or { span, pandoc.Str(rest) }, false
      end
    end
    return nil
  end,
}

-- TEXT with the space that each of its signs takes, in place of one already there.
local function spaced(text)
  for _, space in ipairs({ narrow, plain }) do
    text = text:gsub('«' .. space, '«'):gsub(space .. '»', '»'):gsub(space .. '([;:!?])', '%1')
  end
  text = text:gsub('«', '«' .. narrow):gsub('»', narrow .. '»')
  return (text:gsub('^(.-)([;:!?]+)([^%w/]*)$', function(before, signs, after)
    return before .. (signs:sub(1, 1) == ':' and plain or narrow) .. signs .. after
  end))
end

local spacing = {
  traverse = 'topdown',
  Link = keep_address,
  Str = function(str)
    return pandoc.Str(spaced(str.text))
  end,
}

-- A blank that the source wrote next to a sign gives way to the sign's own.
local function opens(inline)
  return inline.t == 'Str' and (inline.text:sub(1, #narrow) == narrow or inline.text:sub(1, #plain) == plain)
end

local function closes(inline)
  return inline and inline.t == 'Str' and inline.text:sub(-#narrow) == narrow
end

local blanks = {
  traverse = 'topdown',
  Link = keep_address,
  Inlines = function(inlines)
    local out = pandoc.Inlines({})
    for _, inline in ipairs(inlines) do
      if out[#out] and blank[out[#out].t] and opens(inline) then out:remove() end
      if not (blank[inline.t] and closes(out[#out])) then out:insert(inline) end
    end
    return out
  end,
}

local titles = {
  Div = function(div)
    local heading = div.content[1]
    local said = alerts[div.classes[1]]
    if said and heading and heading.t == 'Div' and heading.classes:includes('title') then
      heading.content = { pandoc.Para({ pandoc.Str(said) }) }
      return div
    end
    return nil
  end,
}

return { {
  Pandoc = function(doc)
    if not stringify(doc.meta.lang or ''):match('^fr') then return nil end
    doc.blocks = doc.blocks:walk(quotes):walk(words):walk(spacing):walk(blanks):walk(titles)
    if pandoc.utils.type(doc.meta.title) == 'Inlines' then
      doc.meta.title = doc.meta.title:walk(quotes):walk(spacing):walk(blanks)
    end
    return doc
  end,
} }

-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
--
-- What the skin Briefing needs that a stylesheet cannot do, after the shared filters
-- common and french, in the order of the passes at the end of this file:
--
-- - language reads the document's language and status, for every word below;
-- - levels makes the shallowest heading a first-level one, whoever took the title;
-- - columns right-aligns a column of quantities, by Org's threshold of a half and the
--   parser numeric; minus gives a quantity a true minus; totals gives a row named Total a
--   class and the table a wrapper that scrolls;
-- - plain_code gives a plain block's lines a hanging indent, and a long line whole words;
-- - callouts turns Decision, Ask, Risk and Note blocks and GitHub's alerts into callouts,
--   whose leading strong word names the label; bottom_line wraps the section named as a
--   summary, up to the next heading of its level or callout;
-- - planning_lines hands a planning line to the heading above it; action_titles draws a
--   heading's keyword, priority, tags, planning line and owner in a row of chips before
--   it, and the heading keeps the document's letters, at no size, in no identifier;
-- - identifiers keeps repeated titles apart;
-- - masthead writes the subtitle, author, date, status, reading time and Skim link;
-- - in French, figures spaces groups of figures and percentages, signs keeps a sign with
--   the formula before it, and compounds keeps a title's compounds whole.
--
-- keyword_of, priority_of, tags_of, planning_text, planning_of, identifier_of, lead_of and
-- numeric parse what a document wrote, and are judged by tables in the tests.

local stringify = pandoc.utils.stringify

local statuses = { TODO = 'open', NEXT = 'next', STARTED = 'next', WAITING = 'waiting',
                   DONE = 'done', CANCELLED = 'cancelled' }

local callout_kinds = { decision = 'decision', ask = 'ask', risk = 'risk', note = 'note',
                        important = 'decision', warning = 'ask', caution = 'risk', tip = 'note' }

local planning_kinds = { DEADLINE = 'due', SCHEDULED = 'date', CLOSED = 'date' }

local summary_titles = { summary = true, ['executive summary'] = true, ['tl;dr'] = true, tldr = true,
                         ['bottom line'] = true, ['résumé'] = true, ['synthèse'] = true,
                         ['l\u{2019}essentiel'] = true }

local words = {
  en = {
    statuses = { TODO = 'Open', NEXT = 'Next', STARTED = 'Started', WAITING = 'Waiting',
                 DONE = 'Done', CANCELLED = 'Cancelled' },
    callouts = { decision = 'Decision', ask = 'Ask', risk = 'Risk', note = 'Note',
                 important = 'Important', warning = 'Warning', caution = 'Caution', tip = 'Tip' },
    planning = { DEADLINE = 'Due', SCHEDULED = 'Starts', CLOSED = 'Closed' },
    months = { 'January', 'February', 'March', 'April', 'May', 'June', 'July',
               'August', 'September', 'October', 'November', 'December' },
    short_months = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' },
    bottom_line = 'Bottom line',
    reading = ' min read',
    skim = 'Skim',
    full = 'Full brief',
  },
  fr = {
    statuses = { TODO = 'À faire', NEXT = 'Ensuite', STARTED = 'En cours', WAITING = 'En attente',
                 DONE = 'Fait', CANCELLED = 'Annulé' },
    callouts = { decision = 'Décision', ask = 'Demande', risk = 'Risque', note = 'Note',
                 important = 'Important', warning = 'Attention', caution = 'Prudence', tip = 'Conseil' },
    planning = { DEADLINE = 'Échéance', SCHEDULED = 'Début', CLOSED = 'Clos' },
    months = { 'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
               'août', 'septembre', 'octobre', 'novembre', 'décembre' },
    short_months = { 'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.',
                     'nov.', 'déc.' },
    first_day = '1er',
    bottom_line = 'L\u{2019}essentiel',
    reading = ' min de lecture',
    skim = 'Survol',
    full = 'Texte entier',
  },
}

local says = words.en
local standing
local fine, nobreak = '\u{202F}', '\u{A0}'
local numeric_fraction = 0.5
local currencies = { '£', '€', '¥', '%$' }
local reading_speed = 220
local plain_columns = 40
local inline_runs = { Str = true, Space = true, SoftBreak = true }
local keyword_classes = { todo = true, done = true }
local line_attributes = { 'data-pos', 'data-imprimeur-line' }
local planning_mark = 'briefing-planning'
local group_spaced, group_joined = '(%d) (%d%d%d)%f[%D]', '(%d)' .. nobreak .. '(%d%d%d)%f[%D]'
local group_fine = '%1' .. fine .. '%2'

-- The block inside a wrapper, or the block itself.
local function unwrapped(block)
  if block and block.t == 'Div' and block.attributes.wrapper and #block.content == 1 then
    return block.content[1]
  end
  return block
end

local function chip(kind, text, pair)
  return pandoc.Span({ pandoc.Str(text) },
    pandoc.Attr('', { 'briefing-chip' }, { { 'data-kind', kind }, pair }))
end

-- A chip for a heading's mark: the heading keeps the letters, and the sheet draws the word.
local function worded_chip(kind, word, pair)
  return pandoc.Span({}, pandoc.Attr('', { 'briefing-chip' }, { { 'data-kind', kind }, { 'data-word', word }, pair }))
end

-- These inlines of a heading stay its words, and the sheet hides them.
local function hide(content, from, to)
  for index = from, to do
    local inline = content[index]
    if inline.t == 'Span' then
      inline.classes:insert('briefing-letters')
    else
      content[index] = pandoc.Span({ inline }, { class = 'briefing-letters' })
    end
  end
end

local function drop_first(inlines)
  inlines:remove(1)
  if inlines[1] and inlines[1].t == 'Space' then inlines:remove(1) end
end

local function day_of(day)
  return tonumber(day) == 1 and says.first_day or tostring(tonumber(day))
end

local function escaped(text)
  return (text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

local function item(text, class)
  return pandoc.Span({ pandoc.Str(text) }, { class = class })
end

-- TEXT without the no-break space that french puts before a colon.
local function unspaced(text)
  return (text:gsub(nobreak, ''))
end

-- Parser: a heading's keyword, in the shape of each reader; Markdown's needs its colon.
local function keyword_of(inlines)
  local first = inlines[1]
  if first and first.t == 'Span' and keyword_classes[first.classes[1]] then
    return stringify(first)
  end
  local word = first and first.t == 'Str' and unspaced(first.text):match('^(%u+):$')
  return statuses[word] and inlines[2] and inlines[2].t == 'Space' and word or nil
end

-- Parser: a heading's priority cookie, a letter or a number.
local function priority_of(inlines)
  local first = inlines[1]
  local cookie = first and first.t == 'Str' and first.text:match('^%[#(%w)%]$')
  return cookie and (tonumber(cookie) or (cookie:upper():byte() - ('A'):byte() + 1))
end

-- Parser: the chips of a heading's trailing tags, Org's spans or Markdown's :a:b:, which it removes.
local function tags_of(inlines)
  local tags = {}
  local last = inlines[#inlines]
  if last and last.t == 'Str' and unspaced(last.text):match('^:[%w_@#%-:\128-\255]+:$') then
    for tag in unspaced(last.text):gmatch('[^:]+') do table.insert(tags, worded_chip('tag', tag)) end
    inlines:remove(#inlines)
  end
  while #inlines > 0 do
    local tail = inlines[#inlines]
    if tail.t == 'Span' and tail.classes:includes('tag') then
      table.insert(tags, 1, worded_chip('tag', stringify(tail)))
    elseif not stringify(tail):match('^[\u{A0} ]*$') then
      break
    end
    inlines:remove(#inlines)
  end
  return tags
end

-- Parser: the text of a paragraph of planning words and an owner, or nil.
local function planning_text(block)
  local para = unwrapped(block)
  local text = para and (para.t == 'Plain' or para.t == 'Para') and unspaced(stringify(para)) or ''
  local first = text:match('^(%u+):')
  return (planning_kinds[first] or first == 'OWNER') and text or nil
end

-- TEXT with only its ASCII letters and figures, in lower case: what a reader's identifier
-- and a heading's words have in common, whatever they make of signs and accents.
local function bare(text)
  return (text:lower():gsub('%W', ''))
end

-- Parser: the identifier of a heading whose marks go, TITLE being what is left of its words.
-- One that the document chose holds none of those words, and stays.
local function identifier_of(header, title)
  if not bare(stringify(header.content)):find(bare(header.identifier), 1, true) then return header.identifier end
  return (stringify(title):lower():gsub('[^%w%s_%-\128-\255]', ''):gsub('%s+', '-'))
end

-- Parser: the chips of a planning paragraph's text.
local function planning_of(text)
  local chips = pandoc.Inlines({})
  for word, month, day in text:gmatch('(%u+):%s*[<%[]?%d%d%d%d%-(%d%d)%-(%d%d)') do
    local name = says.short_months[tonumber(month)]
    if planning_kinds[word] and name then
      chips:insert(worded_chip(planning_kinds[word], says.planning[word] .. ' ' .. day_of(day) .. ' ' .. name))
    end
  end
  local owner = text:match('OWNER:%s*([^,]+)')
  if owner then chips:insert(worded_chip('owner', owner)) end
  return chips
end

-- Parser: a leading strong word of a callout's first paragraph, which it removes.
local function lead_of(content)
  local para = unwrapped(content[1])
  local strong = para and para.t == 'Para' and para.content[1]
  if not strong or strong.t ~= 'Strong' then return nil end
  local lead = stringify(strong):gsub(nobreak, ' '):gsub(fine, ' ')
  local word = lead:match('^([^%s:.]+)%s?[:.]$')
  if word then drop_first(para.content) end
  return word
end

-- Parser: whether a cell holds a quantity.  It widens Org's test to thousands, currencies,
-- 3.5k and the true minus, and refuses a version or a date.  A cell over 64 bytes is none,
-- as the patterns would take long on a hostile one.
local function numeric(text)
  if #text > 64 then return false end
  local plain = text:gsub('\u{2212}', '-'):gsub(',(%d%d%d)%f[%D]', '%1'):gsub('(%d)[kKmM]$', '%1')
  if says == words.fr then
    plain = plain:gsub(nobreak, ' '):gsub(fine, ' '):gsub(' (%d%d%d)%f[%D]', '%1')
      :gsub(',(%d+)$', '.%1'):gsub(' %%$', '%%')
  end
  for _, sign in ipairs(currencies) do
    plain = plain:gsub('^([<>]?[-+]?)' .. sign, '%1')
  end
  return plain:match('^[<>]?[-+^.0-9]*[0-9][-+^.0-9eEdDx()%%:]*$') ~= nil
    and plain:match('%d[.-]%d+[.-]%d') == nil
end

-- The rows of every body of a table.
local function rows_of(tbl)
  local rows = {}
  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body) do table.insert(rows, row) end
  end
  return rows
end

local language = {
  Meta = function(meta)
    says = stringify(meta.lang or ''):lower():match('^fr') and words.fr or words.en
    standing = meta.status and stringify(meta.status)
  end,
}

local levels = {
  Pandoc = function(doc)
    local top = 6
    doc.blocks:walk({ Header = function(header) top = math.min(top, header.level) end })
    if top == 1 then return nil end
    doc.blocks = doc.blocks:walk({
      Header = function(header)
        header.level = header.level - top + 1
        return header
      end,
    })
    return doc
  end,
}

local columns = {
  Table = function(tbl)
    local numbers, filled = {}, {}
    for column = 1, #tbl.colspecs do numbers[column], filled[column] = 0, 0 end
    for _, row in ipairs(rows_of(tbl)) do
      for column, cell in ipairs(row.cells) do
        local text = stringify(cell.contents)
        if text ~= '' then filled[column] = filled[column] + 1 end
        if numeric(text) then numbers[column] = numbers[column] + 1 end
      end
    end
    for column, spec in ipairs(tbl.colspecs) do
      if spec[1] == 'AlignDefault' and numbers[column] / filled[column] >= numeric_fraction then
        tbl.colspecs[column] = { 'AlignRight', spec[2] }
      end
    end
    return tbl
  end,
}

local minus = {
  Table = function(tbl)
    for _, row in ipairs(rows_of(tbl)) do
      for _, cell in ipairs(row.cells) do
        local plain = cell.contents[1]
        local first = plain and plain.content and plain.content[1]
        if first and first.t == 'Str' and first.text:sub(1, 1) == '-' and numeric(stringify(cell.contents)) then
          plain.content[1] = pandoc.Str('\u{2212}' .. first.text:sub(2))
        end
      end
    end
    return tbl
  end,
}

local totals = {
  Table = function(tbl)
    for _, row in ipairs(rows_of(tbl)) do
      local name = stringify(row.cells[1] and row.cells[1].contents or {}):lower()
      if name:match('^totals?%f[%A]') or name:match('^sum%f[%A]') or name:match('total$') then
        row.attr.classes:insert('briefing-total')
      end
    end
    return pandoc.Div({ tbl }, { class = 'briefing-table' })
  end,
}

-- The block goes raw, so the wrapper takes what says where it comes from.
local plain_code = {
  Div = function(div)
    local block = div.content[1]
    if not (div.classes:includes('imprimeur-code') and block and block.t == 'CodeBlock') then return nil end
    local lines = {}
    for line in (block.text:gsub('\n+$', '') .. '\n'):gmatch('(.-)\n') do
      local text = #line <= plain_columns and escaped(line) or line:gsub('%S+', function(word)
        return '<span class="briefing-word">' .. escaped(word) .. '</span>'
      end)
      table.insert(lines, '<span>' .. text .. '</span>')
    end
    for _, name in ipairs(line_attributes) do div.attributes[name] = block.attributes[name] end
    div.content = { pandoc.RawBlock('html',
      '<pre><code class="briefing-plain">' .. table.concat(lines, '\n') .. '</code></pre>') }
    return div
  end,
}

local callouts = {
  Div = function(div)
    if div.classes:includes('summary') then
      div.classes = { 'briefing-bottom-line' }
      div.content:insert(1, pandoc.Div({ pandoc.Plain({ pandoc.Str(says.bottom_line) }) },
        { class = 'briefing-label' }))
      return div
    end
    local kind = callout_kinds[div.classes[1]]
    if not kind then return nil end
    local label = says.callouts[div.classes[1]]
    local first = div.content[1]
    if first and first.t == 'Div' and first.classes:includes('title') then div.content:remove(1) end
    label = lead_of(div.content) or label
    div.classes = { 'briefing-callout' }
    div.attributes['data-kind'] = kind
    div.content:insert(1, pandoc.Div({ pandoc.Plain({ pandoc.Str(label) }) }, { class = 'briefing-label' }))
    return div
  end,
}

local bottom_line = {
  Pandoc = function(doc)
    local first
    for index, block in ipairs(doc.blocks) do
      if block.t == 'Header' and summary_titles[stringify(block.content):lower()] then
        first = index
        break
      end
    end
    if not first then return nil end
    local last = first
    for index = first + 1, #doc.blocks do
      local block = doc.blocks[index]
      if block.t == 'Header' and block.level <= doc.blocks[first].level
        or block.t == 'Div' and block.classes:includes('briefing-callout') then
        break
      end
      last = index
    end
    local out = pandoc.Blocks({ table.unpack(doc.blocks, 1, first - 1) })
    out:insert(pandoc.Div({ table.unpack(doc.blocks, first, last) }, { class = 'briefing-bottom-line' }))
    out:extend({ table.unpack(doc.blocks, last + 1) })
    doc.blocks = out
    return doc
  end,
}

local planning_lines = {
  Blocks = function(blocks)
    local out = pandoc.Blocks({})
    local planned
    for index, block in ipairs(blocks) do
      local text = block.t == 'Header' and planning_text(blocks[index + 1])
      if text then block.attributes[planning_mark] = text end
      if planned then
        local kept = block.t == 'Div' and block or pandoc.Div({ block })
        kept.classes:insert('briefing-letters')
        out:insert(kept)
      else
        out:insert(block)
      end
      planned = text
    end
    return out
  end,
}

local action_titles = {
  Header = function(header)
    local content = header.content
    local title = content:clone()
    local chips = pandoc.Inlines({})
    local keyword = keyword_of(title)
    if keyword then
      chips:insert(worded_chip('status', says.statuses[keyword] or (keyword:sub(1, 1) .. keyword:sub(2):lower()),
        { 'data-status', statuses[keyword] or 'other' }))
      drop_first(title)
    end
    local priority = priority_of(title)
    if priority then
      chips:insert(worded_chip('priority', 'P' .. priority, { 'data-priority', tostring(priority) }))
      drop_first(title)
    end
    local leading = #content - #title
    local tags = tags_of(title)
    local trailing = #content - leading - #title
    chips:extend(planning_of(header.attributes[planning_mark] or ''))
    header.attributes[planning_mark] = nil
    if header.attributes.owner then chips:insert(chip('owner', header.attributes.owner)) end
    chips:extend(tags)
    if #chips == 0 then return nil end
    if leading + trailing > 0 then header.identifier = identifier_of(header, title) end
    hide(content, 1, leading)
    hide(content, #content - trailing + 1, #content)
    header.content = content
    local row = pandoc.Inlines({})
    for _, one in ipairs(chips) do row:extend({ one, pandoc.Space() }) end
    row:remove(#row)
    return { pandoc.Div({ pandoc.Plain(row) }, { class = 'briefing-chips' }), header }
  end,
}

local identifiers = {
  Pandoc = function(doc)
    local used = {}
    doc.blocks = doc.blocks:walk({
      Header = function(header)
        local chosen, count = header.identifier, 0
        while used[header.identifier] do
          count = count + 1
          header.identifier = chosen .. '-' .. count
        end
        used[header.identifier] = true
        return header
      end,
    })
    return doc
  end,
}

local masthead = {
  RawBlock = function(block)
    local status = block.format == 'org' and block.text:match('^#%+STATUS:%s*(.-)%s*$')
    if status then
      standing = status
      return {}
    end
  end,

  Pandoc = function(doc)
    local meta = doc.meta
    local row = pandoc.Inlines({})
    if meta.author then row:insert(item(stringify(meta.author), 'briefing-author')) end
    if meta.date then
      local date = stringify(meta.date)
      local year, month, day = date:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)')
      local name = says.months[tonumber(month)]
      row:insert(item(name and (day_of(day) .. ' ' .. name .. ' ' .. year) or date, 'briefing-date'))
    end
    if standing then row:insert(chip('standing', standing)) end
    if #row == 0 and not meta.subtitle then return nil end
    local count = 0
    for _ in stringify(doc.blocks):gmatch('%S+') do count = count + 1 end
    row:insert(item(math.max(1, math.ceil(count / reading_speed)) .. says.reading, 'briefing-reading'))
    row:insert(pandoc.Link({ pandoc.Span({ pandoc.Str(says.skim) }, { class = 'briefing-skim-off' }),
                             pandoc.Span({ pandoc.Str(says.full) }, { class = 'briefing-skim-on' }) }, '#skim', '',
      pandoc.Attr('', { 'briefing-skim' }, { { 'role', 'button' }, { 'aria-pressed', 'false' } })))
    local parts = pandoc.Blocks({})
    if meta.subtitle then
      parts:insert(pandoc.Div({ pandoc.Plain(pandoc.Inlines(meta.subtitle)) }, { class = 'briefing-subtitle' }))
    end
    parts:insert(pandoc.Div({ pandoc.Plain(row) }, { class = 'briefing-meta' }))
    doc.blocks:insert(1, pandoc.Div(parts, { class = 'briefing-masthead' }))
    return doc
  end,
}

local figures = {
  Inlines = function(inlines)
    if says ~= words.fr then return nil end
    local runs = pandoc.Inlines({})
    for _, inline in ipairs(inlines) do
      local plain = inline_runs[inline.t] and stringify(inline)
      local last = runs[#runs]
      if plain and last and last.t == 'Str' then
        runs[#runs] = pandoc.Str(last.text .. plain)
      elseif plain then
        runs:insert(pandoc.Str(plain))
      else
        runs:insert(inline)
      end
    end
    for index, inline in ipairs(runs) do
      if inline.t == 'Str' then
        local text = inline.text:gsub(group_spaced, group_fine):gsub(group_spaced, group_fine)
          :gsub(group_joined, group_fine):gsub(group_joined, group_fine):gsub(' %%', fine .. '%%')
        runs[index] = pandoc.Str(text)
      end
    end
    return runs
  end,
}

-- A browser breaks around a math element.
local signs = {
  Inlines = function(inlines)
    if says ~= words.fr then return nil end
    local out = pandoc.Inlines({})
    for _, inline in ipairs(inlines) do
      local last = out[#out]
      local text = inline.t == 'Str' and last and last.t == 'Math' and inline.text
      local sign = text and (text:match('^' .. nobreak .. ':') or text:match('^' .. fine .. '[;!?%%]')
        or text:match('^' .. fine .. '»'))
      if sign then
        out[#out] = pandoc.Span({ last, pandoc.Str(sign) }, { class = 'briefing-nobreak' })
        out:insert(pandoc.Str(text:sub(#sign + 1)))
      else
        out:insert(inline)
      end
    end
    return out
  end,
}

local compounds = {
  Header = function(header)
    if says ~= words.fr then return nil end
    return header:walk({
      Str = function(str)
        if not str.text:match('%S%-%S') then return nil end
        local out = pandoc.Inlines({})
        for gap, word in str.text:gmatch('(%s*)(%S+)') do
          if gap ~= '' then out:insert(pandoc.Space()) end
          out:insert(word:match('%S%-%S') and pandoc.Span({ pandoc.Str(word) }, { class = 'briefing-compound' })
            or pandoc.Str(word))
        end
        return out
      end,
    })
  end,
}

return { language, levels, columns, minus, totals, plain_code, callouts, bottom_line,
         planning_lines, action_titles, identifiers, masthead, figures, signs, compounds }

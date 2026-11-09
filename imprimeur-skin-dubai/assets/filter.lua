-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
--
-- What the skin Dubai needs that a stylesheet cannot do, after the shared filter common, in
-- the order of the passes at the end of this file.  It began as a copy of Briefing's: a memo
-- filter that both share waits for a third skin to need it.
--
-- - language reads the document's language and status, for every word below: Arabic under
--   ar, English under any other;
-- - levels makes the shallowest heading a first-level one, whoever took the title;
-- - columns right-aligns a column of quantities, by Org's threshold of a half and the
--   parser numeric; minus gives a quantity a true minus; totals gives a row named Total or
--   الإجمالي a class and the table a wrapper that scrolls;
-- - plain_code gives a plain block's lines a hanging indent, and a long line whole words;
-- - callouts turns Decision, Ask, Risk and Note blocks and GitHub's alerts into callouts,
--   whose leading strong word names the label; bottom_line wraps the section named as a
--   summary, up to the next heading of its level or callout; kpis marks a strong phrase of
--   the bottom line that begins with a quantity as a key figure;
-- - planning_lines hands a planning line to the heading above it; action_titles draws a
--   heading's keyword, priority, tags, planning line and owner in a row of chips before
--   it, and the heading keeps the document's letters, at no size, in no identifier;
-- - identifiers keeps repeated titles apart;
-- - masthead writes the subtitle, author, date, status, reading time and Skim link, and an
--   empty time element for the Umm al-Qura date, which page.mjs fills, as a filter has no
--   calendar but the Gregorian.
--
-- keyword_of, priority_of, tags_of, planning_text, planning_of, identifier_of, lead_of,
-- western, numeric and date_of parse what a document wrote, and are judged by tables in the
-- tests.
-- The author's digits stay as typed: western reads them, and writes nothing to the page.

local stringify = pandoc.utils.stringify

local statuses = { TODO = 'open', NEXT = 'next', STARTED = 'next', WAITING = 'waiting',
                   DONE = 'done', CANCELLED = 'cancelled' }

local callout_kinds = { decision = 'decision', ask = 'ask', risk = 'risk', note = 'note',
                        important = 'decision', warning = 'ask', caution = 'risk', tip = 'note' }

local planning_kinds = { DEADLINE = 'due', SCHEDULED = 'date', CLOSED = 'date' }

local summary_titles = { summary = true, ['executive summary'] = true, ['tl;dr'] = true, tldr = true,
                         ['bottom line'] = true, ['الخلاصة'] = true, ['الملخص التنفيذي'] = true }

local total_words = { 'المجموع', 'مجموع', 'الإجمالي', 'إجمالي' }

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
    reading = '%d min read',
    skim = 'Skim',
    full = 'Full brief',
  },
  -- The months are CLDR's for ar-AE, whose abbreviations are the names themselves.
  ar = {
    statuses = { TODO = 'مفتوح', NEXT = 'التالي', STARTED = 'قيد التنفيذ', WAITING = 'بانتظار',
                 DONE = 'منجز', CANCELLED = 'ملغى' },
    callouts = { decision = 'قرار', ask = 'طلب', risk = 'مخاطرة', note = 'ملاحظة',
                 important = 'مهم', warning = 'تنبيه', caution = 'تحذير', tip = 'نصيحة' },
    planning = { DEADLINE = 'الاستحقاق', SCHEDULED = 'البدء', CLOSED = 'أُغلق' },
    months = { 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو',
               'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر' },
    bottom_line = 'الخلاصة',
    reading = 'مدة القراءة %d د',
    skim = 'نظرة سريعة',
    full = 'المذكرة كاملة',
  },
}
words.ar.short_months = words.ar.months

local says = words.en
local standing
local fine, nobreak = '\u{202F}', '\u{A0}'
local numeric_fraction = 0.5
local currencies = { '£', '€', '¥', '%$', 'AED', 'د%.إ', 'درهم' }
local reading_speed = 220
local plain_columns = 40
local keyword_classes = { todo = true, done = true }
local line_attributes = { 'data-pos', 'data-imprimeur-line' }
local planning_mark = 'dubai-planning'

-- What the parsers read of a figure in Arabic: the Arabic-Indic and Persian digits, the
-- Arabic decimal and thousands separators and percent sign as ASCII, a no-break space as a
-- space, and no bidi mark.  And back, the Arabic-Indic digit of each ASCII one.
local eastern = { ['\u{066B}'] = '.', ['\u{066C}'] = ',', ['\u{066A}'] = '%', [nobreak] = ' ', [fine] = ' ',
                  ['\u{200E}'] = '', ['\u{200F}'] = '', ['\u{061C}'] = '' }
local indic = {}
for digit = 0, 9 do
  eastern[utf8.char(0x0660 + digit)] = tostring(digit)
  eastern[utf8.char(0x06F0 + digit)] = tostring(digit)
  indic[tostring(digit)] = utf8.char(0x0660 + digit)
end

-- The block inside a wrapper, or the block itself.
local function unwrapped(block)
  if block and block.t == 'Div' and block.attributes.wrapper and #block.content == 1 then
    return block.content[1]
  end
  return block
end

local function chip(kind, text, pair)
  return pandoc.Span({ pandoc.Str(text) },
    pandoc.Attr('', { 'dubai-chip' }, { { 'data-kind', kind }, pair }))
end

-- A chip for a heading's mark: the heading keeps the letters, and the sheet draws the word.
local function worded_chip(kind, word, pair)
  return pandoc.Span({}, pandoc.Attr('', { 'dubai-chip' }, { { 'data-kind', kind }, { 'data-word', word }, pair }))
end

-- These inlines of a heading stay its words, and the sheet hides them.
local function hide(content, from, to)
  for index = from, to do
    local inline = content[index]
    if inline.t == 'Span' then
      inline.classes:insert('dubai-letters')
    else
      content[index] = pandoc.Span({ inline }, { class = 'dubai-letters' })
    end
  end
end

local function drop_first(inlines)
  inlines:remove(1)
  if inlines[1] and inlines[1].t == 'Space' then inlines:remove(1) end
end

local function escaped(text)
  return (text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

local function item(text, class)
  return pandoc.Span({ pandoc.Str(text) }, { class = class })
end

-- TEXT without the no-break spaces that an editor may put before a colon.
local function unspaced(text)
  return (text:gsub(nobreak, ''))
end

-- Parser: TEXT with the Arabic forms of its figures as ASCII, for the patterns below.
local function western(text)
  return (text:gsub(utf8.charpattern, eastern))
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
      chips:insert(worded_chip(planning_kinds[word], says.planning[word] .. ' ' .. tonumber(day) .. ' ' .. name))
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

-- Parser: whether a cell holds a quantity.  It widens Org's test to thousands, currencies
-- before or after the figure, the dirham among them, 3.5k, the true minus and the Arabic
-- forms of figures, and refuses a version or a date.  A cell over 64 bytes is none, as the
-- patterns would take long on a hostile one.
local function numeric(text)
  if #text > 64 then return false end
  local plain = western(text):gsub('\u{2212}', '-'):gsub(',(%d%d%d)%f[%D]', '%1'):gsub('(%d)[kKmM]$', '%1')
  for _, sign in ipairs(currencies) do
    plain = plain:gsub('^([<>]?[-+]?)' .. sign .. ' ?', '%1'):gsub(' ?' .. sign .. '$', '')
  end
  return plain:match('^[<>]?[-+^.0-9]*[0-9][-+^.0-9eEdDx()%%:]*$') ~= nil
    and plain:match('%d[.-]%d+[.-]%d') == nil
end

-- Parser: the words of a date for the masthead, in the digits it was typed in, and its day
-- as YYYY-MM-DD in ASCII; or the date as written, and nil, when it names no month.
local function date_of(text)
  local year, month, day = western(text):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)')
  local name = says.months[tonumber(month)]
  if not name then return text, nil end
  local shown = tonumber(day) .. ' ' .. name .. ' ' .. year
  if text:find('\xD9[\xA0-\xA9]') then shown = shown:gsub('%d', indic) end
  return shown, year .. '-' .. month .. '-' .. day
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
    says = stringify(meta.lang or ''):lower():match('^ar%f[%A]') and words.ar or words.en
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
      local total = name:match('^totals?%f[%A]') or name:match('^sum%f[%A]') or name:match('total$')
      for _, word in ipairs(total_words) do
        total = total or name == word or name:sub(1, #word + 1) == word .. ' '
      end
      if total then row.attr.classes:insert('dubai-total') end
    end
    return pandoc.Div({ tbl }, { class = 'dubai-table' })
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
        return '<span class="dubai-word">' .. escaped(word) .. '</span>'
      end)
      table.insert(lines, '<span>' .. text .. '</span>')
    end
    for _, name in ipairs(line_attributes) do div.attributes[name] = block.attributes[name] end
    div.content = { pandoc.RawBlock('html',
      '<pre><code class="dubai-plain">' .. table.concat(lines, '\n') .. '</code></pre>') }
    return div
  end,
}

local callouts = {
  Div = function(div)
    if div.classes:includes('summary') then
      div.classes = { 'dubai-bottom-line' }
      div.content:insert(1, pandoc.Div({ pandoc.Plain({ pandoc.Str(says.bottom_line) }) },
        { class = 'dubai-label' }))
      return div
    end
    local kind = callout_kinds[div.classes[1]]
    if not kind then return nil end
    local label = says.callouts[div.classes[1]]
    local first = div.content[1]
    if first and first.t == 'Div' and first.classes:includes('title') then div.content:remove(1) end
    label = lead_of(div.content) or label
    div.classes = { 'dubai-callout' }
    div.attributes['data-kind'] = kind
    div.content:insert(1, pandoc.Div({ pandoc.Plain({ pandoc.Str(label) }) }, { class = 'dubai-label' }))
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
        or block.t == 'Div' and block.classes:includes('dubai-callout') then
        break
      end
      last = index
    end
    local out = pandoc.Blocks({ table.unpack(doc.blocks, 1, first - 1) })
    out:insert(pandoc.Div({ table.unpack(doc.blocks, first, last) }, { class = 'dubai-bottom-line' }))
    out:extend({ table.unpack(doc.blocks, last + 1) })
    doc.blocks = out
    return doc
  end,
}

-- A key figure begins with a quantity, in one word or a currency and a figure, so that a
-- lead such as *سنة 2025:* is none.
local kpis = {
  Div = function(div)
    if not div.classes:includes('dubai-bottom-line') then return nil end
    return div:walk({
      Strong = function(strong)
        local text = stringify(strong)
        local one, two = text:match('^%S+'), text:match('^%S+%s+%S+')
        if not (one and numeric(one) or two and numeric(two)) then return nil end
        return pandoc.Span({ strong }, { class = 'dubai-kpi' })
      end,
    })
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
        kept.classes:insert('dubai-letters')
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
    return { pandoc.Div({ pandoc.Plain(row) }, { class = 'dubai-chips' }), header }
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
    if meta.author then row:insert(item(stringify(meta.author), 'dubai-author')) end
    if meta.date then
      local shown, day = date_of(stringify(meta.date))
      row:insert(item(shown, 'dubai-date'))
      if day then row:insert(pandoc.RawInline('html', '<time class="dubai-hijri" datetime="' .. day .. '"></time>')) end
    end
    if standing then row:insert(chip('standing', standing)) end
    if #row == 0 and not meta.subtitle then return nil end
    local count = 0
    for _ in stringify(doc.blocks):gmatch('%S+') do count = count + 1 end
    row:insert(item(says.reading:format(math.max(1, math.ceil(count / reading_speed))), 'dubai-reading'))
    row:insert(pandoc.Link({ pandoc.Span({ pandoc.Str(says.skim) }, { class = 'dubai-skim-off' }),
                             pandoc.Span({ pandoc.Str(says.full) }, { class = 'dubai-skim-on' }) }, '#skim', '',
      pandoc.Attr('', { 'dubai-skim' }, { { 'role', 'button' }, { 'aria-pressed', 'false' } })))
    local parts = pandoc.Blocks({})
    if meta.subtitle then
      parts:insert(pandoc.Div({ pandoc.Plain(pandoc.Inlines(meta.subtitle)) }, { class = 'dubai-subtitle' }))
    end
    parts:insert(pandoc.Div({ pandoc.Plain(row) }, { class = 'dubai-meta' }))
    doc.blocks:insert(1, pandoc.Div(parts, { class = 'dubai-masthead' }))
    return doc
  end,
}

return { language, levels, columns, minus, totals, plain_code, callouts, bottom_line, kpis,
         planning_lines, action_titles, identifiers, masthead }

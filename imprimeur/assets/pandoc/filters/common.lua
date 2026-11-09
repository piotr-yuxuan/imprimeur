-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
--
-- A shared filter, in any language, for a skin that lists it as `common':
--
-- - a lone first-level heading opening a document with no title becomes its
--   title, and any other lone one takes the class unnumbered;
-- - a lone picture or film with a description becomes a figure, and one with none
--   does not;
-- - "Table:", "表：" or "جدول:" before a table and "Plate:", "Figure:", "圖：" or
--   "شكل:" after a diagram become captions, for Markdown, which has none;
-- - a bare address may break after its signs, by <wbr>;
-- - a code block that names no language pandoc knows takes div.imprimeur-code, for
--   the width of a highlighted one.

local stringify = pandoc.utils.stringify

local films = { mp4 = true, webm = true, ogv = true, mov = true, m4v = true }

local table_labels = { 'Table:', '表：', 'جدول:' }
local plate_labels = { 'Plate:', 'Figure:', '圖：', 'شكل:' }

-- The block inside a wrapper, or the block itself.
local function unwrapped(block)
  if block and block.t == 'Div' and block.attributes.wrapper and #block.content == 1 then
    return block.content[1]
  end
  return block
end

-- The text after the label, one of LABELS, that opens the paragraph BLOCK, or nil.
local function labelled(block, labels)
  local para = unwrapped(block)
  local first = para and para.t == 'Para' and para.content[1]
  if not first or first.t ~= 'Str' then return nil end
  for _, label in ipairs(labels) do
    if first.text:sub(1, #label) == label then
      local text = pandoc.Inlines({ table.unpack(para.content, 2) })
      local rest = first.text:sub(#label + 1)
      if rest ~= '' then
        text:insert(1, pandoc.Str(rest))
      elseif text[1] and text[1].t == 'Space' then
        text:remove(1)
      end
      return text
    end
  end
  return nil
end

local title = {
  Pandoc = function(doc)
    local blocks = doc.blocks
    local headings = {}
    for index, block in ipairs(blocks) do
      if block.t == 'Header' and block.level == 1 then table.insert(headings, index) end
    end
    if #headings ~= 1 then return nil end
    local heading = blocks[headings[1]]
    if headings[1] == 1 and not doc.meta.title then
      doc.meta.title = heading.content
      blocks:remove(1)
    else
      heading.classes:insert('unnumbered')
    end
    doc.blocks = blocks
    return doc
  end,
}

-- A film alone in its paragraph, with a description: a picture for the next pass.
local films_alone = {
  Para = function(para)
    local link = #para.content == 1 and para.content[1]
    if link and link.t == 'Link' and films[(link.target:match('%.(%w+)$') or ''):lower()]
      and stringify(link.content) ~= link.target then
      return pandoc.Para({ pandoc.Image(link.content, link.target) })
    end
    return nil
  end,
}

local shapes = {
  Para = function(para)
    local picture = #para.content == 1 and para.content[1]
    if picture and picture.t == 'Image' and #picture.caption > 0 then
      return pandoc.Figure({ pandoc.Plain({ picture }) }, { long = { pandoc.Plain(picture.caption) } })
    end
    return nil
  end,

  Link = function(link)
    local text = stringify(link.content)
    if text ~= link.target then return nil end
    local pieces = pandoc.Inlines({})
    for word, signs in text:gmatch('([^/_%-?&=]*)([/_%-?&=]*)') do
      if word .. signs ~= '' then pieces:insert(pandoc.Str(word .. signs)) end
      if signs ~= '' then pieces:insert(pandoc.RawInline('html', '<wbr>')) end
    end
    link.content = pieces
    return link
  end,

  CodeBlock = function(block)
    if #block.classes == 0 then return pandoc.Div({ block }, { class = 'imprimeur-code' }) end
    return nil
  end,
}

local captions = {
  Blocks = function(blocks)
    local out = pandoc.Blocks({})
    for index, block in ipairs(blocks) do
      local following = unwrapped(blocks[index + 1])
      local diagram = unwrapped(out[#out])
      local of_table = following and following.t == 'Table' and labelled(block, table_labels)
      local of_plate = diagram and diagram.t == 'CodeBlock' and diagram.classes:includes('mermaid')
        and labelled(block, plate_labels)
      if of_table then
        following.caption.long = { pandoc.Plain(of_table) }
      elseif of_plate then
        out[#out] = pandoc.Div({ pandoc.Div({ pandoc.Plain(of_plate) }, { class = 'caption' }), out[#out] },
          { class = 'captioned-content' })
      else
        out:insert(block)
      end
    end
    return out
  end,
}

return { title, films_alone, shapes, captions }

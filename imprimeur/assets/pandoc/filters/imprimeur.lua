-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
--
-- The pandoc filter of imprimeur.  It reads its settings from the metadata
-- that Emacs sets with -M, which the document cannot override:
--
-- - imprimeur-languages: the languages pandoc highlights, comma-separated;
-- - imprimeur-remote-images: "allow" lets remote images load.
--
-- Then it rewrites the document for the page:
--
-- - a fence language that pandoc does not highlight moves to the attribute
--   data-language, because an unknown class costs pandoc about 0.3 s per
--   render; a few aliases, such as elisp, become the name pandoc knows; a
--   Mermaid block keeps its class;
-- - the glyph that starts a task-list item becomes a span carrying
--   data-checked, so that pandoc writes no input element;
-- - an Org link without description to a video file becomes a video;
-- - a remote image becomes a link naming its host, unless allowed;
-- - the inline wrappers that +sourcepos adds are unwrapped, and the words they
--   split are one Str again, so that a later filter reads whole words;
-- - an anchor that Emacs put in an Org text, #+IMPRIMEUR_LINE: N, which pandoc
--   reads as a raw block and would leave out, goes on the block after it, at the
--   top level alone, in the shape that +sourcepos gives Markdown: a block with
--   attributes takes data-imprimeur-line, and any other goes in a Div with
--   wrapper.  So a later filter has one rule in every format: unwrap a wrapper.
--
-- finish.lua, which runs after a skin's filters, writes the lines and the marker.

local stringify = pandoc.utils.stringify

local aliases = {
  elisp = 'commonlisp', ['emacs-lisp'] = 'commonlisp', lisp = 'commonlisp',
  sh = 'bash', shell = 'bash', console = 'bash', js = 'javascript',
  mjs = 'javascript', ts = 'typescript', py = 'python', rb = 'ruby',
  rs = 'rust', yml = 'yaml', md = 'markdown', tex = 'latex', clj = 'clojure',
  hs = 'haskell', kt = 'kotlin', ['c++'] = 'cpp',
}

local videos = { mp4 = true, webm = true, ogv = true, mov = true, m4v = true }

-- The blocks that have attributes of their own.
local carriers = { Header = true, CodeBlock = true, Table = true, Figure = true, Div = true }

local tasks = { ['☐'] = { glyph = '☐', checked = 'false' },
                ['☒'] = { glyph = '☑', checked = 'true' } }

function Pandoc(doc)
  local meta = doc.meta
  local allow_remote = stringify(meta['imprimeur-remote-images'] or '') == 'allow'
  local known = {}
  for name in stringify(meta['imprimeur-languages'] or ''):gmatch('[^,]+') do
    known[name] = true
  end

  local blocks = doc.blocks:walk({
    Span = function(span)
      if span.attributes.wrapper then return span.content end
    end,

    Inlines = function(inlines)
      local merged = pandoc.Inlines({})
      for _, inline in ipairs(inlines) do
        local last = merged[#merged]
        if inline.t == 'Str' and last and last.t == 'Str' then
          last.text = last.text .. inline.text
        else
          merged:insert(inline)
        end
      end
      return merged
    end,

    CodeBlock = function(block)
      if block.classes:includes('math') then
        local para = pandoc.Para({ pandoc.Math('DisplayMath', block.text) })
        local pos = block.attributes['data-pos']
        return pos and pandoc.Div({ para }, { wrapper = '1', ['data-pos'] = pos }) or para
      end
      local first = block.classes[1]
      if not first or first == 'mermaid' then return nil end
      local name = aliases[first:lower()] or first:lower()
      if known[name] then
        block.classes[1] = name
      else
        block.classes:remove(1)
        block.attributes['data-language'] = first
      end
      return block
    end,

    BulletList = function(list)
      for _, item in ipairs(list.content) do
        local first = item[1]
        local head = first and first.t == 'Plain' and first.content[1]
        local task = head and head.t == 'Str' and tasks[head.text]
        if task then
          local glyph = pandoc.Span({ pandoc.Str(task.glyph) },
            { class = 'task', ['data-checked'] = task.checked })
          -- With +sourcepos the box stands alone, and the item's text follows
          -- in a block wrapper: the box joins the text, on the same line.
          local rest = item[2]
          local text = #first.content == 1 and rest and rest.t == 'Div'
            and rest.attributes.wrapper and rest.content[1]
          if text and (text.t == 'Plain' or text.t == 'Para') then
            text.content:insert(1, pandoc.Space())
            text.content:insert(1, glyph)
            item:remove(1)
          else
            first.content[1] = glyph
          end
        end
      end
      return list
    end,

    Link = function(link)
      local extension = (link.target:match('%.(%w+)$') or ''):lower()
      local text = stringify(link.content)
      if videos[extension] and (text == link.target or text == 'file:' .. link.target) then
        return pandoc.Image({}, link.target)
      end
    end,

    Image = function(image)
      local host = image.src:match('^[Hh][Tt][Tt][Pp][Ss]?://([^/?#]+)')
        or image.src:match('^//([^/?#]+)')
      if host and not allow_remote then
        local alt = stringify(image.caption)
        return pandoc.Link({ pandoc.Str((alt ~= '' and alt or 'image') .. ' (' .. host .. ')') },
          image.src, '', { class = 'imprimeur-remote' })
      end
    end,
  })

  local shaped = pandoc.Blocks({})
  local line = nil
  for _, block in ipairs(blocks) do
    local anchor = block.t == 'RawBlock' and block.format == 'org'
      and block.text:match('^#%+IMPRIMEUR_LINE: (%d+)$')
    if anchor then
      line = anchor
    elseif not line then
      shaped:insert(block)
    elseif carriers[block.t] then
      block.attributes['data-imprimeur-line'] = line
      shaped:insert(block)
      line = nil
    else
      shaped:insert(pandoc.Div({ block }, { wrapper = '1', ['data-imprimeur-line'] = line }))
      line = nil
    end
  end
  -- The last anchor may name the notes, which pandoc writes after the last block.
  if line then shaped:insert(pandoc.Div({}, { wrapper = '1', ['data-imprimeur-line'] = line })) end
  return pandoc.Pandoc(shaped, meta)
end

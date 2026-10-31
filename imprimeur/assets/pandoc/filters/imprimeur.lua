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
-- - the inline wrappers that +sourcepos adds are unwrapped;
-- - the title and the language precede the document, after a marker line,
--   as one line of JSON that Emacs reads and removes.  They come first
--   because pandoc writes some blocks, such as the footnotes, after the
--   last one, and a document cannot write before the filter's first block.

local stringify = pandoc.utils.stringify

local aliases = {
  elisp = 'commonlisp', ['emacs-lisp'] = 'commonlisp', lisp = 'commonlisp',
  sh = 'bash', shell = 'bash', console = 'bash', js = 'javascript',
  mjs = 'javascript', ts = 'typescript', py = 'python', rb = 'ruby',
  rs = 'rust', yml = 'yaml', md = 'markdown', tex = 'latex', clj = 'clojure',
  hs = 'haskell', kt = 'kotlin', ['c++'] = 'cpp',
}

local videos = { mp4 = true, webm = true, ogv = true, mov = true, m4v = true }

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

    CodeBlock = function(block)
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
          first.content[1] = pandoc.Span({ pandoc.Str(task.glyph) },
            { class = 'task', ['data-checked'] = task.checked })
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

  blocks:insert(1, pandoc.RawBlock('html', '<!--imprimeur-meta-->\n' .. pandoc.json.encode({
    title = stringify(meta.title or ''),
    lang = stringify(meta.lang or ''),
  })))
  return pandoc.Pandoc(blocks, meta)
end

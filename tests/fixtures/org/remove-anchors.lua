-- SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
--
-- Removes the anchors at the document's top level, and no other, so that an
-- anchor that went inside a list, say, still differs from the original.

function Pandoc(doc)
  doc.blocks = doc.blocks:filter(function(block)
    return not (block.t == 'RawBlock' and block.format == 'org'
                and block.text:match('^#%+IMPRIMEUR_LINE: %d+$'))
  end)
  return doc
end

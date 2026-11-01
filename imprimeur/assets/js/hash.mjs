// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// The hash that names what the page has drawn already.

// FNV-1a of 32 bits over the UTF-8 bytes of TEXT, as 8 hexadecimal digits.
export function fnv1a(text) {
  let hash = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(text)) hash = Math.imul(hash ^ byte, 0x01000193);
  return (hash >>> 0).toString(16).padStart(8, '0');
}

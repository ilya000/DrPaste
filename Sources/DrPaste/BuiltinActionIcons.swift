//
//  BuiltinActionIcons.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under the MIT License. See LICENSE.
//  See LICENSE for terms.
//
//  SF Symbol icons for built-in action rows in Settings (#11).
//  Provides visual consistency across the actions list — every row has a leading
//  type icon: AI rows show provider icon, transformation rows show engine icon,
//  built-in rows use this table.
//
//  IDs follow convention v2 (#A74, 0.56.0): `builtin.<content_kind>.<verb_noun>`
//  where content_kind matches the source SemanticKind (text, rich, url, json,
//  table, markdown, code, image, files). `builtin.identity` is the sole anchor
//  exception. No legacy aliases — pre-distribution clean slate.
//

import Foundation

enum BuiltinActionIcons {
    static func iconName(for actionID: String) -> String {
        // All 22 Unicode "fancy text" actions share a single engine icon
        // — case-by-case mapping would just be 22 lines of "textformat".
        if actionID.hasPrefix("builtin.text.font_") { return "textformat" }
        switch actionID {
        // Universal anchor
        case "builtin.identity":                       return "doc.on.clipboard.fill"

        // text.* — plain-text transforms
        case "builtin.text.trim":                      return "scissors"
        case "builtin.text.uppercase":                 return "textformat"
        case "builtin.text.lowercase":                 return "textformat.alt"
        case "builtin.text.title_case":                return "textformat.size"
        case "builtin.text.sentence_case":             return "textformat.abc"
        case "builtin.text.camel_case":                return "textformat"
        case "builtin.text.snake_case":                return "textformat.alt"
        case "builtin.text.kebab_case":                return "minus.forwardslash.plus"
        case "builtin.text.sort_lines":                return "arrow.up.arrow.down"
        case "builtin.text.unique_lines":              return "line.3.horizontal.decrease.circle"
        case "builtin.text.base64_encode":             return "lock"
        case "builtin.text.base64_decode":             return "lock.open"
        case "builtin.text.slugify":                   return "tag"
        case "builtin.text.word_count":                return "number"
        case "builtin.text.generate_qr":               return "qrcode"
        case "builtin.text.layout_repair":             return "globe"
        case "builtin.text.cyrillic_to_latin":         return "character.book.closed"
        case "builtin.text.latin_to_cyrillic":         return "character.book.closed.fill"
        case "builtin.text.unit_conversion":           return "arrow.left.arrow.right"
        case "builtin.text.remove_line_breaks":        return "text.justify"
        case "builtin.text.wrap_quotes":               return "quote.opening"
        case "builtin.text.wrap_parens":               return "parentheses"
        case "builtin.text.extract_emails":            return "envelope"
        case "builtin.text.extract_links":             return "link"
        case "builtin.text.leetspeak":                 return "number.square"
        case "builtin.text.uwu_speak":                 return "face.smiling"
        case "builtin.text.zalgo":                     return "tornado"
        case "builtin.text.type_slowly":               return "keyboard"

        // rich.* — rich-text transforms
        case "builtin.rich.strip_formatting":          return "text.alignleft"
        case "builtin.rich.to_md":                     return "doc.richtext"
        case "builtin.rich.to_html":                   return "chevron.left.forwardslash.chevron.right"
        case "builtin.rich.to_wiki":                   return "book.closed"
        case "builtin.rich.to_unicode_styled":         return "character.cursor.ibeam"

        // url.* — URL transforms
        case "builtin.url.strip_tracking":             return "shield"
        case "builtin.url.extract_domain":             return "globe.americas"
        case "builtin.url.to_md_link":                 return "link"
        case "builtin.url.to_html_link":               return "link.circle"
        case "builtin.url.encode":                     return "percent"
        case "builtin.url.decode":                     return "percent"
        case "builtin.url.preview_card":               return "doc.richtext.fill"

        // json.* — JSON transforms
        case "builtin.json.pretty":                    return "curlybraces"
        case "builtin.json.minify":                    return "curlybraces.square"
        case "builtin.json.extract_keys":              return "list.bullet"
        case "builtin.json.flatten":                   return "rectangle.compress.vertical"
        case "builtin.json.remove_nulls":              return "minus.circle"
        case "builtin.json.validate":                  return "checkmark.seal"

        // table.* — CSV / table transforms
        case "builtin.table.to_json":                  return "tablecells.badge.ellipsis"
        case "builtin.table.to_md":                    return "tablecells"
        case "builtin.table.to_wiki":                  return "tablecells.badge.ellipsis"
        case "builtin.table.to_rich":                  return "tablecells"
        case "builtin.table.to_html":                  return "chevron.left.forwardslash.chevron.right"

        // md.* — Markdown transforms
        case "builtin.md.to_rich":                     return "text.badge.plus"
        case "builtin.md.extract_headings":            return "list.number"
        case "builtin.md.extract_links":               return "link"

        // code.* — code transforms
        case "builtin.code.wrap_block":                return "chevron.left.forwardslash.chevron.right"
        case "builtin.code.tabs_to_spaces":            return "space"
        case "builtin.code.spaces_to_tabs":            return "arrow.right.to.line"
        case "builtin.code.pretty_local":              return "curlybraces.square"

        // html.* — HTML transforms
        case "builtin.html.strip_tags":                return "chevron.left.forwardslash.chevron.right"
        case "builtin.html.escape":                    return "lock.shield"
        case "builtin.html.unescape":                  return "lock.open"

        // image.* — image transforms
        case "builtin.image.ocr":                      return "text.viewfinder"
        case "builtin.image.decode_qr":                return "qrcode.viewfinder"
        case "builtin.md.to_wiki":                      return "w.square.fill"
        case "builtin.image.info":                      return "info.circle"
        case "builtin.image.strip_metadata":           return "eye.slash"
        case "builtin.image.resize":                   return "arrow.up.left.and.arrow.down.right"
        case "builtin.image.compress_jpeg":            return "rectangle.compress.vertical"
        case "builtin.image.to_grayscale":             return "circle.lefthalf.filled"
        case "builtin.image.rotate_right":             return "rotate.right"
        case "builtin.image.rotate_left":              return "rotate.left"
        case "builtin.image.invert_colors":            return "circle.righthalf.filled"
        case "builtin.image.to_ascii_art":             return "textformat.123"

        // files.* — files transforms
        case "builtin.files.copy_paths":               return "doc.on.doc"
        case "builtin.files.copy_filenames":           return "doc.text"
        case "builtin.files.to_md_links":              return "link"
        case "builtin.files.reveal_in_finder":         return "folder"
        case "builtin.files.copy_shell_safe_paths":    return "terminal"
        case "builtin.files.to_rich_icons":            return "doc.richtext"
        case "builtin.files.extract_image":            return "doc.text.image"
        case "builtin.text.to_files":                  return "folder.badge.plus"

        default:                                       return "gearshape"
        }
    }
}

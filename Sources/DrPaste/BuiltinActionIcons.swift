//
//  BuiltinActionIcons.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  SF Symbol icons for built-in action rows in Settings (#11).
//  Provides visual consistency across the actions list — every row has a leading
//  type icon: AI rows show provider icon, transformation rows show engine icon,
//  built-in rows use this table.
//

import Foundation

enum BuiltinActionIcons {
    static func iconName(for actionID: String) -> String {
        // All 22 Unicode "fancy text" actions share a single engine icon
        // — case-by-case mapping would just be 22 lines of "textformat".
        if actionID.hasPrefix("builtin.font_") { return "textformat" }
        switch actionID {
        case "builtin.identity":             return "doc.on.clipboard.fill"
        case "builtin.paste_as_text":        return "text.alignleft"
        case "builtin.clean_formatting":     return "paintbrush.pointed"
        case "builtin.trim":                 return "scissors"
        case "builtin.uppercase":            return "textformat"
        case "builtin.lowercase":            return "textformat.alt"
        case "builtin.layout_repair":        return "globe"
        case "builtin.rich_to_md":           return "doc.richtext"
        case "builtin.rich_to_html":         return "chevron.left.forwardslash.chevron.right"
        case "builtin.rich_to_wiki":         return "book.closed"
        case "builtin.rich_to_unicode_style": return "character.cursor.ibeam"
        case "builtin.cyrillic_translit":    return "character.book.closed"
        case "builtin.json_pretty":          return "curlybraces"
        case "builtin.json_minify":          return "curlybraces.square"
        case "builtin.json_extract_keys":    return "list.bullet"
        case "builtin.json_flatten":         return "rectangle.compress.vertical"
        case "builtin.json_remove_nulls":    return "minus.circle"
        case "builtin.url_strip_tracking":   return "shield"
        case "builtin.url_just_domain":      return "globe.americas"
        case "builtin.url_md_link":          return "link"
        case "builtin.url_html_link":        return "link.circle"
        case "builtin.url_encode":           return "percent"
        case "builtin.url_decode":           return "percent"
        case "builtin.table_to_json":        return "tablecells.badge.ellipsis"
        case "builtin.table_to_md":          return "tablecells"
        case "builtin.md_to_plain":          return "text.alignleft"
        case "builtin.md_extract_headings":  return "list.number"
        case "builtin.md_extract_links":     return "link"
        case "builtin.code_wrap":            return "chevron.left.forwardslash.chevron.right"
        case "builtin.tabs_to_spaces":       return "space"
        case "builtin.spaces_to_tabs":       return "arrow.right.to.line"
        case "builtin.title_case":           return "textformat.size"
        case "builtin.sentence_case":        return "textformat.abc"
        case "builtin.camel_case":           return "textformat"
        case "builtin.snake_case":           return "textformat.alt"
        case "builtin.kebab_case":           return "minus.forwardslash.plus"
        case "builtin.sort_lines":           return "arrow.up.arrow.down"
        case "builtin.unique_lines":         return "line.3.horizontal.decrease.circle"
        case "builtin.base64_encode":        return "lock"
        case "builtin.base64_decode":        return "lock.open"
        case "builtin.slugify":              return "tag"
        case "builtin.word_count":           return "number"
        case "builtin.generate_qr":          return "qrcode"
        case "builtin.image_ocr":            return "text.viewfinder"
        case "builtin.image_decode_qr":      return "qrcode.viewfinder"
        case "builtin.image_strip_metadata": return "eye.slash"
        case "builtin.image_resize_1920":    return "arrow.up.left.and.down.right.magnifyingglass"
        case "builtin.image_compress_jpeg":  return "rectangle.compress.vertical"
        case "builtin.image_grayscale":      return "circle.lefthalf.filled"
        case "builtin.image_rotate":         return "rotate.right"
        case "builtin.image_rotate_left":    return "rotate.left"
        case "builtin.image_invert":         return "circle.righthalf.filled"
        case "builtin.image_ascii_art":      return "textformat.123"
        case "builtin.files_paths":          return "doc.on.doc"
        case "builtin.files_names":          return "doc.text"
        case "builtin.files_md_links":       return "link"
        case "builtin.files_reveal":         return "folder"
        case "builtin.type_slowly":          return "keyboard"
        default:                              return "gearshape"
        }
    }
}

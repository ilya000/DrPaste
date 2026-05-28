//
//  AIPromptTemplates.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Library of useful AI prompt templates (#7).
//  Used by ActionEditor "Insert template…" menu — user picks one, prompt
//  field is filled, can be tweaked further.
//

import Foundation

struct AIPromptTemplate {
    let title: String
    let prompt: String
}

enum AIPromptTemplates {
    static let all: [AIPromptTemplate] = [
        // Translation
        AIPromptTemplate(
            title: "Translate to Spanish (auto-detect)",
            prompt: "Translate the input to Spanish. If the user provides text in Spanish, translate to English instead. Reply with the translation only, no preamble."
        ),
        AIPromptTemplate(
            title: "Translate to English",
            prompt: "Translate the input to English. Preserve the meaning and tone. Reply with the translation only."
        ),
        AIPromptTemplate(
            title: "Translate to French",
            prompt: "Translate the input to French. Preserve the meaning and tone. Reply with the translation only."
        ),
        AIPromptTemplate(
            title: "Translate to German",
            prompt: "Translate the input to German. Preserve the meaning and tone. Reply with the translation only."
        ),

        // Writing
        AIPromptTemplate(
            title: "Summarize",
            prompt: "Summarize the user's input in 1–3 sentences. Reply with the summary only, no preamble."
        ),
        AIPromptTemplate(
            title: "Fix grammar and spelling",
            prompt: "Fix grammar, spelling, and punctuation. Preserve the original language and voice. Reply with the corrected text only, no preamble or commentary."
        ),
        AIPromptTemplate(
            title: "Improve writing",
            prompt: "Improve the writing of the input: better word choice, clearer phrasing, tighter sentences. Keep the same meaning and language. Reply with the improved text only."
        ),
        AIPromptTemplate(
            title: "Rewrite in formal tone",
            prompt: "Rewrite the input in a more formal, professional tone. Preserve language and meaning. Reply with the rewritten text only."
        ),
        AIPromptTemplate(
            title: "Rewrite in casual tone",
            prompt: "Rewrite the input in a casual, friendly tone — as if writing to a friend. Preserve language and meaning. Reply with the rewritten text only."
        ),
        AIPromptTemplate(
            title: "Make shorter (concise)",
            prompt: "Rewrite the input more concisely. Aim for half the length while preserving all important information. Reply with the shorter version only."
        ),
        AIPromptTemplate(
            title: "Make longer (expand)",
            prompt: "Expand the input with more detail, examples, and elaboration while preserving the original meaning and language. Reply with the expanded version only."
        ),
        AIPromptTemplate(
            title: "Convert to bullet points",
            prompt: "Convert the input into a clear bulleted list. Each bullet should be one idea. Preserve language. Reply with the list only."
        ),

        // Code
        AIPromptTemplate(
            title: "Explain code",
            prompt: "Explain what the code does in plain language. Cover purpose, logic, and notable design choices. Reply with the explanation only."
        ),
        AIPromptTemplate(
            title: "Find bugs in code",
            prompt: "Review the code for potential bugs, edge cases, or logical errors. List issues found with brief explanations. If no issues, say so."
        ),
        AIPromptTemplate(
            title: "Add inline comments to code",
            prompt: "Add helpful inline comments to the code explaining non-obvious parts. Preserve the original code structure. Reply with the commented code only."
        ),
        AIPromptTemplate(
            title: "Convert code to TypeScript",
            prompt: "Convert the input code to TypeScript. Preserve logic and add types. Reply with the TypeScript code only."
        ),
        AIPromptTemplate(
            title: "Convert code to Swift",
            prompt: "Convert the input code to Swift. Preserve logic and use idiomatic Swift. Reply with the Swift code only."
        ),

        // Data
        AIPromptTemplate(
            title: "Explain JSON structure",
            prompt: "Explain the structure of this JSON: what it represents, key fields, and nested objects. Reply with the explanation only."
        ),
        AIPromptTemplate(
            title: "Fix broken JSON",
            prompt: "Fix syntax errors in this JSON (missing commas, trailing commas, smart quotes, unescaped characters). Reply with valid JSON only, no preamble."
        ),
        AIPromptTemplate(
            title: "JSON → readable summary",
            prompt: "Read this JSON and summarize its content in plain English. Reply with the summary only."
        ),

        // Misc
        AIPromptTemplate(
            title: "Polish prose",
            prompt: "Polish the input for clarity, flow, and elegance. Keep the same meaning and language. Reply with the polished text only."
        ),
        AIPromptTemplate(
            title: "Convert URL to readable link",
            prompt: "Convert the input URL into a clean Markdown link [Title](URL) using the most likely page title based on the URL path. Reply with the Markdown link only."
        ),
        AIPromptTemplate(
            title: "Extract key facts",
            prompt: "Extract the key facts, numbers, and entities from the input. Format as a short bulleted list. Reply with the list only."
        )
    ]
}

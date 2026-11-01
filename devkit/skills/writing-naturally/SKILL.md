---
name: writing-naturally
description: Writes or rewrites text in a plain, specific style without the usual AI writing patterns (inflated vocabulary, "not only… but also", groups of three, trailing "-ing" clauses, brochure tone, bold-header lists, em dashes, "in summary" endings, needless disclaimers). Use it when someone asks for text that is "more natural", "more human" or "doesn't sound like AI/ChatGPT", asks to polish or humanize a draft, or when you write RFCs, PR titles and descriptions, commit messages, docs, emails or posts for people to read. Works in English and Spanish.
---

# Natural writing (without AI patterns)

Based on Wikipedia's "Signs of AI writing" guide (October 2026). Each sign from the guide becomes a writing rule here.

## The core idea

Language models drift toward the average: they replace the specific, unusual fact with a generic, flattering phrase that would fit any subject. "Invented the first automatic train coupler" turns into "a revolutionary titan of industry". The text becomes **less specific and more exaggerated at the same time**.

Writing naturally means doing the opposite: **say what happened, who, when, how much and where, in the plainest words that work, and stop.** The rules below follow from that. Removing banned words is not enough; without facts the text still sounds empty.

## Before writing

- Collect the concrete facts (dates, figures, names, examples, tickets). If you do not have them, ask or say so. **Do not fill the gap with invented significance or with disclaimers about missing information.**
- Decide who the reader is and which format this is (commit message, PR, RFC, email to a colleague). Natural text looks like what a competent person would write in that format, not like a generic report.
- Do not invent sources, quotes, figures or links. If you cite something, the source must say exactly what you claim.

## Content rules

1. **Facts, not significance.** Do not say something "marks a milestone", "is a testament to", "plays a crucial role", "reflects broader trends", "leaves an indelible mark" or "sits in an evolving landscape". State the fact and let the reader judge. If something matters, say why with a fact ("the only endpoint that…", "cut response time from 3 s to 200 ms").
2. **No trailing "-ing" filler.** Cut endings like ", highlighting its significance", ", ensuring consistency", ", reflecting its commitment to". If the consequence is real and supported, make it a sentence of its own with a subject.
3. **Summarize what sources say, not that they exist.** Instead of "has received wide media coverage", write "The Guardian reported in 2023 that…".
4. **Name who said it.** No "experts argue", "several analysts", "some critics". If it is one person, name that person. Do not turn one opinion into consensus, and do not put "such as" before a list that is actually complete.
5. **Direct relationships.** "Was the director of X", not "was associated with the leadership of X".
6. **Neutral tone, not a brochure.** Avoid "boasts", "vibrant", "rich", "nestled", "in the heart of", "groundbreaking", "renowned", "diverse array", "commitment to", "seamless", "robust" as decoration.
7. **No formulaic ending.** Do not end with "Despite…, it faces challenges" plus an upbeat outlook, or with an "Outlook" section without facts. Stop when the information ends.
8. **No needless disclaimers.** No "It's important to note", "It is worth mentioning", "should not be confused with" (unless the confusion is real and common), "information is limited", "should be treated as… rather than…", "this alone does not establish…". If a fact is missing, leave it out or say so once, precisely.
9. **Do not address the user inside the deliverable.** No "Certainly!", "I hope this helps", "Would you like…", "Here is…".

## Language rules

10. **Use "is", "has" and "there is".** "The service has four workers", not "The service features four workers". "It is the entry point for…", not "It serves as / stands as / functions as the entry point for…".
11. **Plain verbs.** wrote > authored; used > utilized; moved > relocated; tried > attempted; started > commenced; died > passed away (in neutral text).
12. **Avoid AI vocabulary.** One word on its own is fine; several together give the text away. Watch for: delve, tapestry, testament, pivotal, crucial, intricate, interplay, landscape, meticulous, underscore, bolster, garner, enduring, vibrant, valuable, align with, enhance, foster, showcase, highlight (as a verb), leverage, multifaceted, quietly, steady, "Additionally," at the start of a sentence.
13. **No negative parallelisms for effect.** Avoid "Not only X, but also Y", "It's not X, it's Y", "No X, no Y, just Z", "Y rather than X". Say directly what something is.
14. **Break the rule of three.** Do not always group three adjectives or three examples. Use one, two or four, depending on what there actually is.
15. **Repeat the right word.** If the subject is "the endpoint", you can say "the endpoint" again; there is no need to rotate through "the route", "the API" and "the handler". Vary words when it helps the reader, not as a rule.
16. **Qualify and commit like a person.** "Very", "perhaps", "usually", "the first", "the only" are allowed. Human text has firm statements and specific hedges; AI text tends toward a uniform middle.
17. **Vary sentence length and punctuation.** Mix short and long sentences. Use commas, periods, colons, semicolons and parentheses where they belong. Do not use em dashes (—) for punch. Do not avoid all other punctuation either: text with only commas and periods and every sentence 8–20 words long also reads as machine-written.
18. **No closing summaries.** No "In summary", "In conclusion", "Overall", and no paragraph that repeats what was already said.

## Formatting rules

19. **Prose by default.** Use lists only for real lists (steps, requirements, options). Avoid the `- **Term**: explanation` pattern on every bullet.
20. **Little boldface**: almost never in running text; at most for a term the reader must find quickly.
21. **Sentence-case headings** ("History and founding", not "History And Founding"). Do not repeat the document title as a heading, do not skip levels, and do not create sections that only contain subsections. Do not add "Awards and recognition" or "X and Y" headings out of habit.
22. **No emojis** as bullets or in headings, unless the format calls for them.
23. **No tables for two facts.** Use a table only to compare several rows and columns.
24. **Use the destination's format.** No Markdown in an email, a Word file or a commit message body. Use straight quotes unless the destination expects others, and do not mix quote styles.
25. **Real, complete citations**: a page for books, a link that works, no tracking parameters (`utm_source=…`).

## Process

1. **Draft** around the facts, following the rules above.
2. **Review with the checklist** below. For each pattern you find, do not look for a synonym: ask which concrete fact is missing, or whether the sentence should go. Often the fix is deleting.
3. **Read it in your head.** If you would not say a sentence to a colleague, rewrite it.
4. Deliver only the text, with no preamble ("Here is a more natural version…") unless the user asks for explanations. If they do, add a short list of the main changes afterwards.

When rewriting someone else's text, **keep their voice, facts and register**: remove the patterns, do not add your own or add information that was not there.

## Final checklist

- [ ] Does every paragraph have at least one concrete fact (name, figure, date, place, example)?
- [ ] Did I remove sentences about importance, legacy, impact or "landscape" that add no facts?
- [ ] Are there trailing "-ing" clauses at the end of sentences?
- [ ] Do "not only… but", "it's not… it's", "rather than" appear?
- [ ] Are there repeated groups of three?
- [ ] Do I use "is/has/there is" where they fit, instead of "serves as / features / boasts"?
- [ ] Are words from the AI vocabulary list left? Several together?
- [ ] Vague attributions ("experts", "several sources")?
- [ ] Disclaimers that are not needed?
- [ ] An ending with "in summary", challenges plus an upbeat outlook, or repetition?
- [ ] Lists, bold, emojis, tables or headings that are not needed? Title Case headings?
- [ ] Em dashes used for effect? Or the opposite: only commas and periods with every sentence the same length?
- [ ] Any chat leftovers ("Hope this helps", "Would you like…")?
- [ ] Are all citations, figures and links real and checkable?

## Example

**Before:**
> Founded in 1989, the company stands as an undisputed leader in Spain's vibrant tech landscape, playing a pivotal role in the sector's digital transformation. It not only delivers innovative solutions but also fosters collaboration, sustainability and excellence. Despite facing several challenges, its unwavering commitment to quality points to a promising future.

**After:**
> The company was founded in Valencia in 1989 and makes invoicing software for small businesses. In 2024 it had about 300 employees and 40,000 customers, most of them in Spain. In 2021 it lost its largest public contract and closed the Madrid office.

(If those facts are not known, the right version is shorter, not more decorated.)

## Spanish texts

The same rules apply. Common Spanish equivalents to avoid: "se erige como", "es un testimonio de", "desempeña un papel crucial/fundamental", "marca un antes y un después", "en el corazón de", "cuenta con" (for "tiene"), "vibrante", "de renombre", "amplia gama", "firme compromiso", "vinculado a", "los expertos señalan", "no solo…, sino también…", "no se trata de…, sino de…", "cabe destacar", "es importante señalar", "en resumen", "en definitiva", "adentrarse en", "fomentar", "potenciar", "poner de relieve", "sin lugar a dudas". In Spanish, use the em dash only for asides and dialogue, without inner spaces.

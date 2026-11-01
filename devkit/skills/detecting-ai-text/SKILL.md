---
name: detecting-ai-text
description: Analyzes a text and estimates whether it was written, fully or in part, by an AI such as ChatGPT, Claude, Gemini or Grok, quoting the specific patterns it finds. Use it when someone asks whether a text, RFC, PR description, ticket, email, comment or document "was written by AI", "sounds like ChatGPT" or "reads as AI", or asks to review a text for signs of machine writing. Works on English and Spanish texts.
---

# Detect AI-written text

Based on Wikipedia's "Signs of AI writing" guide (WikiProject AI Cleanup, October 2026 version), extended with Spanish equivalents.

## Before you start

- **No single sign proves anything.** Models are trained on human text, and press releases, blogs and marketing share many of these traits. What counts is how many signs appear and how dense they are.
- **Neither detection tools nor people are reliable.** Studies put most people close to chance; only frequent LLM users do much better. Back every conclusion with literal quotes from the text.
- **The signs are symptoms, not the problem.** The real problem is usually invented content, sources that do not say what the text claims, or empty analysis. Point it out when you see it.
- **A false positive does harm.** When in doubt, say "inconclusive".
- The catalog is built for **informational text** (articles, RFCs, reports, biographies, company descriptions, formal emails). It carries less weight for fiction, poetry or casual chat.

## Procedure

1. **Context.** Ask only if it is missing and would change the verdict: what kind of text is it, when was it written, and are there other texts by the same author to compare? Text written before **30 November 2022** (ChatGPT launch) can be treated as human unless there is evidence otherwise.
2. **Look for the strong signs first** (section A). They weigh more than anything else in the catalog, but they are not proof on their own. A sign from A plus signs from other sections can support "Very likely AI"; a sign from A alone, or one that fits the type of text, gives "Inconclusive" at most.
3. **Go through the catalog** (sections B to F) and note each finding with a literal quote.
4. **Weigh the findings.** Strong > moderate > weak. Several different categories at once count for much more than many repetitions of one.
5. **Check the signs of human writing** (section G) and the **indicators that do not work** (section H), so you do not overrate anything.
6. **If the text has citations or links and you can browse**, check a sample. Broken links, invalid DOIs or ISBNs, and sources that do not say what the text claims are among the most solid signs.
7. **Write the report** using the format at the end.

## A. Strong signs

These come from Wikipedia articles, where nobody writes this way on purpose. Before counting one, check that it fits the type of text: an email or a PR comment can say "Let me know if…" and a README can show a ```` ```markdown ```` block without any AI involved. Ignore anything that is quoted, given as an example or part of a template the author was asked to fill in.

- Leftovers from the chatbot conversation inside an article, RFC or report: "Certainly!", "Of course!", "I hope this helps", "Would you like…", "Here is a Wikipedia-style article", "check this before publishing". "Let me know if…" only counts outside emails, messages and comments.
- Refusals or model notices: "As an AI language model…", "As of my last knowledge update…".
- Placeholders left in a finished text: `[Entertainer's Name]`, `(Add your URL here)`, dates like `2025-xx-xx`. Not when the text is a template, a draft or follows a PR or issue template.
- Internal artifacts: `contentReference[oaicite:1]`, stray `[1, 2, 3]`, `<mark>` tags (Gemini), ↩ characters in footnotes. Also the whole text wrapped in a ```` ``` ```` block that starts with "wikitext" or "markdown", but not code blocks used to show examples.
- Notes "for the reviewer" or "for the user" inside the text itself.

## B. Content

| Sign | What to look for | Weight |
|---|---|---|
| Inflated significance and legacy | "stands/serves as", "is a testament to", "pivotal/crucial role", "reflects broader trends", "evolving landscape", "indelible mark", "deeply rooted", "setting the stage". Even on trivial subjects (an etymology, population data, an obscure species). | Strong when dense |
| Emphasis on notability and media coverage | "independent coverage", "featured/profiled in", "trade publications", "national media outlets", "maintains an active social media presence". Talks about the sources instead of summarizing what they say. | Strong |
| Superficial analysis in a trailing "-ing" clause | ", highlighting its importance", "ensuring…", "fostering…", "contributing to…", "reflecting…", "valuable insights", "resonate with". | Strong |
| Promotional or travel-brochure tone | "boasts", "vibrant", "rich", "nestled", "in the heart of", "groundbreaking", "renowned", "diverse array", "commitment to". | Moderate |
| Vague connections | "associated with", "connected to", "in connection with" instead of "was the director of". | Moderate |
| Vague attribution and overgeneralization | "Experts argue", "Observers have noted", "Industry reports", "several sources" (when there is one). Lists presented as non-exhaustive ("such as…") for no reason. | Moderate |
| Formulaic conclusion on challenges and outlook | "Despite its…, X faces several challenges…" followed by an upbeat ending; sections called "Challenges and Legacy" or "Future Outlook". | Strong because of the fixed formula |
| "Awards and recognition" section | "X and Y" headings, especially "Awards and recognition". | Moderate |
| Disclaimers about sources | 2023–24: "it's important to note". 2024–25: "not widely documented", "while specific details are limited", "maintains a low profile". Since mid-2026: "should be treated as… rather than…", "does not by itself establish…", "should not be confused with…". | Strong |

## C. Language and grammar

- **AI vocabulary.** The strongest sign when many of these words appear together; one or two can be chance.
  - 2023 to mid-2024: additionally (sentence start), boasts, bolstered, crucial, delve, emphasizing, enduring, garner, intricate, interplay, landscape, meticulous, pivotal, tapestry, testament, underscore, valuable, vibrant.
  - Mid-2024 to 2025: align with, enhance, fostering, highlighting, showcasing, underscore, vibrant.
  - 2025 to mid-2026: emphasizing, enhance, highlighting, showcasing.
  - Since mid-2026: challenge, clearer, dependable, echoed, foster, leverage, matters, multifaceted, practical, prioritize, quietly, steady, universally; short sentences of 8–20 words.
  - Grok: causal, empirical, correlate, underscore.
- **Avoiding "is" and "has"**: "serves as", "stands as", "represents", "functions as", "features", "offers". Also "began his career as" or "ventured into" instead of "was".
- **Negative parallelisms**: "Not only X, but also Y", "It's not X, it's Y", "No X, no Y, just Z", "Y rather than X", "X, not Y".
- **Rule of three**: constant groups of three adjectives or phrases ("innovative, sustainable and accessible"). More suspicious where nobody would bother, such as a commit message or a short email.
- **A first sentence that defines a generic title** as if it were an entity ("The List of X is a compilation…").
- **Forced lexical variety** (older models): never repeats a noun and rotates four synonyms for the same thing. Weak, because many writers are taught to avoid repetition.

## D. Style and formatting

- Headings in Title Case.
- Mechanical boldface, "key takeaways" style.
- Lists with a bold inline header and a colon: `- **Term**: explanation`.
- Broken heading hierarchy: repeating the document title, skipping levels, sections that only contain subsections.
- Emojis before headings or bullets (🚀 ✨ 📚 🤝).
- Small, unnecessary tables, or Markdown tables where they do not render.
- Markdown where the destination does not use it (`**`, `#`, `---`, `[text](url)`).
- Curly quotes “ ” and apostrophe ’ (ChatGPT, DeepSeek), sometimes mixed with straight ones. Weak: Word, macOS and iOS insert them automatically. Claude and Gemini rarely use them.
- Em dashes (—), especially with spaces around them and used for punch. A historical sign (until about September 2026) and weak on its own; Claude still uses them more than most writers. The opposite also applies: since late 2026 some models use no dashes, parentheses or colons at all, so text with only commas and periods and uniform sentence length is suspicious too.
- Paragraphs or sections that end by summarizing what was just said: "In summary", "In conclusion", "Overall" (more common in older models).

## E. Citations and references

- Several broken links that are not in the Internet Archive either (strong).
- ISBNs with an invalid checksum, DOIs that do not resolve or point to unrelated papers.
- General books cited without a page or URL, or with pages that do not contain the claim.
- References defined but never used, broken reuse, the same citation after every sentence.
- Tracking parameters in URLs: `utm_source=chatgpt.com`, `utm_source=openai`, `utm_source=copilot.com`, `referrer=grok.com`. They show the tool was used to find sources, not that it wrote the text (moderate).
- Volumes or issues that do not contain the cited article (strong once checked).
- Dates that do not fit, such as an access date long before the text was written or an author who had died before the cited publication date. Weak: people read sources before they start writing, and works get published posthumously or reprinted. Only count it after checking the source's publication history, and only when it fails.

## F. Comments, messages and metadata

- Customer-service tone: "I have carefully reviewed…", "I apologize for any inconvenience this may have caused", "If there are specific issues, please point them out".
- Long comments split into sections with headings.
- Citing rules or policies that do not exist, or misquoting them.
- Playing down AI use, or asking reviewers to judge the content rather than its origin.
- Change summaries that assure compliance ("improved clarity, neutrality and flow"), list what was kept ("while preserving the original meaning"), stress "verified sources", or itemize technical parameters.
- Letter formulas: "I hope this message finds you well", "I am writing to…".
- Template profiles: "About Me", "My Interests", "Let's Connect!" with emojis.
- A sudden change of style compared to other texts by the same author (flawless grammar out of nowhere). If the author writes the same way as before 2022, that points to a human.

## G. Signs of human writing

- Text written before 30 November 2022.
- The author can explain their choices and mistakes (for example, where a wrong link came from).
- Simple constructions: "there is", "it has", "is", "wrote" (not "authored"), "used" (not "utilized"), "died" (not "passed away").
- Definite statements: "the only", "the first", "one of the best".
- Qualifiers and intensifiers: "very", "perhaps", "tends to".
- Wordy phrases: "in order to", "the fact that", "as a result of".
- Very specific, rare details (exact dates, figures, concrete anecdotes, internal names and tickets).

## H. Indicators that do not work (never use them as evidence)

- Perfect grammar.
- Mixing formal and casual registers, or a tone that is both "clinical" and "emotional".
- "Bland" or "robotic" prose in general.
- Formal, academic or "fancy" prose in general (only the specific words above count).
- Transition words like "Additionally" on their own.
- Missing sources.
- Odd formatting errors, or perfect formatting.

## Spanish texts

The catalog comes from English text. For Spanish, look for these equivalents (my adaptation, not measured in the guide): "se erige como", "es un testimonio de", "desempeña un papel crucial/fundamental", "marca un antes y un después", "deja una huella imborrable", "en un panorama en constante evolución", "cuenta con" (for "tiene"), "vibrante", "enclavado en", "en el corazón de", "de renombre", "amplia gama", "firme compromiso", "vinculado a", "los expertos señalan", "no solo…, sino también…", "no se trata de…, sino de…", "cabe destacar", "es importante señalar", "en resumen", "en definitiva", "adentrarse en", "un rico tapiz", "fomentar", "potenciar", "poner de relieve", "sin lugar a dudas". Forced lexical variety carries less weight in Spanish, where schools teach writers to avoid repetition.

## Report format

```
## Verdict
<Very likely AI | Likely AI | Inconclusive | Likely human>, confidence <low/medium/high>
<1–2 sentences with the main reason>

## Signs found
| # | Sign | Literal quote | Weight |
|---|---|---|---|
| 1 | … | "…" | Strong/Moderate/Weak |

## Signs of human writing
- …  (or "Nothing notable")

## Limits of this analysis
- Type of text, language, length, missing date or other texts by the author, unverified sources, etc.

## Underlying problems (if any)
- Unsupported claims, doubtful sources, empty analysis, whoever wrote it.
```

For long texts, analyze section by section: parts may be AI-written and others not. If the user wants the text rewritten, suggest the `devkit:writing-naturally` skill, and remind them that hiding the signs does not fix the underlying problems.

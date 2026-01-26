# Dialogue Website Design

One-page marketing site for Dialogue, the voice transcription app for Mac.

## Overview

**Style:** Modern indie Mac app aesthetic (Flighty, Carrot Weather references). Clean,
tech-forward, playful copy with Apple-inspired puns. Not retrofuturistic — fits
naturally in the Apple ecosystem.

**Tech stack:** Static HTML/CSS/JS or lightweight framework (Astro, plain Vite).
No React complexity needed.

**CTAs:**
- Primary: Mac App Store download
- Secondary: iOS waitlist email capture

---

## Page Structure

```
NAV
HERO
WORKFLOW MANIFESTO (voice-first positioning)
PERSONA DEMOS (animated transcription)
FEATURES (4 sections)
iOS WAITLIST
FOOTER
```

---

## Navigation

```
Dialogue [logo]                          Download for Mac [button]
```

Simple fixed header. Logo left, CTA right.

---

## Hero Section

**Headline:**
> Talk to yourself. Productively.

**Subhead:**
> Dialogue turns your voice into transcripts, summaries, and action items —
> without touching the cloud.

**CTA:** Mac App Store badge/button

**Notes:**
- "Transcriptional." banked as a fun word for use elsewhere (feature section, badge)
- Tone: cheeky but legit

---

## Workflow Manifesto Section

Short, punchy block that frames the voice-first workflow shift. Positioned between
hero and demos to establish the "why" before showing the "how."

**Headline:**
> The keyboard is a bottleneck.

**Copy:**
> You speak 4x faster than you type. Your ideas shouldn't wait for your fingers
> to catch up. Dialogue lets you capture first and organize later — voice to
> transcript in real time, right on your Mac.

**Visual treatment:**
- Centered text, larger than body copy
- Slight contrast from surrounding sections (subtle background shift or extra whitespace)
- Optional: animated stat counter "150 wpm vs 40 wpm" or similar

**Tone:** Confident, not preachy. States the obvious truth everyone feels.

---

## Persona Demo Section

Animated transcription demos cycling through different use cases. Each shows:
- Persona label
- Tagline
- macOS-styled window with typed animation

**Animation specs:**
- Text types word-by-word at ~150 WPM
- Cursor blink at insertion point
- Optional subtle waveform animation
- Timing: ~4 sec typing, ~2 sec pause, fade to next
- macOS window chrome (traffic lights, title bar)
- Dark mode default
- SF Pro or system font

### Personas

| Persona | Tagline | Transcript |
|---------|---------|------------|
| **Student** | *[TBD - "present" angle, no typing]* | "In 1930, the Republican-controlled House of Representatives, in an effort to alleviate the effects of the... anyone? anyone?... Great Depression, passed the..." |
| **Developer** | *Dictate now. Commit later.* | "TODO: refactor this before anyone sees it. And by anyone I mean future me." |
| **Writer** | *Capture the muse before it ghosts you.* | "It was a dark and stormy night. No wait. Delete that. It was an ordinary Tuesday, except..." |
| **Accessibility** | *Type less. Say more.* | "Text to Mom: Yes I ate breakfast. Yes it was real food. Mostly." |
| **Meeting** | *[TBD - "remember" angle, softer tone]* | "Action item: circle back on the synergies. And figure out what that actually means." |
| **Brainstorm** | *Your best ideas don't wait for a keyboard.* | "The whole thing should feel inevitable — like, of course it works this way." |

**Note:** Student and Meeting taglines need refinement. Transcripts are finalized.

---

## Feature Sections

Four features, Apple-style presentation: big headline, short supporting copy.

### Feature 1: Live Transcription (The Killer Feature)

**Headline:**
> Your words. On screen. Instantly.

**Copy:**
> No upload. No waiting. No cloud. Transcription happens on your Mac, in real
> time, as you speak.

---

### Feature 2: Quick Capture

**Headline:**
> Floating. Unobtrusive. Always ready.

**Copy:**
> A tiny panel that stays on top while you work. Hit record, speak, close. Done.

---

### Feature 3: Search

**Headline:**
> Find that thing you said three weeks ago.

**Copy:**
> Full-text search across every recording.

---

### Feature 4: Privacy

**Headline:**
> What happens on your Mac stays on your Mac.

**Copy:**
> No accounts. No subscriptions. No asterisks.

---

## iOS Waitlist Section

```
                    Coming to iPhone.

    ┌─────────────────────────────┐  ┌────────────────┐
    │  your@email.com             │  │  Notify me     │
    └─────────────────────────────┘  └────────────────┘

          We'll email you when it's ready. No spam, promise.
```

**Implementation:** Simple email capture form. Needs backend or service
(Buttondown, ConvertKit, etc.)

---

## Footer

Placeholder links for now:
- Download for Mac
- Privacy Policy
- Contact
- [Optional: Social links]
- [Optional: Location/personality line]

---

## Visual Design Notes

**References:**
- Flighty (flighty.com) — clean, confident, monospace accents
- Carrot Weather — personality-driven copy
- Apple product pages — punny headlines, three-word punches

**Typography:**
- Primary: System/SF Pro for native feel
- Accent: Monospace for technical emphasis (like Flighty)

**Color:**
- Dark mode default (developer aesthetic)
- Clean, minimal palette

**Motion:**
- Typed animation for demo (word-by-word, cursor blink)
- Optional waveform visualization
- Smooth transitions between personas

---

## Implementation Notes

### Typed Animation

```javascript
// Pseudocode for typing effect
const demos = [
  { persona: "Student", tagline: "...", text: "In 1930..." },
  { persona: "Developer", tagline: "Dictate now...", text: "TODO:..." },
  // ...
];

function typeText(text, element, speed = 60) {
  // Type word-by-word at ~150 WPM
  // Add cursor element that blinks
  // On complete, pause, then fade to next
}
```

### Email Capture

Options:
- Buttondown (simple, privacy-focused)
- ConvertKit
- Custom backend endpoint

---

## Open Items

- [ ] Finalize Student tagline
- [ ] Finalize Meeting tagline
- [ ] Choose email capture service
- [ ] Determine hosting (Vercel, Netlify, etc.)
- [ ] App Store assets/links
- [ ] Footer content decisions
- [ ] Actual domain for site

---

## Banked Ideas

- **"Transcriptional."** — portmanteau for use in feature section or badge
- **Live Web Speech API demo** — future enhancement, actual mic-based demo

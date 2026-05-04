# Scroll Converter

A minimal JavaScript snippet that converts vertical scroll (mouse wheel) input into horizontal scroll on the page.

## What It Does

When a user scrolls vertically with their mouse wheel, this script intercepts the event and translates it into horizontal scrolling on the document. If the user is already scrolling horizontally (e.g., via a trackpad gesture), the script stays out of the way.

That's it. It's a single-purpose utility for pages with horizontal layouts.

## How I Use It

For elements that have `overflow-y: hidden` and `overflow-x: scroll`, typically this would imply an element that intends to arrange its children in a horizontal row that will overflow past its determined size.

For users that have a traditional mouse where the wheel is solely vertically traversing, scrolling through this element would be challenging if the scrollbar does not present itself visibly.

This code snippet is meant to convert that traditional wheel scrolling into scrolling that would apply to the element that overflows horizontally.

## How It Works

1. Listens for `wheel` events on the document's scrolling element.
2. If the scroll is primarily horizontal (`|deltaX| > |deltaY|`), it does nothing — native behavior takes over.
3. Otherwise, it prevents the default vertical scroll and applies `deltaY` to `scrollLeft`.

The script uses `document.scrollingElement` to target the correct viewport scroll container regardless of browser or doctype mode.

## Setup

Drop `main.js` into your page:

```html
<script src="main.js"></script>
```

No dependencies. No build step.

## Notes

- The listener is registered with `{ passive: false }` so that `preventDefault()` is allowed. This is necessary but means the browser cannot optimize scroll performance for this listener — expect minor scroll jank on low-end devices.
- This only captures `wheel` events. Touch/swipe input on mobile is unaffected.

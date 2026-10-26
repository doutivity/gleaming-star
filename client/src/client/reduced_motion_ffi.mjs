// Why this file exists: the user's `prefers-reduced-motion` setting can only
// be read through `window.matchMedia`, and neither Lustre nor plinth binds it.
// It is the only hand-written JavaScript in the client.

const query = () => globalThis.matchMedia?.("(prefers-reduced-motion: reduce)");

/** True when the user asked for less motion. False where there is no browser. */
export function prefers_reduced_motion() {
  return query()?.matches ?? false;
}

/** Calls `callback(matches)` whenever the setting changes. */
export function on_reduced_motion_change(callback) {
  query()?.addEventListener("change", (event) => callback(event.matches));
}

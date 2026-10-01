# Changelog

All notable changes to AIMeter will be documented in this file.

This project follows semantic versioning while it is practical for a small macOS utility.

## [0.6.0] - 2026-09-30

### Added

- General setting to hide the menu bar progress bar when Cursor Auto and API percentages are shown instead.
- Optional Claude 5-hour and weekly percentage display in the menu bar.
- OpenAI ChatGPT Plus Codex usage tracking for weekly limits, credits, and reset timing.

### Changed

- Menu bar display always keeps at least one of the progress bar or Cursor Auto/API percentages visible; percentages-only mode shows `--/--` when Cursor has not synced yet.
- Cursor usage now reads from the [spending dashboard](https://cursor.com/dashboard/spending) instead of `cursor.com/settings`.
- Saved Cursor settings that still pointed at the old settings URL are migrated to the spending dashboard automatically.
- Claude reset timestamps are shown in local date/time format, and the weekly usage card includes its own progress bar.

### Fixed

- Claude email verification pages are no longer mistaken for the signed-in app, so email login is not interrupted before the session is established.
- Claude usage settings detection supports the current hash-routed settings modal.
- Claude usage API responses now preserve the all-model weekly utilization alongside the five-hour meter.
- Cursor Connect now uses an isolated WebKit session store so bloated shared cookies no longer trigger Vercel `494: REQUEST_HEADER_TOO_LARGE` when loading the spending dashboard.
- Cursor sync automatically clears oversized local cookies and retries once, then shows a clear reconnect message if the dashboard still cannot load.
- Cursor sync now prefers the dashboard `get-current-period-usage` response instead of unrelated page JSON or DOM text.
- Cursor API/Auto percentages no longer get mis-scaled when Cursor returns whole-number percent values such as `1.0` for 1%.
- Cursor DOM parsing is scoped to the Included usage section so on-demand or historical percentages are not mistaken for plan usage.
- Cursor background sync now proactively calls the spending-dashboard usage API from the signed-in page context when passive network interception misses it.
- Cursor sync tolerates total-only usage payloads and surfaces a clearer message when Cursor returns `Usage summary is not enabled`.

## [0.4.0] - 2026-05-07

### Added

- Claude support with an isolated local web session, URL validation, and usage parsing from Claude's usage settings page.
- Provider-aware dashboard state for tracking Cursor and Claude side by side.
- Claude usage cards for current session, All models, Claude Design, and reset timing when Claude exposes it.
- Start-at-login setting using macOS login items.
- Local development and notarized DMG verification helper scripts.

### Changed

- Menu bar progress now uses the highest connected provider usage percentage.
- Popover only shows connected providers and keeps a loading state visible while saved provider sessions are still being checked.
- Claude usage UI now renders a stable set of cards instead of changing shape while the page loads.

### Fixed

- Deduplicated repeated Claude usage rows so `All models` and `Claude Design` appear only once.
- Filtered Claude template and explanatory copy so it does not become bogus usage text.
- Prevented the first-run provider connection screen from flashing during startup loading.

## [0.3.0] - 2026-05-06

### Changed

- Replaced menu bar percentage text with a compact progress bar-only status item.
- Kept warning/disconnected states visible in the menu bar with a small status indicator.

## [0.1.0] - 2026-05-05

### Added

- Native macOS menu bar dashboard for Cursor usage.
- Cursor tracking for plan label, total usage, Auto usage, and API usage.
- Local WebKit connection window for Cursor sign-in.
- Background refresh coordinators with cached successful snapshots.
- Unit tests for parsers, settings persistence, coordinators, and dashboard state.
- DMG build script with optional notarization support.
- Public launch docs, screenshots, contribution guide, security policy, and GitHub templates.
- URL validation and host-filtered scraping so AIMeter only loads and parses expected Cursor pages.

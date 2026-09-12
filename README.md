# Search Window Switcher

Prototype searchable KWin declarative effect.

## Behaviour

- Windows are ordered by MRU, with the window that was active when the switcher opened appended at the end.
- The search field is focused immediately.
- Search matches window caption, `resourceClass`, and `resourceName` without changing MRU ordering.
- Up/Down moves the selection with wrap-around:
  - Up on the first result selects the last result.
  - Down on the last result selects the first result.
- Enter activates the highlighted result.
- Escape or clicking outside the panel cancels.
- Ctrl+1 ... Ctrl+9 activates filtered results 1 ... 9.
- Ctrl+0 activates filtered result 10.
- Mouse hover selects a row; clicking activates it.
- A 30-second failsafe timeout automatically dismisses the effect.

The prototype shortcut is `Meta+Alt+Space`.

## Install

```bash
kpackagetool6 --type KWin/Effect --install .
```

To upgrade an existing installation:

```bash
kpackagetool6 --type KWin/Effect --upgrade .
```

KWin may require the effect to be toggled off/on or, in some cases, a logout/login before a newly installed or upgraded QML effect is fully reloaded.

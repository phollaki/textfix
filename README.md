# TextFix

TextFix is a small macOS menu bar app that rewrites the selected text in any app with OpenAI.
Select text, press a hotkey, and TextFix replaces the selection with the result.

| Hotkey | Action |
|---|---|
| Control+Option+R | Rephrase |
| Control+Option+G | Fix grammar |
| Control+Option+T | Translate Hungarian to English |

## Setup

Save your OpenAI API key in the Keychain:

```sh
security add-generic-password -s openai-api-key -a "$USER" -w
```

Build and install the app:

```sh
./install.sh
```

Then turn on TextFix in System Settings > Privacy & Security > Accessibility.
The app is signed ad hoc, so you need to do this again after each install.

The model is set with `TEXTFIX_MODEL` (default `gpt-6-luna`).
The prompts are in `textfix`.

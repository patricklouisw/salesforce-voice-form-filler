# voiceFormFillerV2

Continuous-dictation variant of [voiceFormFiller](../voiceFormFiller/README.md). Web Speech API runs with `continuous=true` and `interimResults=true` so the user can speak through several fields in one take, with natural pauses, and watch interim text update as they go. Recording auto-stops after `autoStopSeconds` (default 30s) or when the user clicks stop.

Use V2 when one OmniScript step needs many fields filled from a longer monologue. Use [V1](../voiceFormFiller/README.md) when each step has only one or two fields and you want a tighter "speak → confirm" loop.

## Differences from V1

| Behavior | V1 | V2 |
| --- | --- | --- |
| `recognition.continuous` | `false` | `true` |
| `recognition.interimResults` | `false` | `true` |
| Transcript handling | Replaced on each `onresult` | Accumulates final chunks in `_finalTranscript`, appends current interim for display |
| `no-speech` errors | Surface to user | Suppressed (frequent during natural pauses in continuous mode) |
| Auto-stop | None | `setTimeout(safeStop, autoStopSeconds * 1000)` after start |
| Extra customAttribute | — | `autoStopSeconds` |
| `masterLabel` | "Voice Form Filler" | "Voice Form Filler V2" |

Everything else — Apex call shape, OmniScript apply, state machine, browser-support gating, fallback resolution from `omniJsonData` — matches V1.

## Browser support

Uses the Web Speech API (`SpeechRecognition` / `webkitSpeechRecognition`).

| Browser | Supported | Notes |
| --- | --- | --- |
| Desktop Chrome | ✅ | Primary target. |
| Desktop Edge | ✅ | Primary target. |
| Desktop Safari | ✅ | Uses the `webkit` prefix. Implementation has historically been flaky. |
| Android Chrome | ✅ | |
| iOS Safari / iOS Chrome | ❌ | Explicitly excluded — `detectBrowserSupport()` detects iOS via UA and returns `false` even though the API technically exists. The component hides itself or shows a hint, controlled by `unsupportedBehavior`. |
| Firefox | ❌ | Does not implement `SpeechRecognition`. |

## Public API (customAttributes)

Same as V1 plus `autoStopSeconds`:

| Attribute | Type | Required | Notes |
| --- | --- | --- | --- |
| `fieldConfig` | JSON string or object | Yes | Map of `{ fieldKey: <spec> }`. Each `<spec>` is either a plain natural-language description string or an object with `description` plus optional `type` (`string`, `number`, `boolean`, `date`, `time`, `datetime`, `array`, `enum`), `enum`, `minimum`, `maximum`. See examples below. |
| `promptDeveloperName` | String | No | Developer name of the Flex Prompt Template. Blank → Apex default (`Voice_Form_Filler`). |
| `languages` | JSON array, CSV, or array | No | Defaults to en-US / es-ES / fr-FR / de-DE. |
| `autoStopSeconds` | Number | No | Default 30. Non-positive / non-finite values fall back to 30. |
| `omniJsonData` | object | No | Experience Cloud fallback source for `fieldConfig` / `promptDeveloperName`. |
| `unsupportedBehavior` | `'hint'` \| `'hide'` | No | Default `'hint'`. |
| `debug` | Boolean / `'true'` | No | Logs setter activity and fallback resolutions. |

See the [V1 README](../voiceFormFiller/README.md) for the Experience Cloud fallback keys — they work identically here.

### Example `fieldConfig` (short form)

```json
{
  "firstName": "person's first name",
  "lastName":  "person's last name",
  "age":       "age in years as a number"
}
```

### Example `fieldConfig` (rich form)

Each value can be an object that pins down the type, enum, and bounds. The descriptions also tell the model how to *format* the value (e.g. phone digits without dashes, semicolon-joined multi-selects, ISO date/time strings). This shape works well in V2 because the longer continuous transcript is more likely to mention several typed fields in one take:

```json
{
  "firstNamev3": { "description": "first name of the user", "type": "string" },
  "lastNamev3":  { "description": "last name of the user",  "type": "string" },
  "emailv3":     { "description": "email address of the user", "type": "string" },
  "phonev3": {
    "description": "phone number of the user. You must provide the number without dashes, example: 4371234567",
    "type": "string"
  },
  "numberv3": {
    "description": "number of children the user has, integer between 0 and 10 inclusive",
    "type": "number",
    "minimum": 0,
    "maximum": 10
  },
  "IsMarriedv3": { "description": "whether the user is married", "type": "boolean" },
  "socialv3": {
    "description": "social media profile URL of the user. Must include the https:// prefix, example: https://instagram.com/username",
    "type": "string"
  },
  "annualIncomev3": {
    "description": "annual income of the user in dollars, must be zero or greater (no negative values)",
    "type": "number",
    "minimum": 0
  },
  "arrivalDatev3": { "description": "arrival date in YYYY-MM-DD format", "type": "date" },
  "arrivalTimev3": {
    "description": "arrival time in HH:mm:ss.SSSZ format (24-hour UTC), example: 01:00:00.000Z",
    "type": "time"
  },
  "departureDateTimev3": {
    "description": "departure date and time in ISO 8601 UTC format with milliseconds, example: 2026-05-14T16:00:00.000Z",
    "type": "datetime"
  },
  "petsv3": {
    "description": "pets the user has; choose one or more of: Dog, Cat, No Pets. Return as a semicolon-separated string with no spaces, example: 'Dog;Cat'. If only one is chosen, return just that value, example: 'Dog'",
    "type": "array",
    "enum": ["Dog", "Cat", "No Pets"]
  },
  "sinv3": {
    "description": "social insurance number of the user, 9 digits without spaces or dashes",
    "type": "string"
  },
  "selectv3": {
    "description": "preferred language",
    "type": "enum",
    "enum": ["English", "Spanish"]
  },
  "radiov3": {
    "description": "whether a password is required; Yes or No",
    "type": "enum",
    "enum": ["Yes", "No"]
  },
  "rangev3": {
    "description": "estimated number of souvenirs, integer between 5 and 10 inclusive",
    "type": "number",
    "minimum": 5,
    "maximum": 10
  },
  "addressv3": {
    "description": "street address including city, state, and zip if mentioned",
    "type": "string"
  },
  "reasonForContactingv3": {
    "description": "reason the user is contacting us, summarized in their own words",
    "type": "string"
  },
  "disclosurev3": {
    "description": "whether the user consents to the terms and conditions",
    "type": "boolean"
  }
}
```

The Apex controller filters the LLM response down to keys that exist in this map and drops null / blank values before returning to the LWC, so any extra keys the model invents are silently discarded.

## States

Same machine as V1 (`IDLE` / `LISTENING` / `TRANSCRIBED` / `PROCESSING` / `DONE` / `ERROR`). Notable continuous-mode behavior:

- During `LISTENING`, interim transcript updates live but is not committed to `_finalTranscript` until the recognizer marks a result final.
- `onend` transitions to `TRANSCRIBED` only if `_finalTranscript` has content; otherwise back to `IDLE`.
- `handleRetry` clears both `transcript` and `_finalTranscript`.

## Apex contract

Identical to V1 — imports [`extractFieldValues`](../../classes/VoiceFormFillerController.md) and forwards the resolved transcript, field config, language, and prompt developer name.

## Files

- [voiceFormFillerV2.js](voiceFormFillerV2.js)
- [voiceFormFillerV2.html](voiceFormFillerV2.html)
- [voiceFormFillerV2.css](voiceFormFillerV2.css)
- [voiceFormFillerV2.js-meta.xml](voiceFormFillerV2.js-meta.xml)

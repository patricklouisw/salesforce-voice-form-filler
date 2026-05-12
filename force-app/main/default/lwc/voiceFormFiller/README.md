# voiceFormFiller

Single-utterance voice-to-form LWC for OmniScript. The user clicks the mic, speaks one sentence ("My name is Peter, I am 42"), and the component sends the transcript to a Flex Prompt Template via `VoiceFormFillerController.extractFieldValues`. The returned key/value pairs are applied to the surrounding OmniScript via `omniApplyCallResp` (provided by `OmniscriptBaseMixin`).

For continuous multi-field dictation (one take across multiple fields, with natural pauses), use [voiceFormFillerV2](../voiceFormFillerV2/README.md) instead.

## Where it runs

`isExposed=true` with `runtimeNamespace=omnistudio`. Configured in [voiceFormFiller.js-meta.xml](voiceFormFiller.js-meta.xml) for:
- App Page / Record Page / Home Page (Lightning App Builder)
- Experience Cloud pages

Primary intended use is as a Custom LWC step inside an OmniScript.

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

| Attribute | Type | Required | Notes |
| --- | --- | --- | --- |
| `fieldConfig` | JSON string or object | Yes | Map of `{ fieldKey: <spec> }`. Each `<spec>` is either a plain natural-language description string, or an object with `description` plus optional `type` (`string`, `number`, `boolean`, `date`, `time`, `datetime`, `array`, `enum`), `enum`, `minimum`, `maximum`. The Prompt Template uses these to decide which transcript phrases map to which keys and how to format the value. Keys must match the OmniScript element names you want to prefill. |
| `promptDeveloperName` | String | No | Developer name of the Flex Prompt Template to invoke. Blank → Apex falls back to `Voice_Form_Filler`. |
| `languages` | JSON array, CSV string, or array | No | Languages offered in the dropdown. Each entry is either a string `code` or an object `{ code, label }`. Defaults to en-US / es-ES / fr-FR / de-DE. |
| `omniJsonData` | object | No | OmniScript data JSON. Aura runtime injects this automatically in Experience Cloud where customAttributes can be dropped. Used as a fallback to find `fieldConfig` / `promptDeveloperName`. |
| `unsupportedBehavior` | `'hint'` \| `'hide'` | No | Default `'hint'`. Controls what renders on iOS / unsupported browsers. |
| `debug` | Boolean / `'true'` | No | When true, the component logs setter inputs and the fallback resolutions to the console. |

### Example `fieldConfig` (short form)

```json
{
  "firstName": "person's first name",
  "lastName":  "person's last name",
  "age":       "age in years as a number"
}
```

### Example `fieldConfig` (rich form)

Each value can be an object that pins down the type, enum, and bounds. The descriptions also tell the model how to *format* the value (e.g. phone digits without dashes, semicolon-joined multi-selects, ISO date/time strings):

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

### Experience Cloud fallback

When OmniScript runs inside Experience Cloud, custom attributes on a Custom LWC step are sometimes dropped before they reach the LWC. To work around this:

1. Place a Text/Text Area element (or Set Values action) in the same OmniScript step with the JSON value stored under one of these key names: `fieldConfig`, `fieldConfigJson`, `voiceFieldConfig`, `fieldConfigSource`.
2. For the prompt template name, use the key name `promptDeveloperName`.

The component searches the `omniJsonData` tree recursively for the first matching key and uses that value if the @api customAttribute is empty.

## States (rendered in [voiceFormFiller.html](voiceFormFiller.html))

- `IDLE` — mic button shown, prompt to start
- `LISTENING` — destructive stop button, "Listening..." label
- `TRANSCRIBED` — shows what was heard, with "Use this & fill form" / "Try again"
- `PROCESSING` — spinner while Apex is in flight
- `DONE` — success message + optional debug summary of filled keys
- `ERROR` — destructive-colored error message + retry

## Apex contract

Imports `extractFieldValues` from [VoiceFormFillerController](../../classes/VoiceFormFillerController.md). The LWC calls:

```js
extractFieldValues({
  transcript,             // raw user speech
  fieldConfigJson,        // resolved JSON string
  language,               // BCP-47 like "en-US"
  promptDeveloperName     // resolved name, or null for default
});
```

The returned `Map<String, Object>` is then passed to `omniApplyCallResp` to merge into the OmniScript data JSON.

## Files

- [voiceFormFiller.js](voiceFormFiller.js) — component class
- [voiceFormFiller.html](voiceFormFiller.html) — template
- [voiceFormFiller.css](voiceFormFiller.css) — styles
- [voiceFormFiller.js-meta.xml](voiceFormFiller.js-meta.xml) — bundle metadata

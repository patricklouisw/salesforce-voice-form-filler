# Voice Form Filler

Salesforce DX bundle that adds voice-driven field prefill to OmniScript. The user speaks; the Web Speech API transcribes; an Apex controller hands the transcript and a field-config JSON to a Flex Prompt Template; Einstein returns a JSON object of extracted values; the LWC merges those values into the OmniScript data JSON.

```
LWC (mic + transcript)
   │  extractFieldValues(transcript, fieldConfigJson, language, promptDeveloperName)
   ▼
VoiceFormFillerController.cls
   │  ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(...)
   ▼
Voice_Form_Filler  (Flex Prompt Template, Vertex AI Gemini 2.5 Flash Lite)
   │  { fieldKey: value | null, ... }
   ▼
LWC → omniApplyCallResp → OmniScript data
```

## Components

### LWCs

- **[voiceFormFiller](force-app/main/default/lwc/voiceFormFiller/README.md)** — single-utterance variant. One click, one sentence, transcript shown, user confirms, fields filled. Web Speech API runs with `continuous=false`. Use when each OmniScript step has only one or two fields and you want a tight "speak → confirm" loop.
- **[voiceFormFillerV2](force-app/main/default/lwc/voiceFormFillerV2/README.md)** — continuous-dictation variant. `continuous=true` and `interimResults=true` so the user can talk through several fields in one take with natural pauses and see interim text update live. Auto-stops after `autoStopSeconds` (default 30s). Use when one step needs many fields filled from a longer monologue.

Both LWCs share the same Apex contract, OmniScript apply via `OmniscriptBaseMixin.omniApplyCallResp`, state machine (`IDLE` → `LISTENING` → `TRANSCRIBED` → `PROCESSING` → `DONE` / `ERROR`), browser-support gating (Chrome/Edge desktop; iOS Safari excluded), and Experience Cloud fallback that recursively searches `omniJsonData` for `fieldConfig` / `promptDeveloperName` when custom attributes are dropped by the runtime.

The full public customAttributes table (including `fieldConfig`, `promptDeveloperName`, `languages`, `unsupportedBehavior`, `debug`, and V2's `autoStopSeconds`) plus short-form and rich-form `fieldConfig` examples live in each component's README.

### Apex

- **[VoiceFormFillerController](force-app/main/default/classes/VoiceFormFillerController.md)** — `with sharing` `@AuraEnabled` bridge between the LWCs and the prompt template. Single public method:

  ```apex
  Map<String, Object> extractFieldValues(
      String transcript,
      String fieldConfigJson,
      String language,
      String promptDeveloperName
  )
  ```

  Builds the three Free Text inputs (`Input:transcript`, `Input:fieldConfig`, `Input:language`), calls `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate`, walks `generations[0]` for the first non-blank generation text (`response` / `text` / `generation` / `content` / `message` — the property name has drifted across releases), strips ```` ```json ```` fences if present, parses the result, and filters the map down to keys that exist in `fieldConfigJson` with non-null, non-blank values. Defaults `language` to `en-US` and `promptDeveloperName` to `Voice_Form_Filler` when blank. Throws `AuraHandledException` for blank transcript, invalid field-config JSON, Prompt Builder errors, empty response, or non-JSON output.

  A `@TestVisible` `testMockResponse` lets [VoiceFormFillerControllerTest](force-app/main/default/classes/VoiceFormFillerControllerTest.cls) bypass `ConnectApi.EinsteinLLM` so tests don't need Prompt Builder licensing in the running org while still exercising the input-building path.

### GenAI Prompt Template

- **[Voice_Form_Filler](force-app/main/default/genAiPromptTemplates/Voice_Form_Filler.genAiPromptTemplate-meta.xml)** — Flex Prompt Template (`type=einstein_gpt__flex`, primary model `sfdc_ai__DefaultVertexAIGemini25FlashLite001`, visibility `Global`). Three required Free Text inputs match the Apex contract:

  | Input | Used for |
  | --- | --- |
  | `transcript` | Raw user speech |
  | `fieldConfig` | JSON map of field keys → description string OR `{description, type, enum?, minimum?, maximum?}` |
  | `language` | BCP-47 locale of the transcript (e.g. `en-US`) |

  The prompt frames the model as a deterministic extraction engine and pins down the rules: extract only what the user actually said (no inference, no hallucination), strip filler and self-corrections (`"Smyth — no, Smith"` → `"Smith"`), preserve proper-noun capitalization including compound names (`McDonald`, `O'Brien`, `de la Cruz`), honor type hints (`number`/`integer` → JSON number; `date` → `YYYY-MM-DD`; `boolean` → `true`/`false`; `enum` → exactly one of the allowed values or `null`), translate only when the type implies it (numbers in any language → digits, spoken dates → ISO, `sí`/`non` → boolean), keep names and free text in the spoken language, return every key from the field config (missing → `null`), and emit only the raw JSON object with no fences, prose, or extra keys.

  Eight worked examples in the template cover the common shapes: simple English, partial information, Spanish with date, English self-correction, nothing usable, French with integer, enum mapping, and compound-name preservation.

  The developer name `Voice_Form_Filler` is what the Apex falls back to when the LWC's `promptDeveloperName` customAttribute is blank. Cloning this template and pointing the LWC at the clone's developer name is the supported way to drive multiple prompt variants from one deployed LWC bundle.

## Source layout

```
force-app/main/default/
├── lwc/
│   ├── voiceFormFiller/        ← V1, single-utterance
│   └── voiceFormFillerV2/      ← V2, continuous dictation
├── classes/
│   ├── VoiceFormFillerController.cls
│   └── VoiceFormFillerControllerTest.cls
└── genAiPromptTemplates/
    └── Voice_Form_Filler.genAiPromptTemplate-meta.xml
```

## Salesforce DX project docs

- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference.htm)
- [Salesforce Extensions for VS Code](https://developer.salesforce.com/tools/vscode/)

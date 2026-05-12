# VoiceFormFillerController

`@AuraEnabled` bridge between the [voiceFormFiller](../lwc/voiceFormFiller/README.md) and [voiceFormFillerV2](../lwc/voiceFormFillerV2/README.md) LWCs and a Flex Prompt Template in Prompt Builder. Takes a raw transcript plus a field-config JSON, asks Einstein to extract values, and returns a filtered `Map<String, Object>` keyed by the configured fields.

The class is `with sharing` and only exposes one method to clients.

## Public method

```apex
@AuraEnabled
public static Map<String, Object> extractFieldValues(
    String transcript,
    String fieldConfigJson,
    String language,
    String promptDeveloperName
)
```

| Param | Required | Notes |
| --- | --- | --- |
| `transcript` | Yes | Raw user speech. Blank → `AuraHandledException`. |
| `fieldConfigJson` | Yes | JSON map of `{ fieldKey: "natural-language description" }`. Must parse to a `Map<String, Object>`. |
| `language` | No | BCP-47 locale (e.g. `"en-US"`). Blank → defaults to `"en-US"`. |
| `promptDeveloperName` | No | Developer name of the Flex Prompt Template to invoke. Blank → defaults to `DEFAULT_PROMPT_DEVELOPER_NAME` (`Voice_Form_Filler`). |

Returns the LLM's extraction filtered to:
1. only keys that exist in `fieldConfigJson`, and
2. only values that are non-null and not blank strings.

Throws `AuraHandledException` for: blank transcript, blank/invalid field-config JSON, Prompt Builder error, empty LLM response, or non-JSON LLM output.

## Prompt Template contract

The class invokes `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(promptDeveloperName, …)` and passes three Free Text inputs:

| Input | Source |
| --- | --- |
| `Input:transcript` | `transcript` param |
| `Input:fieldConfig` | `fieldConfigJson` param (the raw JSON string) |
| `Input:language` | `language` param, or `"en-US"` if blank |

The template **must** return a single JSON object whose keys are the configured field keys. Markdown code fences (```json ... ```) are tolerated — see `stripCodeFences`.

## Response parsing

`ConnectApi.EinsteinPromptTemplateGenerationsRepresentation` has shipped with the generation text under different property names across releases (`response`, `text`, `generation`, `content`, `message`). To stay resilient, the class serializes the result to JSON and walks the `generations[0]` map, returning the first non-blank string among those candidate keys (see `pluckText`).

## Configuring the prompt template at runtime

Historically the developer name was a hardcoded constant. It is now passed from the LWC so a single deployed bundle can drive multiple Prompt Templates.

- The Apex layer keeps `DEFAULT_PROMPT_DEVELOPER_NAME = 'Voice_Form_Filler'` as the fallback.
- LWC callers expose a `promptDeveloperName` customAttribute on the component — see [voiceFormFiller README](../lwc/voiceFormFiller/README.md#public-api-customattributes).
- In OmniStudio, set the customAttribute to the developer name (e.g. `Patient_Intake_Prompt`) on the Custom LWC step. Leave it blank to use the default.

## Test seam

`testMockResponse` (a `@TestVisible` static `String`) lets unit tests bypass `ConnectApi.EinsteinLLM`. When set inside `@IsTest`, `invokePromptTemplate` short-circuits *after* the input map has been built and returns the mock string. This means tests still exercise the input-building code path but do not require Prompt Builder licensing in the running org.

```apex
VoiceFormFillerController.testMockResponse =
    '{"firstName":"Peter","lastName":"OBrien","age":42}';
Map<String, Object> result = VoiceFormFillerController.extractFieldValues(
    'My name is Peter OBrien, I am 42.',
    '{"firstName":"first name","lastName":"last name","age":"age in years"}',
    'en-US',
    null
);
```

See [VoiceFormFillerControllerTest.cls](VoiceFormFillerControllerTest.cls) for the full suite, including direct coverage of `extractTextFromSerializedResult`, `pluckText`, and `stripCodeFences`.

## Files

- [VoiceFormFillerController.cls](VoiceFormFillerController.cls) — controller
- [VoiceFormFillerController.cls-meta.xml](VoiceFormFillerController.cls-meta.xml) — Apex metadata
- [VoiceFormFillerControllerTest.cls](VoiceFormFillerControllerTest.cls) — tests

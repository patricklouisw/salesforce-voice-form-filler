/**
 * VoiceFormFillerController
 * -------------------------
 * Bridges the voiceFormFiller LWC to a Flex Prompt Template in Prompt Builder.
 * The Prompt Template (developer name passed in by the LWC, or the default
 * below) is expected to have three input variables of type Free Text:
 * transcript, fieldConfig, language. It must return a single JSON object whose
 * keys match the field config keys.
 */
public with sharing class VoiceFormFillerController {

    // Fallback developer name when the caller does not supply one.
    @TestVisible
    private static String DEFAULT_PROMPT_DEVELOPER_NAME = 'Voice_Form_Filler';

    // Test seam: when set inside an @IsTest context, invokePromptTemplate
    // returns this string instead of calling ConnectApi.EinsteinLLM. Lets us
    // test the full controller without a Prompt Builder dependency.
    @TestVisible
    private static String testMockResponse;

    /**
     * Called from the LWC. Sends the transcript + field config to the prompt
     * template, parses the JSON response, and returns only keys that exist
     * in the original field config (and that have non-null, non-empty values).
     */
    @AuraEnabled
    public static Map<String, Object> extractFieldValues(
        String transcript,
        String fieldConfigJson,
        String language,
        String promptDeveloperName
    ) {
        if (String.isBlank(transcript)) {
            throwClient('Transcript is empty.');
        }
        if (String.isBlank(fieldConfigJson)) {
            throwClient('Field configuration is missing.');
        }

        Map<String, Object> fieldConfig;
        try {
            fieldConfig = (Map<String, Object>) JSON.deserializeUntyped(fieldConfigJson);
        } catch (Exception e) {
            throwClient('Field configuration is not valid JSON: ' + e.getMessage());
        }

        String templateName = String.isBlank(promptDeveloperName)
            ? DEFAULT_PROMPT_DEVELOPER_NAME
            : promptDeveloperName;

        String rawResponse;
        try {
            rawResponse = invokePromptTemplate(transcript, fieldConfigJson, language, templateName);
        } catch (Exception e) {
            throwClient('Prompt Builder call failed: ' + e.getMessage());
        }

        String cleaned = stripCodeFences(rawResponse);

        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
        } catch (Exception e) {
            throwClient('Model returned non-JSON output: ' + cleaned);
        }

        // Filter to keys present in fieldConfig and drop nulls / empty strings.
        Map<String, Object> filtered = new Map<String, Object>();
        for (String key : parsed.keySet()) {
            if (!fieldConfig.containsKey(key)) continue;
            Object v = parsed.get(key);
            if (v == null) continue;
            if (v instanceof String && String.isBlank((String) v)) continue;
            filtered.put(key, v);
        }
        return filtered;
    }

    // ----------------- internals -----------------

    private static String invokePromptTemplate(
        String transcript,
        String fieldConfigJson,
        String language,
        String promptDeveloperName
    ) {
        ConnectApi.WrappedValue transcriptInput = new ConnectApi.WrappedValue();
        transcriptInput.value = transcript;

        ConnectApi.WrappedValue fieldConfigInput = new ConnectApi.WrappedValue();
        fieldConfigInput.value = fieldConfigJson;

        ConnectApi.WrappedValue languageInput = new ConnectApi.WrappedValue();
        languageInput.value = String.isBlank(language) ? 'en-US' : language;

        Map<String, ConnectApi.WrappedValue> inputParams =
            new Map<String, ConnectApi.WrappedValue>{
                'Input:transcript'  => transcriptInput,
                'Input:fieldConfig' => fieldConfigInput,
                'Input:language'    => languageInput
            };

        ConnectApi.EinsteinPromptTemplateGenerationsInput pInput =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        pInput.inputParams = inputParams;
        pInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        pInput.additionalConfig.applicationName = 'PromptBuilderPreview';
        pInput.isPreview = false;

        // Test seam: in tests, skip the actual LLM call and return the mock.
        // Placed *after* input building so the input-building code is exercised.
        if (Test.isRunningTest() && testMockResponse != null) {
            return testMockResponse;
        }

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation result =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                promptDeveloperName,
                pInput
            );

        if (result == null) {
            throwClient('Empty response from Prompt Builder.');
        }
        // Read the response generically via JSON so we don't depend on the
        // exact property name (it has been "response", "text", or "generation"
        // across recent releases).
        String serialized = JSON.serialize(result, /*suppressNulls*/ true);
        return extractTextFromSerializedResult(serialized);
    }

    /**
     * Pulls the first non-blank generation text from a serialized
     * EinsteinPromptTemplateGenerationsRepresentation. TestVisible so unit
     * tests can exercise the parser directly without a live LLM call.
     */
    @TestVisible
    private static String extractTextFromSerializedResult(String serialized) {
        Map<String, Object> resultMap =
            (Map<String, Object>) JSON.deserializeUntyped(serialized);

        List<Object> generations = (List<Object>) resultMap.get('generations');
        if (generations == null || generations.isEmpty()) {
            throwClient('Empty response from Prompt Builder.');
        }

        String text = pluckText((Map<String, Object>) generations[0]);
        if (String.isBlank(text)) {
            throwClient('Empty response from Prompt Builder.');
        }
        return text;
    }

    /**
     * Find the first non-blank string value among common LLM response field
     * names. Defensive: the underlying property has changed across releases.
     */
    @TestVisible
    private static String pluckText(Map<String, Object> gen) {
        String[] candidates = new String[]{
            'response', 'text', 'generation', 'content', 'message'
        };
        for (String key : candidates) {
            Object v = gen.get(key);
            if (v instanceof String && !String.isBlank((String) v)) {
                return (String) v;
            }
        }
        return null;
    }

    /**
     * Some models wrap JSON in markdown code fences despite instructions.
     * Strip ```json ... ``` or ``` ... ``` if present.
     */
    @TestVisible
    private static String stripCodeFences(String input) {
        if (String.isBlank(input)) return input;
        String s = input.trim();
        if (s.startsWith('```')) {
            Integer firstNewline = s.indexOf('\n');
            if (firstNewline > 0) {
                s = s.substring(firstNewline + 1);
            } else {
                s = s.substring(3);
            }
            if (s.endsWith('```')) {
                s = s.substring(0, s.length() - 3);
            }
        }
        return s.trim();
    }

    private static void throwClient(String msg) {
        AuraHandledException ahe = new AuraHandledException(msg);
        ahe.setMessage(msg);
        throw ahe;
    }
}

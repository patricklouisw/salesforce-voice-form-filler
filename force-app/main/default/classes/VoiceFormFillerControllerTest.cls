/**
 * Tests for VoiceFormFillerController.
 *
 * Bypasses ConnectApi.EinsteinLLM via the controller's testMockResponse seam,
 * so these tests run in any org regardless of Prompt Builder licensing.
 */
@IsTest
private class VoiceFormFillerControllerTest {

    private static final String FIELD_CONFIG_JSON =
        '{"firstName":"first name","lastName":"last name","age":"age in years"}';

    @IsTest
    static void extractFieldValues_returnsFilteredMap_onValidLlmResponse() {
        VoiceFormFillerController.testMockResponse =
            '{"firstName":"Peter","lastName":"OBrien","age":42,"unknownKey":"ignored"}';

        Test.startTest();
        Map<String, Object> result = VoiceFormFillerController.extractFieldValues(
            'My name is Peter OBrien, I am 42.',
            FIELD_CONFIG_JSON,
            'en-US',
            null
        );
        Test.stopTest();

        System.assertEquals('Peter', (String) result.get('firstName'));
        System.assertEquals('OBrien', (String) result.get('lastName'));
        System.assertEquals(42, (Integer) result.get('age'));
        System.assertEquals(false, result.containsKey('unknownKey'));
        System.assertEquals(3, result.size());
    }

    @IsTest
    static void extractFieldValues_dropsNullsAndEmptyStrings() {
        VoiceFormFillerController.testMockResponse =
            '{"firstName":"Peter","lastName":null,"age":""}';

        Test.startTest();
        Map<String, Object> result = VoiceFormFillerController.extractFieldValues(
            'I am Peter.',
            FIELD_CONFIG_JSON,
            'en-US',
            null
        );
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals('Peter', (String) result.get('firstName'));
        System.assertEquals(false, result.containsKey('lastName'));
        System.assertEquals(false, result.containsKey('age'));
    }

    @IsTest
    static void extractFieldValues_stripsCodeFences_inLlmResponse() {
        VoiceFormFillerController.testMockResponse =
            '```json\n{"firstName":"Maria"}\n```';

        Test.startTest();
        Map<String, Object> result = VoiceFormFillerController.extractFieldValues(
            'I am Maria.',
            FIELD_CONFIG_JSON,
            'es-ES',
            null
        );
        Test.stopTest();

        System.assertEquals('Maria', (String) result.get('firstName'));
    }

    @IsTest
    static void extractFieldValues_defaultsLanguage_whenBlank() {
        VoiceFormFillerController.testMockResponse = '{"firstName":"Sam"}';

        Test.startTest();
        Map<String, Object> result = VoiceFormFillerController.extractFieldValues(
            'I am Sam.',
            FIELD_CONFIG_JSON,
            null,
            null
        );
        Test.stopTest();

        System.assertEquals('Sam', (String) result.get('firstName'));
    }

    @IsTest
    static void extractFieldValues_acceptsCustomPromptDeveloperName() {
        VoiceFormFillerController.testMockResponse = '{"firstName":"Lee"}';

        Test.startTest();
        Map<String, Object> result = VoiceFormFillerController.extractFieldValues(
            'I am Lee.',
            FIELD_CONFIG_JSON,
            'en-US',
            'Custom_Prompt_Template'
        );
        Test.stopTest();

        System.assertEquals('Lee', (String) result.get('firstName'));
    }

    @IsTest
    static void extractFieldValues_throws_onBlankTranscript() {
        Boolean threw = false;
        try {
            VoiceFormFillerController.extractFieldValues('', FIELD_CONFIG_JSON, 'en-US', null);
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('Transcript'),
                'message should mention transcript: ' + e.getMessage());
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void extractFieldValues_throws_onBlankFieldConfig() {
        Boolean threw = false;
        try {
            VoiceFormFillerController.extractFieldValues('hello', '', 'en-US', null);
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('Field configuration'));
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void extractFieldValues_throws_onInvalidFieldConfigJson() {
        Boolean threw = false;
        try {
            VoiceFormFillerController.extractFieldValues(
                'hello', 'this-is-not-json', 'en-US', null
            );
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('valid JSON'));
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void extractFieldValues_throws_onNonJsonModelOutput() {
        VoiceFormFillerController.testMockResponse =
            'I cannot extract anything from that.';

        Boolean threw = false;
        try {
            Test.startTest();
            VoiceFormFillerController.extractFieldValues(
                'mumble mumble', FIELD_CONFIG_JSON, 'en-US', null
            );
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('non-JSON'));
        }
        System.assertEquals(true, threw);
    }

    // ---------- direct parser-helper coverage ----------

    @IsTest
    static void extractTextFromSerializedResult_findsResponseField() {
        String text = VoiceFormFillerController.extractTextFromSerializedResult(
            '{"generations":[{"response":"hello world"}]}'
        );
        System.assertEquals('hello world', text);
    }

    @IsTest
    static void extractTextFromSerializedResult_findsTextField() {
        String text = VoiceFormFillerController.extractTextFromSerializedResult(
            '{"generations":[{"text":"hello text"}]}'
        );
        System.assertEquals('hello text', text);
    }

    @IsTest
    static void extractTextFromSerializedResult_findsGenerationField() {
        String text = VoiceFormFillerController.extractTextFromSerializedResult(
            '{"generations":[{"generation":"hello generation"}]}'
        );
        System.assertEquals('hello generation', text);
    }

    @IsTest
    static void extractTextFromSerializedResult_findsContentField() {
        String text = VoiceFormFillerController.extractTextFromSerializedResult(
            '{"generations":[{"content":"hello content"}]}'
        );
        System.assertEquals('hello content', text);
    }

    @IsTest
    static void extractTextFromSerializedResult_findsMessageField() {
        String text = VoiceFormFillerController.extractTextFromSerializedResult(
            '{"generations":[{"message":"hello message"}]}'
        );
        System.assertEquals('hello message', text);
    }

    @IsTest
    static void extractTextFromSerializedResult_throws_onMissingGenerations() {
        Boolean threw = false;
        try {
            VoiceFormFillerController.extractTextFromSerializedResult('{}');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'missing generations should throw');
    }

    @IsTest
    static void extractTextFromSerializedResult_throws_onEmptyGenerations() {
        Boolean threw = false;
        try {
            VoiceFormFillerController.extractTextFromSerializedResult(
                '{"generations":[]}'
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'empty generations should throw');
    }

    @IsTest
    static void extractTextFromSerializedResult_throws_onUnknownTextField() {
        Boolean threw = false;
        try {
            VoiceFormFillerController.extractTextFromSerializedResult(
                '{"generations":[{"someOtherField":"x"}]}'
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'no recognizable text field should throw');
    }

    @IsTest
    static void pluckText_returnsNull_whenNoCandidatesMatch() {
        Map<String, Object> gen = new Map<String, Object>{
            'unknownA' => 'x',
            'unknownB' => 'y'
        };
        System.assertEquals(null, VoiceFormFillerController.pluckText(gen));
    }

    @IsTest
    static void pluckText_skipsBlankStrings() {
        Map<String, Object> gen = new Map<String, Object>{
            'response' => '   ',
            'text'     => 'real value'
        };
        System.assertEquals('real value', VoiceFormFillerController.pluckText(gen));
    }

    @IsTest
    static void stripCodeFences_handlesAllShapes() {
        System.assertEquals('{"a":1}',
            VoiceFormFillerController.stripCodeFences('{"a":1}'));
        System.assertEquals('{"a":1}',
            VoiceFormFillerController.stripCodeFences('```json\n{"a":1}\n```'));
        System.assertEquals('{"a":1}',
            VoiceFormFillerController.stripCodeFences('```\n{"a":1}\n```'));
        System.assertEquals(null,
            VoiceFormFillerController.stripCodeFences(null));
        System.assertEquals('',
            VoiceFormFillerController.stripCodeFences(''));
    }
}

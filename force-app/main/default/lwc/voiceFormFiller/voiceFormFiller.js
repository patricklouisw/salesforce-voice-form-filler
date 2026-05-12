/**
 * @description       :
 * @author            : Cloud SynApps Inc.
 * @last modified on  : 2026-05-07
 * @last modified by  : Nicolas Stalteri
**/
import { LightningElement, api, track } from 'lwc';
import { OmniscriptBaseMixin } from 'omnistudio/omniscriptBaseMixin';
import extractFieldValues from '@salesforce/apex/VoiceFormFillerController.extractFieldValues';

const STATE = {
    IDLE: 'idle',
    LISTENING: 'listening',
    TRANSCRIBED: 'transcribed',
    PROCESSING: 'processing',
    DONE: 'done',
    ERROR: 'error'
};

const DEFAULT_LANGUAGES = [
    { code: 'en-US', label: 'English (US)' },
    { code: 'es-ES', label: 'Spanish (Spain)' },
    { code: 'fr-FR', label: 'French' },
    { code: 'de-DE', label: 'German' }
];

export default class VoiceFormFiller extends OmniscriptBaseMixin(LightningElement) {

    _debug = false;
    @api
    get debug() {
        return this._debug;
    }
    set debug(value) {
        this._debug = (value === true || value === 'true');
    }

    _languagesRaw;
    _languages = DEFAULT_LANGUAGES;
    @api
    get languages() {
        return this._languagesRaw;
    }
    set languages(value) {
        let val;
        if (value && typeof value === 'string') {
            val = JSON.parse(value);
        } else if (value && (Array.isArray(value) || typeof value === 'object')) {
            val = [...value];
        }
        this.log('[voiceFormFiller] @api languages setter called with:',
            val, '(type:', typeof value, ')');
        this._languagesRaw = val;
        const parsed = parseLanguages(val);
        this.log('[voiceFormFiller] languages parsed to:', parsed);
        if (parsed && parsed.length > 0) {
            this._languages = parsed;
            if (!parsed.find((l) => l.code === this.selectedLang)) {
                this.selectedLang = parsed[0].code;
            }
        }
    }

    _promptDeveloperName;
    @api
    get promptDeveloperName() {
        return this._promptDeveloperName;
    }
    set promptDeveloperName(value) {
        this._promptDeveloperName =
            typeof value === 'string' ? value.trim() : value;
        this.log('[voiceFormFiller] @api promptDeveloperName setter called with:',
            this._promptDeveloperName);
    }

    _fieldConfig;
    @api
    get fieldConfig() {
        return this._fieldConfig;
    }
    set fieldConfig(value) {
        let val;
        if (typeof value === 'string') {
            val = JSON.parse(value);
        } else if (value && (typeof value === 'object')) {
            val = Object.assign({}, value);
        }
        this.log('[voiceFormFiller] @api fieldConfig setter called with:',
            val, '(type:', typeof val, ', length:',
            val && val.length, ')');
        this._fieldConfig = val;
    }

    /**
     * OmniScript data JSON. Aura runtime in Experience Cloud reliably
     * injects this even when customAttributes are dropped. We use it as
     * a fallback to find fieldConfig in a sibling Text Area / Set Values.
     */
    _omniJsonData;
    @api
    get omniJsonData() {
        return this._omniJsonData;
    }
    set omniJsonData(value) {
        this._omniJsonData = value;
        this.log('[voiceFormFiller] omniJsonData setter called with:',
            value ? JSON.stringify(value) : value);
    }

    @api unsupportedBehavior = 'hint';

    @track selectedLang = 'en-US';
    @track state = STATE.IDLE;
    @track transcript = '';
    @track errorMessage = '';
    @track lastFilled = null;
    @track isBrowserSupported = true;

    recognition;

    connectedCallback() {
        this.log('[voiceFormFiller] connectedCallback - state at mount:', {
            languagesRaw: this._languagesRaw,
            languagesParsed: this._languages,
            fieldConfig: this._fieldConfig,
            fieldConfigType: typeof this._fieldConfig,
            fieldConfigLength: this._fieldConfig && this._fieldConfig.length,
            selectedLang: this.selectedLang,
            unsupportedBehavior: this.unsupportedBehavior
        });
        if (this._languages && this._languages.length > 0 &&
            !this._languages.find((l) => l.code === this.selectedLang)) {
            this.selectedLang = this._languages[0].code;
        }
        this.isBrowserSupported = this.detectBrowserSupport();
        this.log('[voiceFormFiller] isBrowserSupported:', this.isBrowserSupported,
            'userAgent:', navigator.userAgent);
        if (this.isBrowserSupported) {
            this.initRecognition();
        }
    }

    disconnectedCallback() {
        this.safeStop();
    }

    detectBrowserSupport() {
        const hasApi = !!(window.SpeechRecognition || window.webkitSpeechRecognition);
        if (!hasApi) return false;
        const ua = navigator.userAgent || '';
        const isIOS = /iPad|iPhone|iPod/.test(ua) && !window.MSStream;
        if (isIOS) return false;
        return true;
    }

    initRecognition() {
        const SpeechRecognition =
            window.SpeechRecognition || window.webkitSpeechRecognition;
        if (!SpeechRecognition) return;

        this.recognition = new SpeechRecognition();
        this.recognition.continuous = false;
        this.recognition.interimResults = false;
        this.recognition.maxAlternatives = 1;
        this.recognition.lang = this.selectedLang;

        this.recognition.onresult = (event) => {
            const t = event && event.results && event.results[0] && event.results[0][0]
                ? event.results[0][0].transcript || ''
                : '';
            this.transcript = t.trim();
            this.state = this.transcript ? STATE.TRANSCRIBED : STATE.IDLE;
        };
        this.recognition.onerror = (event) => {
            this.state = STATE.ERROR;
            this.errorMessage = this.formatRecognitionError(event && event.error);
        };
        this.recognition.onend = () => {
            if (this.state === STATE.LISTENING) {
                this.state = STATE.IDLE;
            }
        };
    }

    handleLanguageChange(event) {
        this.selectedLang = event.detail.value;
        if (this.recognition) {
            this.recognition.lang = this.selectedLang;
        }
    }

    handleStartListening() {
        this.log('[voiceFormFiller] handleStartListening - lang:',
            this.selectedLang, 'fieldConfig present:', !!this._fieldConfig);
        if (!this.recognition) {
            this.initRecognition();
            if (!this.recognition) return;
        }
        this.recognition.lang = this.selectedLang;
        this.transcript = '';
        this.errorMessage = '';
        this.state = STATE.LISTENING;
        try {
            this.recognition.start();
        } catch (e) {
            this.state = STATE.ERROR;
            this.errorMessage = `Could not start microphone: ${e.message}`;
        }
    }

    handleStopListening() {
        this.safeStop();
    }

    safeStop() {
        if (this.recognition) {
            try { this.recognition.stop(); } catch (e) { /* ignore */ }
        }
    }

    async handleConfirmTranscript() {
        this.log('[voiceFormFiller] handleConfirmTranscript - inputs:', {
            transcript: this.transcript,
            fieldConfigRaw: this._fieldConfig,
            fieldConfigType: typeof this._fieldConfig,
            fieldConfigAsString: this.fieldConfigAsString,
            language: this.selectedLang
        });
        if (!this.transcript) return;
        const fieldConfigValue = this.fieldConfigAsString;
        if (!fieldConfigValue) {
            this.logError('[voiceFormFiller] fieldConfig is missing or empty.',
                'Raw value was:', this._fieldConfig);
            this.state = STATE.ERROR;
            this.errorMessage =
                'Field configuration is missing. Configure the "fieldConfig" customAttribute.';
            return;
        }
        this.state = STATE.PROCESSING;
        this.errorMessage = '';
        try {
            const result = await extractFieldValues({
                transcript: this.transcript,
                fieldConfigJson: fieldConfigValue,
                language: this.selectedLang,
                promptDeveloperName: this.resolvedPromptDeveloperName
            });
            const parsed = typeof result === 'string' ? JSON.parse(result) : result;
            const cleaned = this.applyToOmniscript(parsed);
            this.lastFilled = cleaned;
            this.state = STATE.DONE;
        } catch (error) {
            this.state = STATE.ERROR;
            this.errorMessage =
                (error && error.body && error.body.message) ||
                (error && error.message) ||
                'Could not extract values from your response.';
        }
    }

    applyToOmniscript(values) {
        if (!values || typeof values !== 'object') return {};
        const cleaned = {};
        Object.keys(values).forEach((key) => {
            const v = values[key];
            if (v === null || v === undefined) return;
            if (typeof v === 'string' && v.trim() === '') return;
            cleaned[key] = v;
        });
        if (Object.keys(cleaned).length > 0) {
            this.omniApplyCallResp(cleaned);
        }
        return cleaned;
    }

    handleRetry() {
        this.transcript = '';
        this.errorMessage = '';
        this.lastFilled = null;
        this.state = STATE.IDLE;
    }

    log(...args) {
        if (this._debug) {
            // eslint-disable-next-line no-console
            console.log(...args);
        }
    }

    logError(...args) {
        if (this._debug) {
            // eslint-disable-next-line no-console
            console.error(...args);
        }
    }

    // ---------- getters ----------

    /**
     * Prompt Template developer name to invoke. Resolves in this order:
     *   1) @api promptDeveloperName customAttribute
     *   2) `promptDeveloperName` key anywhere in omniJsonData (Experience
     *      Cloud fallback, mirrors the fieldConfig resolution)
     *   3) null — Apex will fall back to its DEFAULT_PROMPT_DEVELOPER_NAME.
     */
    get resolvedPromptDeveloperName() {
        if (typeof this._promptDeveloperName === 'string'
            && this._promptDeveloperName.trim()) {
            return this._promptDeveloperName.trim();
        }
        if (this._omniJsonData) {
            const v = findKeyDeep(this._omniJsonData, 'promptDeveloperName');
            if (typeof v === 'string' && v.trim()) return v.trim();
        }
        return null;
    }

    get fieldConfigAsString() {
        // 1) @api fieldConfig — works in designer / App Page / orgs where
        //    customAttributes propagate.
        if (typeof this._fieldConfig === 'string' && this._fieldConfig.trim()) {
            return this._fieldConfig;
        }
        if (this._fieldConfig && typeof this._fieldConfig === 'object') {
            return JSON.stringify(this._fieldConfig);
        }
        // 2) omniJsonData fallback — Experience Cloud / Aura runtime where
        //    customAttributes can be dropped. Looks for any of these keys
        //    anywhere in the data JSON tree.
        if (this._omniJsonData) {
            const candidates = [
                'fieldConfig',
                'fieldConfigJson',
                'voiceFieldConfig',
                'fieldConfigSource'
            ];
            for (const key of candidates) {
                const v = findKeyDeep(this._omniJsonData, key);
                if (typeof v === 'string' && v.trim()) return v;
                if (v && typeof v === 'object') return JSON.stringify(v);
            }
        }
        return null;
    }

    get languageOptions() {
        return this._languages || DEFAULT_LANGUAGES;
    }

    get comboboxOptions() {
        return this.languageOptions.map((l) => ({ label: l.label, value: l.code }));
    }

    get hasMultipleLanguages() {
        return this.languageOptions.length > 1;
    }

    get isLanguagePickerDisabled() {
        return this.state === STATE.LISTENING || this.state === STATE.PROCESSING;
    }

    get showHint() {
        return !this.isBrowserSupported && this.unsupportedBehavior !== 'hide';
    }

    get isIdle()        { return this.state === STATE.IDLE; }
    get isListening()   { return this.state === STATE.LISTENING; }
    get isTranscribed() { return this.state === STATE.TRANSCRIBED; }
    get isProcessing()  { return this.state === STATE.PROCESSING; }
    get isDone()        { return this.state === STATE.DONE; }
    get isError()       { return this.state === STATE.ERROR; }

    get hasFilledSummary() {
        return this.lastFilled && Object.keys(this.lastFilled).length > 0;
    }

    get showFilledSummary() {
        return this.hasFilledSummary && this._debug;
    }

    get filledSummary() {
        if (!this.lastFilled) return '';
        return Object.entries(this.lastFilled)
            .map(([k, v]) => `${k}: ${v}`)
            .join(', ');
    }

    formatRecognitionError(code) {
        switch (code) {
            case 'no-speech': return 'No speech detected. Please try again.';
            case 'audio-capture': return 'No microphone was found.';
            case 'not-allowed':
            case 'service-not-allowed':
                return 'Microphone access was blocked. Please allow access in your browser settings.';
            case 'network': return 'Network error during speech recognition.';
            case 'aborted': return 'Recording was cancelled.';
            default: return `Recognition error: ${code || 'unknown'}`;
        }
    }
}

function parseLanguages(raw) {
    if (raw === null || raw === undefined) return null;
    if (Array.isArray(raw)) return normalizeLangArray(raw);
    if (typeof raw !== 'string') return null;
    const trimmed = raw.trim();
    if (!trimmed) return null;
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
        try {
            const parsed = JSON.parse(trimmed);
            if (Array.isArray(parsed)) return normalizeLangArray(parsed);
        } catch (e) { /* fall through */ }
    }
    const codes = trimmed.split(',').map((c) => c.trim()).filter((c) => c);
    if (codes.length > 0) {
        return codes.map((c) => ({ code: c, label: c }));
    }
    return null;
}

function normalizeLangArray(arr) {
    return arr
        .map((item) => {
            if (!item) return null;
            if (typeof item === 'string') return { code: item, label: item };
            if (item.code) return { code: item.code, label: item.label || item.code };
            return null;
        })
        .filter(Boolean);
}

/**
 * Recursively searches an object tree for the first occurrence of `key`.
 * Used to find values nested under OmniStudio step containers
 * (e.g. data.Step1.fieldConfig).
 */
function findKeyDeep(obj, key) {
    if (!obj || typeof obj !== 'object') return null;
    if (Object.prototype.hasOwnProperty.call(obj, key)) {
        return obj[key];
    }
    for (const k of Object.keys(obj)) {
        const v = obj[k];
        if (v && typeof v === 'object') {
            const found = findKeyDeep(v, key);
            if (found !== null && found !== undefined) return found;
        }
    }
    return null;
}

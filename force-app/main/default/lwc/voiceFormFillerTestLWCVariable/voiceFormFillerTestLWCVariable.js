import { LightningElement, api } from 'lwc';
import { OmniscriptBaseMixin } from 'omnistudio/omniscriptBaseMixin';

export default class VoiceFormFillerTestLWCVariable extends OmniscriptBaseMixin(LightningElement) {
    @api fieldConfig;
    @api languages;
    @api omniJsonData;

    get fieldConfigDisplay() {
        return stringify(this.fieldConfig);
    }

    get languagesDisplay() {
        return stringify(this.languages);
    }

}

function stringify(value) {
    if (value === null || value === undefined) return '(empty)';
    if (typeof value === 'string') return value;
    try {
        return JSON.stringify(value);
    } catch (e) {
        return String(value);
    }
}

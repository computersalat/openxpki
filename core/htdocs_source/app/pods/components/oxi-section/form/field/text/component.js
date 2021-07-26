import Component from '@glimmer/component';
import { tracked  } from '@glimmer/tracking';
import { action, set } from '@ember/object';
import { scheduleOnce } from '@ember/runloop';
import { getOwner } from '@ember/application';
import { isArray } from '@ember/array';
import { inject } from '@ember/service';

export default class OxiFieldTextComponent extends Component {
    @inject('intl') intl;

    /*
     * Note: the search input field is two-fold:
     * If a cert identifier is entered manually, it's value equals the
     * value that is submitted.
     * If an entry from the drop-down list is chosen, then it shows
     * the certificate subject but not the true form value to be submitted.
     */
    @tracked value = null;
    @tracked label = null;

    // autocomplete related:
    @tracked isDropdownOpen = false;
    @tracked searchResults = [];
    searchIndex = 0;
    searchPrevious = null;
    searchTimer = null;
    acStaticParams = new Map();   // mapping: parameter name => static value
    acFieldRefParams = new Map(); // mapping: parameter name => source field name

    constructor() {
        super(...arguments);

        let content = this.args.content;
        this.value = content.value;

        if (this.isAutoComplete) {
            if (content.autocomplete?.action === undefined) {
                throw new Error(`oxi-section/form/field/text: parameter "autocomplete.action" missing`);
            }
            let params;
            if (params = content.autocomplete?.params) {
                if (Object.prototype.toString.call(params) !== '[object Object]')
                    throw new Error(`oxi-section/form/field/text: parameter "autocomplete.params" must be a hash`);

                for (const [key, value] of Object.entries(params)) {
                    let func;
                    // if the value is a hash, it's a reference to another field
                    if (Object.prototype.toString.call(value) === '[object Object]') {
                        if (! value.field) throw new Error(`oxi-section/form/field/text: autocomplete parameter definition "${key}" does not contain "field" attribute`);
                        this.acFieldRefParams.set(key, value.field);
                    }
                    // otherwise it's a plain string
                    else {
                        this.acStaticParams.set(key, value);
                    }
                }
            }
        }
    }

    get isAutoComplete() {
        return this.args.content.autocomplete;
    }

    @action
    onInput(evt) {
        let value = this.cleanup(evt.target.value);
        this.setValue(value);
    }

    // Own "paste" implementation to allow for text cleanup
    @action
    onPaste(event) {
        let paste = (event.clipboardData || window.clipboardData).getData('text');
        let pasteCleaned = this.cleanup(paste, { trimTrailingStuff: true });
        let inputField = event.target;
        let oldVal = this.value || "";

        let newCursorPos = inputField.selectionStart + pasteCleaned.length;

        // put cursor into right position after Ember rendered all updates
        scheduleOnce('afterRender', this, () => {
            inputField.focus();
            inputField.setSelectionRange(newCursorPos, newCursorPos);
        });

        let value =
            oldVal.slice(0, inputField.selectionStart) +
            pasteCleaned +
            oldVal.slice(inputField.selectionEnd);

        this.setValue(value);
        event.preventDefault();
    }

    setValue(value) {
        this.value = value;
        this.args.onChange(value); // report changes to parent component

        // fetch autocomplete list (but don't process same input value twice)
        if (this.isAutoComplete && value !== this.searchPrevious) {
            this.autocompleteQuery(value);
        }
    }

    // Strips newlines + leading (and if chosen trailing) whitespaces and quotation marks
    cleanup(text, args = { trimTrailingStuff: false }) {
        let result = text.replace(/\r?\n/gm, '').replace(/^["'„\s]*/, '');
        if (args.trimTrailingStuff) {
            result = result.replace(/["'“\s]*$/, '');
        }
        return result;
    }


    /*
     **************************************************************************
     * Autocomplete related methods below...
     **************************************************************************
     */


    autocompleteQuery(value) {
        this.searchPrevious = value;

        this.searchResults = []; // make sure changed input (e.g. under 3 characters) will not show old result list again
        this.label = '';

        // cancel old search query timer on new input
        if (this.searchTimer) clearTimeout(this.searchTimer); // after check value === this.searchPrevious !

        // don't search short values
        if ((value||"").length < 3) { this.isDropdownOpen = false; return }

        // start search query after 300ms without input
        this.searchTimer = setTimeout(() => {
            let searchIndex = ++this.searchIndex;

            // resolve referenced fields and their values
            let enc = new Map(); this.acFieldRefParams.forEach((v, k) => { enc.set(v, k) }); // inverted map
            let ref = this.args.encodeFields(enc.keys(), enc); // returns an Object
            // static parameters
            let plain = Object.fromEntries(this.acStaticParams);

            getOwner(this).lookup("route:openxpki").sendAjaxQuiet({
                action: this.args.content.autocomplete.action,
                [this.args.content.name] : value, // [] denotes a dynamic key name
                ...ref,
                ...plain,
            }).then((doc) => {
                // only show results of most recent search (if parallel requests were sent)
                if (searchIndex !== this.searchIndex) { return }

                if (doc.error) {
                    this.args.onError(doc.error);
                    return;
                }

                this.searchResults = doc;
                if (doc[0] != null) {
                    doc[0].active = true;
                }
                this.isDropdownOpen = true;
            });
        }, 300);
    }

    @action
    onKeydown(evt) {
        if (this.isDropdownOpen == false) return;

        // Enter - select active value
        if (evt.keyCode === 13) {
            let results = this.searchResults;
            let a = results.findBy("active", true);
            if (a) {
                this.selectResult(a);
            }
            evt.stopPropagation(); evt.preventDefault();
        }
        // Escape
        else if (evt.keyCode === 27) {
            this.isDropdownOpen = false;
            evt.stopPropagation(); evt.preventDefault();
        }
        // Arrow up
        else if (evt.keyCode === 38) {
            this.selectNeighbor(-1);
            evt.stopPropagation(); evt.preventDefault();
        }
        // Arrow down
        else if (evt.keyCode === 40) {
            this.selectNeighbor(1);
            evt.stopPropagation(); evt.preventDefault();
        }
    }

    selectNeighbor(diff) {
        let results = this.searchResults;
        if (!results.length) { return }
        let a = results.findBy("active", true);
        set(a, "active", false);
        let index = (results.indexOf(a) + diff + results.length) % results.length;
        a = results[index];
        return set(a, "active", true);
    }

    @action
    onFocus() {
        if (this.isAutoComplete) {
            // If we also send other form field(s) then better refresh the
            // autocomplete results as the other field(s) might have changed.
            if (this.acFieldRefParams.size > 0) {
                // We don't use the current value (maybe chosen from the autocomplete
                // result list) but the same value as used for the previous query.
                this.autocompleteQuery(this.searchPrevious);
            }
            // Otherwise just show result list again
            else {
                if (this.searchResults.length) this.isDropdownOpen = true;
            }
        }
    }

    @action
    onBlur() {
        this.isDropdownOpen = false;
    }

    @action
    onMouseDown(evt) {
        if (evt.target.tagName === "INPUT") { return }
        // prevent focus loss on input field after autocomplete list entry was clicked
        evt.stopPropagation(); evt.preventDefault();
    }

    @action
    selectResult(res) {
        this.value = res.value;
        this.label = res.label;
        this.args.onChange(this.value);
        this.isDropdownOpen = false;
    }
}

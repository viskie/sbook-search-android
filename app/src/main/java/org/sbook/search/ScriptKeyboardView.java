package org.sbook.search;

import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.Typeface;
import android.view.Gravity;
import android.view.ViewGroup;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;

import java.util.LinkedHashMap;
import java.util.Map;

@SuppressLint("ViewConstructor")
final class ScriptKeyboardView extends LinearLayout {
    static final String[] SCRIPT_NAMES = {
            "ABC · System", "देवनागरी", "বাংলা", "ગુજરાતી", "ਗੁਰਮੁਖੀ",
            "ଓଡ଼ିଆ", "தமிழ்", "తెలుగు", "ಕನ್ನಡ", "മലയാളം"
    };

    private static final Map<String, String[][]> LAYOUTS = new LinkedHashMap<>();

    static {
        LAYOUTS.put("देवनागरी", new String[][]{
                {"अ", "आ", "इ", "ई", "उ", "ऊ", "ऋ", "ए", "ऐ", "ओ", "औ", "ं", "ः"},
                {"क", "ख", "ग", "घ", "ङ", "च", "छ", "ज", "झ", "ञ", "ट", "ठ", "ड", "ढ", "ण"},
                {"त", "थ", "द", "ध", "न", "प", "फ", "ब", "भ", "म", "य", "र", "ल", "व"},
                {"श", "ष", "स", "ह", "ा", "ि", "ी", "ु", "ू", "ृ", "े", "ै", "ो", "ौ", "्"}
        });
        LAYOUTS.put("বাংলা", new String[][]{
                {"অ", "আ", "ই", "ঈ", "উ", "ঊ", "ঋ", "এ", "ঐ", "ও", "ঔ", "ং", "ঃ"},
                {"ক", "খ", "গ", "ঘ", "ঙ", "চ", "ছ", "জ", "ঝ", "ঞ", "ট", "ঠ", "ড", "ঢ", "ণ"},
                {"ত", "থ", "দ", "ধ", "ন", "প", "ফ", "ব", "ভ", "ম", "য", "র", "ল", "শ", "ষ", "স", "হ"},
                {"া", "ি", "ী", "ু", "ূ", "ৃ", "ে", "ৈ", "ো", "ৌ", "্"}
        });
        LAYOUTS.put("ગુજરાતી", new String[][]{
                {"અ", "આ", "ઇ", "ઈ", "ઉ", "ઊ", "ઋ", "એ", "ઐ", "ઓ", "ઔ", "ં", "ઃ"},
                {"ક", "ખ", "ગ", "ઘ", "ઙ", "ચ", "છ", "જ", "ઝ", "ઞ", "ટ", "ઠ", "ડ", "ઢ", "ણ"},
                {"ત", "થ", "દ", "ધ", "ન", "પ", "ફ", "બ", "ભ", "મ", "ય", "ર", "લ", "વ", "શ", "ષ", "સ", "હ"},
                {"ા", "િ", "ી", "ુ", "ૂ", "ૃ", "ે", "ૈ", "ો", "ૌ", "્"}
        });
        LAYOUTS.put("ਗੁਰਮੁਖੀ", new String[][]{
                {"ੳ", "ਅ", "ੲ", "ਸ", "ਹ", "ਕ", "ਖ", "ਗ", "ਘ", "ਙ", "ਚ", "ਛ", "ਜ", "ਝ", "ਞ"},
                {"ਟ", "ਠ", "ਡ", "ਢ", "ਣ", "ਤ", "ਥ", "ਦ", "ਧ", "ਨ", "ਪ", "ਫ", "ਬ", "ਭ", "ਮ"},
                {"ਯ", "ਰ", "ਲ", "ਵ", "ੜ", "ਾ", "ਿ", "ੀ", "ੁ", "ੂ", "ੇ", "ੈ", "ੋ", "ੌ", "੍", "ਂ"}
        });
        LAYOUTS.put("ଓଡ଼ିଆ", new String[][]{
                {"ଅ", "ଆ", "ଇ", "ଈ", "ଉ", "ଊ", "ଋ", "ଏ", "ଐ", "ଓ", "ଔ", "ଂ", "ଃ"},
                {"କ", "ଖ", "ଗ", "ଘ", "ଙ", "ଚ", "ଛ", "ଜ", "ଝ", "ଞ", "ଟ", "ଠ", "ଡ", "ଢ", "ଣ"},
                {"ତ", "ଥ", "ଦ", "ଧ", "ନ", "ପ", "ଫ", "ବ", "ଭ", "ମ", "ଯ", "ର", "ଲ", "ଵ", "ଶ", "ଷ", "ସ", "ହ"},
                {"ା", "ି", "ୀ", "ୁ", "ୂ", "ୃ", "େ", "ୈ", "ୋ", "ୌ", "୍"}
        });
        LAYOUTS.put("தமிழ்", new String[][]{
                {"அ", "ஆ", "இ", "ஈ", "உ", "ஊ", "எ", "ஏ", "ஐ", "ஒ", "ஓ", "ஔ", "ஃ"},
                {"க", "ங", "ச", "ஞ", "ட", "ண", "த", "ந", "ப", "ம", "ய", "ர", "ல", "வ", "ழ", "ள", "ற", "ன"},
                {"ா", "ி", "ீ", "ு", "ூ", "ெ", "ே", "ை", "ொ", "ோ", "ௌ", "்"}
        });
        LAYOUTS.put("తెలుగు", new String[][]{
                {"అ", "ఆ", "ఇ", "ఈ", "ఉ", "ఊ", "ఋ", "ఎ", "ఏ", "ఐ", "ఒ", "ఓ", "ఔ", "ం", "ః"},
                {"క", "ఖ", "గ", "ఘ", "ఙ", "చ", "ఛ", "జ", "ఝ", "ఞ", "ట", "ఠ", "డ", "ఢ", "ణ"},
                {"త", "థ", "ద", "ధ", "న", "ప", "ఫ", "బ", "భ", "మ", "య", "ర", "ల", "వ", "శ", "ష", "స", "హ", "ళ"},
                {"ా", "ి", "ీ", "ు", "ూ", "ృ", "ె", "ే", "ై", "ొ", "ో", "ౌ", "్"}
        });
        LAYOUTS.put("ಕನ್ನಡ", new String[][]{
                {"ಅ", "ಆ", "ಇ", "ಈ", "ಉ", "ಊ", "ಋ", "ಎ", "ಏ", "ಐ", "ಒ", "ಓ", "ಔ", "ಂ", "ಃ"},
                {"ಕ", "ಖ", "ಗ", "ಘ", "ಙ", "ಚ", "ಛ", "ಜ", "ಝ", "ಞ", "ಟ", "ಠ", "ಡ", "ಢ", "ಣ"},
                {"ತ", "ಥ", "ದ", "ಧ", "ನ", "ಪ", "ಫ", "ಬ", "ಭ", "ಮ", "ಯ", "ರ", "ಲ", "ವ", "ಶ", "ಷ", "ಸ", "ಹ", "ಳ"},
                {"ಾ", "ಿ", "ೀ", "ು", "ೂ", "ೃ", "ೆ", "ೇ", "ೈ", "ೊ", "ೋ", "ೌ", "್"}
        });
        LAYOUTS.put("മലയാളം", new String[][]{
                {"അ", "ആ", "ഇ", "ഈ", "ഉ", "ഊ", "ഋ", "എ", "ഏ", "ഐ", "ഒ", "ഓ", "ഔ", "ം", "ഃ"},
                {"ക", "ഖ", "ഗ", "ഘ", "ങ", "ച", "ഛ", "ജ", "ഝ", "ഞ", "ട", "ഠ", "ഡ", "ഢ", "ണ"},
                {"ത", "ഥ", "ദ", "ധ", "ന", "പ", "ഫ", "ബ", "ഭ", "മ", "യ", "ര", "ല", "വ", "ശ", "ഷ", "സ", "ഹ", "ള", "ഴ", "റ"},
                {"ാ", "ി", "ീ", "ു", "ൂ", "ൃ", "െ", "േ", "ൈ", "ൊ", "ോ", "ൌ", "്"}
        });
    }

    private final EditText target;

    ScriptKeyboardView(Context context, EditText target) {
        super(context);
        this.target = target;
        setOrientation(VERTICAL);
        setPadding(0, Ui.dp(context, 6), 0, Ui.dp(context, 8));
        setBackgroundColor(Ui.CHARCOAL);
    }

    void useSystemKeyboard() {
        setVisibility(GONE);
        target.setShowSoftInputOnFocus(true);
        target.requestFocus();
        ((InputMethodManager) getContext().getSystemService(Context.INPUT_METHOD_SERVICE))
                .showSoftInput(target, InputMethodManager.SHOW_IMPLICIT);
    }

    void showScript(String script) {
        removeAllViews();
        String[][] rows = LAYOUTS.get(script);
        if (rows == null) {
            useSystemKeyboard();
            return;
        }
        target.setShowSoftInputOnFocus(false);
        ((InputMethodManager) getContext().getSystemService(Context.INPUT_METHOD_SERVICE))
                .hideSoftInputFromWindow(target.getWindowToken(), 0);
        for (String[] keys : rows) addKeyRow(keys);
        addKeyRow(new String[]{"SPACE", "⌫", "CLEAR"});
        setVisibility(VISIBLE);
        target.requestFocus();
    }

    private void addKeyRow(String[] keys) {
        HorizontalScrollView scroll = new HorizontalScrollView(getContext());
        scroll.setHorizontalScrollBarEnabled(false);
        LinearLayout row = new LinearLayout(getContext());
        row.setOrientation(HORIZONTAL);
        row.setGravity(Gravity.CENTER);
        row.setPadding(Ui.dp(getContext(), 6), Ui.dp(getContext(), 2), Ui.dp(getContext(), 6), Ui.dp(getContext(), 2));
        for (String key : keys) {
            Button button = new Button(getContext());
            button.setText(key.equals("SPACE") ? "स्पेस / space" : key);
            button.setTextColor(Ui.BLACK);
            button.setTextSize(key.length() > 2 ? 12 : 20);
            button.setTypeface(Typeface.DEFAULT_BOLD);
            button.setAllCaps(false);
            button.setMinWidth(key.length() > 2 ? Ui.dp(getContext(), 110) : Ui.dp(getContext(), 48));
            button.setMinimumHeight(Ui.dp(getContext(), 44));
            button.setBackground(Ui.background(Ui.ORANGE, 8, getContext()));
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, Ui.dp(getContext(), 48));
            params.setMargins(Ui.dp(getContext(), 3), 0, Ui.dp(getContext(), 3), 0);
            button.setLayoutParams(params);
            button.setOnClickListener(view -> press(key));
            row.addView(button);
        }
        scroll.addView(row);
        addView(scroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
    }

    private void press(String key) {
        int start = Math.max(0, target.getSelectionStart());
        int end = Math.max(0, target.getSelectionEnd());
        if (key.equals("CLEAR")) {
            target.setText("");
            return;
        }
        if (key.equals("⌫")) {
            if (start != end) {
                target.getText().delete(Math.min(start, end), Math.max(start, end));
            } else if (start > 0) {
                int previous = Character.offsetByCodePoints(target.getText(), start, -1);
                target.getText().delete(previous, start);
            }
            return;
        }
        String value = key.equals("SPACE") ? " " : key;
        target.getText().replace(Math.min(start, end), Math.max(start, end), value);
    }
}

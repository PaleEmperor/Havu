package studio.havu.android;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.os.Build;
import android.text.InputType;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.FrameLayout;

import java.lang.ref.WeakReference;
import java.nio.charset.StandardCharsets;

/** One native text edit session. The Godot thread reads the outcome after dismissal. */
public final class HavuKeyboard {
    private static final String TAG = "HavuKeyboard";
    private static final byte[] UNAVAILABLE = { 0 };
    private static final byte[] CANCELED = { 1 };
    private static final byte ACCEPTED = 2;
    private final WeakReference<Activity> host;
    private volatile byte[] outcome = new byte[0];

    private HavuKeyboard(Activity activity) {
        host = new WeakReference<>(activity);
    }

    public static HavuKeyboard open(Activity activity, byte[] title, byte[] initial, int keyboardType,
                                    boolean signed, int maxLength, int minimum, int maximum) {
        HavuKeyboard session = new HavuKeyboard(activity);
        activity.runOnUiThread(() -> {
            if (activity.isFinishing() || activity.isDestroyed()) {
                session.outcome = UNAVAILABLE;
                return;
            }
            try {
                session.show(activity, new String(title, StandardCharsets.UTF_8),
                        new String(initial, StandardCharsets.UTF_8), keyboardType, signed,
                        maxLength, minimum, maximum);
            } catch (RuntimeException exception) {
                Log.w(TAG, "Could not open the native editor", exception);
                session.outcome = UNAVAILABLE;
            }
        });
        return session;
    }

    public byte[] result() {
        Activity activity = host.get();
        byte[] value = outcome;
        return value.length == 0 && (activity == null || activity.isDestroyed()) ? UNAVAILABLE : value;
    }

    private void show(Activity activity, String title, String initial, int keyboardType, boolean signed,
                      int maxLength, int minimum, int maximum) {
        boolean multiline = keyboardType == 1;
        AlertDialog.Builder builder = new AlertDialog.Builder(activity);
        Context context = builder.getContext();
        KeyboardEditor editor = new KeyboardEditor(context);
        editor.setSingleLine(!multiline);
        editor.setInputType(inputType(keyboardType, signed));
        if (multiline) {
            editor.setMinLines(3);
            editor.setMaxLines(8);
            editor.setGravity(Gravity.TOP | Gravity.START);
        } else {
            editor.setImeOptions(EditorInfo.IME_ACTION_DONE);
            editor.setSelectAllOnFocus(true);
        }
        editor.setText(initial);

        FrameLayout content = new FrameLayout(context);
        int margin = Math.round(20 * context.getResources().getDisplayMetrics().density);
        content.setPadding(margin, margin / 2, margin, 0);
        content.addView(editor, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT));
        AlertDialog dialog = builder.setTitle(title).setView(content)
                .setPositiveButton("Apply", null).setNegativeButton("Cancel", null)
                .setNeutralButton("Havu keyboard", null).create();
        Window window = dialog.getWindow();
        window.clearFlags(WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM);
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE
                | WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);

        byte[][] result = { CANCELED };
        Runnable submit = () -> {
            String text = editor.getText().toString();
            String error = validationError(text, maxLength, minimum, maximum);
            if (error != null) {
                editor.setError(error);
                return;
            }
            if (minimum <= maximum) text = Integer.toString(Integer.parseInt(text.trim()));
            byte[] encoded = text.getBytes(StandardCharsets.UTF_8);
            byte[] accepted = new byte[encoded.length + 1];
            System.arraycopy(encoded, 0, accepted, 1, encoded.length);
            accepted[0] = ACCEPTED;
            result[0] = accepted;
            dialog.dismiss();
        };
        dialog.setOnDismissListener(ignored -> outcome = result[0]);
        editor.requestFocus();
        dialog.show();
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(ignored -> submit.run());
        dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(ignored -> {
            result[0] = UNAVAILABLE;
            dialog.dismiss();
        });
        if (multiline) {
            editor.setSelection(editor.length());
        } else {
            editor.selectAll();
            editor.setOnEditorActionListener((view, action, event) -> {
                if (action != EditorInfo.IME_ACTION_DONE) return false;
                submit.run();
                return true;
            });
        }
    }

    // Values from Godot's DisplayServer.VirtualKeyboardType.
    private static int inputType(int type, boolean signed) {
        switch (type) {
            case 1:
                return InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE
                        | InputType.TYPE_TEXT_FLAG_CAP_SENTENCES;
            case 2:
            case 3:
                return InputType.TYPE_CLASS_NUMBER
                        | (type == 3 ? InputType.TYPE_NUMBER_FLAG_DECIMAL : 0)
                        | (signed ? InputType.TYPE_NUMBER_FLAG_SIGNED : 0);
            case 4:
                return InputType.TYPE_CLASS_PHONE;
            case 5:
                return InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS;
            case 6:
                return InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD;
            case 7:
                return InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI;
            default:
                return InputType.TYPE_CLASS_TEXT;
        }
    }

    static String validationError(String text, int maxLength, int minimum, int maximum) {
        if (minimum <= maximum) {
            try {
                int value = Integer.parseInt(text.trim());
                if (value < minimum || value > maximum) throw new NumberFormatException();
            } catch (NumberFormatException error) {
                return "Enter a number from " + minimum + " to " + maximum + ".";
            }
        }
        if (maxLength > 0 && text.codePointCount(0, text.length()) > maxLength) {
            return "Use " + maxLength + " characters or fewer.";
        }
        return null;
    }

    private static final class KeyboardEditor extends EditText {
        private boolean requestedOnFocus;

        KeyboardEditor(Context context) {
            super(context);
            setShowSoftInputOnFocus(false);
            if (Build.VERSION.SDK_INT >= 34) setAutoHandwritingEnabled(false);
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            boolean handled = super.onTouchEvent(event);
            if (handled && event.getActionMasked() == MotionEvent.ACTION_UP
                    && event.getToolType(event.getActionIndex()) == MotionEvent.TOOL_TYPE_FINGER) {
                post(this::showKeyboard);
            }
            return handled;
        }

        @Override
        public void onWindowFocusChanged(boolean hasWindowFocus) {
            super.onWindowFocusChanged(hasWindowFocus);
            if (hasWindowFocus && !requestedOnFocus) post(() -> {
                if (hasWindowFocus() && requestFocus()) {
                    requestedOnFocus = true;
                    showKeyboard();
                }
            });
        }

        void showKeyboard() {
            if (!isAttachedToWindow() || !hasWindowFocus() || !isFocused()) return;
            InputMethodManager manager = getContext().getSystemService(InputMethodManager.class);
            if (Build.VERSION.SDK_INT >= 30) {
                WindowInsetsController controller = getWindowInsetsController();
                if (controller != null) controller.show(WindowInsets.Type.ime());
            }
            // Some devices still need a request targeting the focused editor.
            if (manager != null) manager.showSoftInput(this, 0);
            Log.i(TAG, "Requested keyboard for focused editor");
        }
    }
}

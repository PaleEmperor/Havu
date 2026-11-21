package studio.havu.android;

import android.app.Activity;
import android.os.Build;
import android.os.SystemClock;
import android.util.Log;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.Window;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

/** Reads the hardware button before Godot converts stylus events into mouse events. */
public final class HavuStylus implements InvocationHandler {
    private static volatile boolean enabled;
    private static volatile boolean detecting;
    private static final AtomicInteger detected = new AtomicInteger();
    private static final AtomicLong shortcutDown = new AtomicLong(-1);
    private final Window.Callback delegate;
    private int heldStylusKeys;

    private HavuStylus(Window.Callback delegate) {
        this.delegate = delegate;
    }

    public static void configure(Activity activity, boolean active) {
        shortcutDown.set(-1);
        enabled = active;
        activity.runOnUiThread(() -> {
            Window window = activity.getWindow();
            Window.Callback original = window.getCallback();
            if (original == null || activity.isDestroyed()) return;
            if (Proxy.isProxyClass(original.getClass())
                    && Proxy.getInvocationHandler(original) instanceof HavuStylus) return;
            try {
                Window.Callback callback = (Window.Callback) Proxy.newProxyInstance(
                        HavuStylus.class.getClassLoader(), new Class<?>[] { Window.Callback.class },
                        new HavuStylus(original));
                window.setCallback(callback);
            } catch (RuntimeException exception) {
                Log.w("HavuStylus", "Could not watch stylus buttons", exception);
            }
        });
    }

    public static boolean isSamsungDevice() {
        return "samsung".equalsIgnoreCase(Build.MANUFACTURER);
    }

    public static int takeShortcutContact() {
        long contact = shortcutDown.getAndSet(-1);
        return enabled && contact >= 0 && SystemClock.uptimeMillis() - (contact >> 2) <= 750
                ? (int) (contact & 3) : 0;
    }

    public static void setDetection(boolean active) {
        detected.set(0);
        detecting = active;
    }

    public static int takeDetectedButton() {
        return detected.getAndSet(0);
    }

    private static boolean isStylus(int toolType) {
        return toolType == MotionEvent.TOOL_TYPE_STYLUS || toolType == MotionEvent.TOOL_TYPE_ERASER;
    }

    static int buttonCode(int toolType, int buttons) {
        if (!isStylus(toolType)) return 0;
        if ((buttons & MotionEvent.BUTTON_STYLUS_PRIMARY) != 0) return 1;
        if ((buttons & MotionEvent.BUTTON_STYLUS_SECONDARY) != 0) return 2;
        return (buttons & MotionEvent.BUTTON_SECONDARY) != 0 ? 1 : 0;
    }

    private static void detect(MotionEvent event) {
        if (!detecting || event.getPointerCount() == 0) return;
        int action = event.getActionMasked();
        if (action == MotionEvent.ACTION_BUTTON_RELEASE || action == MotionEvent.ACTION_UP
                || action == MotionEvent.ACTION_CANCEL || action == MotionEvent.ACTION_HOVER_EXIT) return;
        int buttons = action == MotionEvent.ACTION_BUTTON_PRESS ? event.getActionButton() : event.getButtonState();
        int code = buttonCode(event.getToolType(0), buttons);
        if (code != 0) detected.compareAndSet(0, code);
    }

    @Override
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        switch (method.getName()) {
            case "dispatchTouchEvent":
                return dispatchTouch((MotionEvent) args[0]);
            case "dispatchGenericMotionEvent":
                return dispatchMotion((MotionEvent) args[0]);
            case "dispatchKeyEvent":
                return dispatchKey((KeyEvent) args[0]);
            case "onWindowFocusChanged":
                if (!(Boolean) args[0]) {
                    heldStylusKeys = 0;
                    shortcutDown.set(-1);
                }
                delegate.onWindowFocusChanged((Boolean) args[0]);
                return null;
            default:
                try {
                    return method.invoke(delegate, args);
                } catch (InvocationTargetException exception) {
                    throw exception.getCause();
                }
        }
    }

    private boolean dispatchMotion(MotionEvent event) {
        detect(event);
        int action = event.getActionMasked();
        // Leave hover and contact in the normal input stream. Only consume
        // standalone button events delivered to Havu's window.
        if ((action == MotionEvent.ACTION_BUTTON_PRESS || action == MotionEvent.ACTION_BUTTON_RELEASE)
                && event.getPointerCount() > 0
                && buttonCode(event.getToolType(0), event.getActionButton()) != 0) return true;
        return delegate.dispatchGenericMotionEvent(event);
    }

    private boolean dispatchKey(KeyEvent event) {
        int button;
        switch (event.getKeyCode()) {
            case KeyEvent.KEYCODE_STYLUS_BUTTON_PRIMARY: button = 1; break;
            case KeyEvent.KEYCODE_STYLUS_BUTTON_SECONDARY: button = 2; break;
            case KeyEvent.KEYCODE_STYLUS_BUTTON_TERTIARY:
            case KeyEvent.KEYCODE_STYLUS_BUTTON_TAIL: return true;
            default: return delegate.dispatchKeyEvent(event);
        }
        int mask = 1 << button;
        if (event.getAction() == KeyEvent.ACTION_DOWN && !event.isCanceled()) {
            heldStylusKeys |= mask;
            if (detecting && event.getRepeatCount() == 0) detected.compareAndSet(0, button);
        } else {
            heldStylusKeys &= ~mask;
        }
        return true;
    }

    private boolean dispatchTouch(MotionEvent event) {
        detect(event);
        if (!enabled || detecting || event.getActionMasked() != MotionEvent.ACTION_DOWN || event.getPointerCount() != 1) {
            return delegate.dispatchTouchEvent(event);
        }
        int toolType = event.getToolType(0);
        int button = buttonCode(toolType, event.getButtonState());
        if (button == 0 && heldStylusKeys != 0 && isStylus(toolType)) {
            button = Integer.numberOfTrailingZeros(heldStylusKeys);
        }
        shortcutDown.set(button == 0 ? -1 : (SystemClock.uptimeMillis() << 2) | button);
        if (button == 0) return delegate.dispatchTouchEvent(event);

        // Keep pressure, position and device identity. Godot's mouse path
        // needs a primary-button down even when Android reports only a side button.
        MotionEvent.PointerProperties properties = new MotionEvent.PointerProperties();
        MotionEvent.PointerCoords coordinates = new MotionEvent.PointerCoords();
        event.getPointerProperties(0, properties);
        event.getPointerCoords(0, coordinates);
        MotionEvent primary = MotionEvent.obtain(event.getDownTime(), event.getEventTime(),
                event.getAction(), 1, new MotionEvent.PointerProperties[] { properties },
                new MotionEvent.PointerCoords[] { coordinates }, event.getMetaState(),
                MotionEvent.BUTTON_PRIMARY, event.getXPrecision(), event.getYPrecision(),
                event.getDeviceId(), event.getEdgeFlags(), event.getSource(), event.getFlags());
        try {
            return delegate.dispatchTouchEvent(primary);
        } finally {
            primary.recycle();
        }
    }
}

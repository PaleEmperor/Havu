package studio.havu.android;

import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.provider.DocumentsContract.Document;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.util.Locale;

/** Lists documents using the user's existing Storage Access Framework folder grant. */
public final class HavuProjectFolder {
    private HavuProjectFolder() {}

    public static boolean persist(Context context, String folder) {
        ContentResolver resolver = context.getContentResolver();
        Uri tree = Uri.parse(folder);
        try {
            resolver.takePersistableUriPermission(tree,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            return true;
        } catch (SecurityException ignored) {
            try {
                resolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION);
                return true;
            } catch (SecurityException denied) {
                return false;
            }
        }
    }

    public static byte[] scan(Context context, String folder) {
        try {
            ContentResolver resolver = context.getContentResolver();
            Uri tree = Uri.parse(folder);
            String treeId = DocumentsContract.getTreeDocumentId(tree);
            Uri directory = DocumentsContract.buildDocumentUriUsingTree(tree, treeId);
            String title = "";
            try (Cursor cursor = resolver.query(directory, new String[]{Document.COLUMN_DISPLAY_NAME},
                    null, null, null)) {
                if (cursor == null || !cursor.moveToFirst()) return new byte[0];
                title = cursor.getString(0);
            }

            Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, treeId);
            String[] fields = {Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE};
            JSONArray entries = new JSONArray();
            try (Cursor cursor = resolver.query(children, fields, null, null, null)) {
                if (cursor == null) return new byte[0];
                while (cursor.moveToNext()) {
                    String name = cursor.getString(1);
                    if (Document.MIME_TYPE_DIR.equals(cursor.getString(2)) || name == null
                            || !name.toLowerCase(Locale.ROOT).endsWith(".havu")) continue;
                    Uri file = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0));
                    entries.put(new JSONObject().put("name", name).put("path", file.toString()));
                }
            }
            return new JSONObject().put("title", title == null ? "" : title).put("entries", entries)
                    .toString().getBytes(StandardCharsets.UTF_8);
        } catch (RuntimeException | JSONException unavailable) {
            return new byte[0];
        }
    }
}

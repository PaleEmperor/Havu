package studio.havu.android;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;

/** Rasterizes the ordered, already-clipped paint footprints for one RGBA8 tile. */
public final strictfp class HavuPaintRaster {
    private static final int MAX_VERTICES = 64;

    private static final ExecutorService workers = Executors.newFixedThreadPool(4, job -> {
        Thread thread = new Thread(job, "Havu paint tile");
        thread.setDaemon(true);
        return thread;
    });

    private HavuPaintRaster() {}

    private static final AtomicLong nextSession = new AtomicLong();
    private static final ConcurrentHashMap<Long, Stroke> sessions = new ConcurrentHashMap<>();

    private static final class Tile {
        final int x, y, width, height;
        final byte[] pixels;
        Future<?> last;

        Tile(int x, int y, int width, int height) {
            this.x = x;
            this.y = y;
            this.width = width;
            this.height = height;
            pixels = new byte[width * height * 4];
        }
    }

    private static final class Stroke {
        final LinkedHashMap<Long, Tile> tiles = new LinkedHashMap<>();
        final AtomicInteger pending = new AtomicInteger();
        volatile boolean canceled;
    }

    public static long begin() {
        long id = nextSession.incrementAndGet();
        sessions.put(id, new Stroke());
        return id;
    }

    public static boolean submit(long id, byte[] footprints, byte[] updates) {
        Stroke stroke = sessions.get(id);
        if (stroke == null || stroke.canceled) return false;
        ByteBuffer in = ByteBuffer.wrap(updates).order(ByteOrder.LITTLE_ENDIAN);
        while (in.remaining() >= 20) {
            if (stroke.pending.get() >= 192) return false;
            int x = in.getInt();
            int y = in.getInt();
            int w = in.getInt();
            int h = in.getInt();
            int length = in.getInt();
            if (w < 1 || w > 128 || h < 1 || h > 128 || (length != 0 && length != w * h * 4)
                || in.remaining() < length) return false;
            long key = (((long) x) << 32) | (y & 0xffffffffL);
            Tile tile = stroke.tiles.get(key);
            if (tile == null) {
                if (length == 0 || stroke.tiles.size() >= 160) return false;
                tile = new Tile(x, y, w, h);
                in.get(tile.pixels);
                stroke.tiles.put(key, tile);
            } else if (length > 0) {
                return false;
            }
            final Tile target = tile;
            final Future<?> previous = target.last;
            stroke.pending.incrementAndGet();
            target.last = workers.submit(() -> {
                try {
                    if (previous != null) previous.get();
                    if (!stroke.canceled && paint(target.pixels, footprints, x, y, w, h).length == 0) {
                        throw new IllegalArgumentException("Invalid raster footprint");
                    }
                    return null;
                } finally {
                    stroke.pending.decrementAndGet();
                }
            });
        }
        return !in.hasRemaining();
    }

    public static byte[] finish(long id) {
        Stroke stroke = sessions.remove(id);
        if (stroke == null || stroke.canceled) return new byte[0];
        int length = 0;
        for (Tile tile : stroke.tiles.values()) length += 16 + tile.pixels.length;
        ByteBuffer output = ByteBuffer.allocate(length).order(ByteOrder.LITTLE_ENDIAN);
        try {
            for (Tile tile : stroke.tiles.values()) {
                if (tile.last != null) tile.last.get();
                output.putInt(tile.x).putInt(tile.y).putInt(tile.width).putInt(tile.height).put(tile.pixels);
            }
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            stroke.canceled = true;
            return new byte[0];
        } catch (java.util.concurrent.ExecutionException error) {
            stroke.canceled = true;
            return new byte[0];
        }
        return output.array();
    }

    public static void discard(long id) {
        Stroke stroke = sessions.remove(id);
        if (stroke != null) stroke.canceled = true;
    }

    public static byte[] paint(byte[] rgba, byte[] footprints, int left, int top, int width, int height) {
        if (width < 1 || width > 128 || height < 1 || height > 128 || rgba.length != width * height * 4) {
            return new byte[0];
        }
        ByteBuffer input = ByteBuffer.wrap(footprints).order(ByteOrder.LITTLE_ENDIAN);
        double[] x = new double[MAX_VERTICES];
        double[] y = new double[MAX_VERTICES];
        int[] counts = new int[height];
        double[][] crossings = new double[height][MAX_VERTICES];
        while (input.hasRemaining()) {
            if (input.remaining() < 24) return new byte[0];
            float minX = input.getFloat();
            float minY = input.getFloat();
            float maxX = input.getFloat();
            float maxY = input.getFloat();
            int ink = input.getInt();
            int count = input.getInt();
            if (count < 3 || count > MAX_VERTICES || input.remaining() < count * 8) return new byte[0];
            int firstRow = Math.max(top, (int) Math.floor(minY));
            int lastRow = Math.min(top + height, (int) Math.ceil(maxY));
            if (firstRow >= lastRow || maxX <= left || minX >= left + width || (ink >>> 24) == 0) {
                input.position(input.position() + count * 8);
                continue;
            }
            for (int vertex = 0; vertex < count; vertex++) {
                x[vertex] = input.getFloat();
                y[vertex] = input.getFloat();
            }
            Arrays.fill(counts, firstRow - top, lastRow - top, 0);
            int previous = count - 1;
            for (int vertex = 0; vertex < count; vertex++) {
                double y0 = y[previous];
                double y1 = y[vertex];
                int from = Math.max(firstRow, (int) Math.ceil(Math.min(y0, y1) - 0.5));
                int to = Math.min(lastRow, (int) Math.ceil(Math.max(y0, y1) - 0.5));
                double x0 = x[previous];
                double xDelta = x[vertex] - x0;
                for (int row = from; row < to; row++) {
                    int local = row - top;
                    crossings[local][counts[local]++] = x0 + xDelta * ((row + 0.5 - y0) / (y1 - y0));
                }
                previous = vertex;
            }
            for (int row = firstRow - top; row < lastRow - top; row++) {
                int spans = counts[row];
                if (spans == 2 && crossings[row][0] > crossings[row][1]) {
                    double swap = crossings[row][0];
                    crossings[row][0] = crossings[row][1];
                    crossings[row][1] = swap;
                } else if (spans > 2) {
                    Arrays.sort(crossings[row], 0, spans);
                }
                for (int span = 0; span + 1 < spans; span += 2) {
                    int first = Math.max(0, (int) Math.ceil(crossings[row][span] - 0.5) - left);
                    int last = Math.min(width, (int) Math.ceil(crossings[row][span + 1] - 0.5) - left);
                    blendSpan(rgba, row * width + first, row * width + last, ink);
                }
            }
        }
        return rgba;
    }

    private static void blendSpan(byte[] rgba, int first, int last, int source) {
        int alpha = source >>> 24;
        int red = source & 255;
        int green = (source >>> 8) & 255;
        int blue = (source >>> 16) & 255;
        float sourceAlpha = alpha / 255f;
        float inverse = 1f - sourceAlpha;
        float srcRed = (red / 255f) * sourceAlpha;
        float srcGreen = (green / 255f) * sourceAlpha;
        float srcBlue = (blue / 255f) * sourceAlpha;
        for (int offset = first * 4; offset < last * 4; offset += 4) {
            if (alpha == 255) {
                rgba[offset] = (byte) red;
                rgba[offset + 1] = (byte) green;
                rgba[offset + 2] = (byte) blue;
                rgba[offset + 3] = (byte) alpha;
                continue;
            }
            float dstAlpha = (rgba[offset + 3] & 255) / 255f;
            float coverage = dstAlpha * inverse + sourceAlpha;
            rgba[offset] = channel(rgba[offset], dstAlpha, inverse, srcRed, coverage);
            rgba[offset + 1] = channel(rgba[offset + 1], dstAlpha, inverse, srcGreen, coverage);
            rgba[offset + 2] = channel(rgba[offset + 2], dstAlpha, inverse, srcBlue, coverage);
            rgba[offset + 3] = quantize(coverage);
        }
    }

    private static byte channel(byte value, float alpha, float inverse, float source, float coverage) {
        return quantize((((value & 255) / 255f) * alpha * inverse + source) / coverage);
    }

    private static byte quantize(float value) {
        return (byte) Math.min(255, (int) (value * 255f));
    }
}

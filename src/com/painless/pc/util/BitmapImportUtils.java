package com.painless.pc.util;

import java.io.File;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

/** Bounded bitmap decoding for user-selected import files and archive entries. */
public final class BitmapImportUtils {

	private static final int MAX_DIMENSION = 2048;
	private static final long MAX_PIXELS = 4L * 1024L * 1024L;

	private BitmapImportUtils() {
	}

	public static Bitmap decode(File file) {
		if (file == null || !file.isFile()) {
			return null;
		}

		BitmapFactory.Options bounds = new BitmapFactory.Options();
		bounds.inJustDecodeBounds = true;
		BitmapFactory.decodeFile(file.getAbsolutePath(), bounds);
		if (!isSupported(bounds)) {
			return null;
		}
		return BitmapFactory.decodeFile(file.getAbsolutePath());
	}

	public static Bitmap decode(byte[] data) {
		if (data == null || data.length == 0) {
			return null;
		}

		BitmapFactory.Options bounds = new BitmapFactory.Options();
		bounds.inJustDecodeBounds = true;
		BitmapFactory.decodeByteArray(data, 0, data.length, bounds);
		if (!isSupported(bounds)) {
			return null;
		}
		return BitmapFactory.decodeByteArray(data, 0, data.length);
	}

	private static boolean isSupported(BitmapFactory.Options bounds) {
		return bounds.outWidth > 0 && bounds.outHeight > 0
				&& bounds.outWidth <= MAX_DIMENSION && bounds.outHeight <= MAX_DIMENSION
				&& ((long) bounds.outWidth * (long) bounds.outHeight) <= MAX_PIXELS;
	}
}

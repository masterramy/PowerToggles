package com.painless.pc.picker.theme;

import java.io.File;

import org.json.JSONObject;

import android.graphics.Bitmap;

/**
 * A theme entry.
 */
public class ThemeEntry {

  // Title if its a section title
  public int title = 0;

  // Set to true if loading this theme failed
  public boolean failed = false;

  // Theme file for user-imported or legacy-local themes
  public File themeFile;

  public JSONObject config;
  public Bitmap background;
  public int backgroundRes = 0;

  // Values used for rendering
  public int[] padding;
  public float[] stretch;
  public boolean hideDividers;
  public int dividerColor;

  public final int[] buttonColors = new int[3];
  public final int[] buttonAlphas = new int[3];

  public final boolean isLoaded() {
    return background != null || backgroundRes != 0;
  }
}

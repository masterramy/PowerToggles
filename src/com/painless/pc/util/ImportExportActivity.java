package com.painless.pc.util;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;

import android.content.Intent;
import android.graphics.drawable.Drawable;
import android.net.Uri;
import android.os.Build;
import android.view.Menu;
import android.view.MenuItem;
import android.widget.Toast;

import com.painless.pc.R;
import com.painless.pc.picker.FilePicker;
import com.painless.pc.singleton.Debug;

/**
 * An abstract activity with utilities functions to start new activities and direct the result accordingly.
 * This activity also abstract outs some out the import/export functionality.
 *
 * @param <T> Import settings type
 */
public abstract class ImportExportActivity<T> extends CallerActivity {

	private static final long MAX_DOCUMENT_IMPORT_BYTES = 16L * 1024L * 1024L;

	private final int menuId;

	private final String fileExtension;
	private final int exportMsgTitle;
	private final int exportMsgArray;

	private final int importMsgTitle;
	private final int importMsgArray;

	public ImportExportActivity(int menuId, String fileExtension, int exportMsgTitle, int exportMsgArray,
			int importMsgTitle, int importMsgArray) {
		this.menuId = menuId;
		this.fileExtension = fileExtension;
		this.exportMsgTitle = exportMsgTitle;
		this.exportMsgArray = exportMsgArray;
		this.importMsgTitle = importMsgTitle;
		this.importMsgArray = importMsgArray;
	}

	// ************************ Options menu ************************
	@Override
	public boolean onCreateOptionsMenu(Menu menu) {
		getMenuInflater().inflate(menuId, menu);
		for (int i=menu.size()-1; i >=0; i--) {
			MenuItem item = menu.getItem(i);
			Drawable d = item.getIcon();
			if (d != null) {
				d = d.getConstantState().newDrawable(getResources());
				d.setAlpha(204);
				item.setIcon(d);
			}
		}
		return true;
	}

	@Override
	public boolean onOptionsItemSelected(MenuItem item) {
		if (item.getItemId() == R.id.cfg_export) {
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
				Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT)
						.addCategory(Intent.CATEGORY_OPENABLE)
						.setType(getDocumentMimeType())
						.putExtra(Intent.EXTRA_TITLE, "power-toggles-backup" + fileExtension);
				requestResult(10, intent, new CallerActivity.ResultReceiver() {
					@Override
					public void onResult(int requestCode, Intent data) {
						if (data != null && data.getData() != null) {
							startExportingInternal(data.getData());
						}
					}
				});
			} else {
				Intent intent = new Intent(this, FilePicker.class)
						.putExtra("savemode", true)
						.putExtra("title", getText(exportMsgTitle))
						.putExtra("filter", fileExtension);
				requestResult(10, intent, new CallerActivity.ResultReceiver() {
					@Override
					public void onResult(int requestCode, Intent data) {
						if (data != null) {
							startExportingInternal(data.getStringExtra("file"));
						}
					}
				});
			}
		} else if (item.getItemId() == R.id.cfg_import) {
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
				Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT)
						.addCategory(Intent.CATEGORY_OPENABLE)
						.setType(getDocumentMimeType());
				requestResult(10, intent, new CallerActivity.ResultReceiver() {
					@Override
					public void onResult(int requestCode, Intent data) {
						if (data != null && data.getData() != null) {
							startImportInternal(data.getData());
						}
					}
				});
			} else {
				Intent intent = new Intent(this, FilePicker.class)
						.putExtra("savemode", false)
						.putExtra("title", getText(importMsgTitle))
						.putExtra("filter", fileExtension);
				requestResult(10, intent, new CallerActivity.ResultReceiver() {
					@Override
					public void onResult(int requestCode, Intent data) {
						if (data != null) {
							startImportInternal(data.getStringExtra("file"));
						}
					}
				});
			}
		}
		return true;
	}

	private String getDocumentMimeType() {
		return ".zip".equalsIgnoreCase(fileExtension) ? "application/zip" : "application/octet-stream";
	}

	@Thunk void startExportingInternal(final Uri destination) {
		final String[] exportArray = getResources().getStringArray(exportMsgArray);

		new ProgressTask<Void, Uri>(this, exportArray[0]) {
			@Override
			protected Uri doInBackground(Void... params) {
				OutputStream out = null;
				try {
					out = getContentResolver().openOutputStream(destination, "w");
					if (out == null) {
						return null;
					}
					doExport(out);
					return destination;
				} catch (Exception e) {
					Debug.log(e);
					return null;
				} finally {
					if (out != null) {
						try { out.close(); } catch (Exception e) { Debug.log(e); }
					}
				}
			}

			@Override
			public void onDone(Uri result) {
				String msg = (result == null) ? exportArray[2] : String.format(exportArray[1], result.toString());
				Toast.makeText(ImportExportActivity.this, msg, Toast.LENGTH_LONG).show();
			}
		}.execute();
	}

	@Thunk void startExportingInternal(final String filePath) {
		final String[] exportArray = getResources().getStringArray(exportMsgArray);

		new ProgressTask<String, File>(this, exportArray[0]) {

			@Override
			protected File doInBackground(String... params) {
				try {
					if (filePath == null) {
						return null;
					}
					File exportFile = new File(filePath);
					doExport(new FileOutputStream(exportFile));
					return exportFile;
				} catch (Exception e) {
					Debug.log(e);
					return null;
				}
			}

			@Override
			public void onDone(File result) {
				String msg = (result == null) ? exportArray[2] :
					String.format(exportArray[1], result.getAbsolutePath());
				Toast.makeText(ImportExportActivity.this, msg, Toast.LENGTH_LONG).show();

				if (result != null) {
					try {
						Intent intent = new Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE);
						intent.setData(Uri.fromFile(result));
						sendBroadcast(intent);
					} catch (Exception e) {
						Debug.log(e);
					}
				}
			}
		}.execute();
	}

	public abstract void doExport(OutputStream out) throws Exception;

	// ************************ Import ************************
	@Thunk void startImportInternal(final Uri source) {
		final String[] importArray = getResources().getStringArray(importMsgArray);
		new ProgressTask<Void, T>(this, importArray[0]) {
			@Override
			protected T doInBackground(Void... params) {
				File temp = null;
				InputStream in = null;
				FileOutputStream out = null;
				try {
					temp = File.createTempFile("power_toggles_import_", fileExtension, getCacheDir());
					in = getContentResolver().openInputStream(source);
					if (in == null) {
						return null;
					}
					out = new FileOutputStream(temp);
					byte[] buffer = new byte[8192];
					int read;
					long total = 0;
					while ((read = in.read(buffer)) != -1) {
						total += read;
						if (total > MAX_DOCUMENT_IMPORT_BYTES) {
							throw new java.io.IOException("Import exceeds maximum supported size");
						}
						out.write(buffer, 0, read);
					}
					out.flush();
					out.close();
					out = null;
					in.close();
					in = null;
					return doImportInBackground(temp);
				} catch (Exception e) {
					Debug.log(e);
					return null;
				} finally {
					if (out != null) {
						try { out.close(); } catch (Exception e) { Debug.log(e); }
					}
					if (in != null) {
						try { in.close(); } catch (Exception e) { Debug.log(e); }
					}
					if (temp != null && temp.exists() && !temp.delete()) {
						Debug.log(new Exception("Unable to delete temporary import file"));
					}
				}
			}

			@Override
			public void onDone(T result) {
				if (result == null) {
					Toast.makeText(ImportExportActivity.this, importArray[1], Toast.LENGTH_LONG).show();
				} else {
					onPostImport(result);
				}
			}
		}.execute();
	}

	@Thunk void startImportInternal(final String filePath) {
		final String[] importArray = getResources().getStringArray(importMsgArray);
		new ProgressTask<Void, T>(this, importArray[0]) {

			@Override
			protected T doInBackground(Void... params) {
				try {
					if (filePath == null) {
						return null;
					}
					File importFile = new File(filePath);
					if (!importFile.isFile() || importFile.length() > MAX_DOCUMENT_IMPORT_BYTES) {
						throw new java.io.IOException("Import exceeds maximum supported size");
					}
					return doImportInBackground(importFile);
				} catch (Exception e) {
					Debug.log(e);
				}
				return null;
			}

			@Override
			public void onDone(T result) {
				if (result == null) {
					Toast.makeText(ImportExportActivity.this, importArray[1], Toast.LENGTH_LONG).show();
				} else {
					onPostImport(result);
				}
			}
		}.execute();
	}

	public abstract T doImportInBackground(File importFile) throws Exception;
	public abstract void onPostImport(T result);

	@Override
	public void onBackPressed() {
		super.onBackPressed();
		maybeShowAnimation();
	}

	public void maybeShowAnimation() {
		if (!isTaskRoot()) {
			overridePendingTransition(R.anim.left_slide_in, R.anim.right_slide_out);
		}
	}
}

//! C ABI over the LightCraft engine for the Swift app.
//!
//! Ownership rules (mirrored in `include/StudioPhotoEngine.h`):
//! - every `*mut c_char` returned here is freed with [`sc_string_free`];
//! - every `*mut ScImage` with [`sc_image_free`];
//! - every `*mut ScPhoto` with [`sc_photo_free`].
//! No function panics across the boundary: panics become error strings.
//!
//! A photo handle is not thread-safe: the Swift wrapper serialises access on one queue.

use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::Arc;

use lightcraft_develop::DevelopSettings;
use lightcraft_engine::Session;
use lightcraft_engine::catalog::PhotoId;
use lightcraft_engine::export::{ExportFormat, ExportOptions, export_photo, write_file};
use lightcraft_pipeline::{RenderRequest, SourceInfo, StageCache};

use lightcraft_raster::Rgb32f;
use serde_json::{Value, json};

pub struct ScPhoto {
    path: String,
    session: Session,
    id: PhotoId,
    preview: Arc<Rgb32f>,
    info: SourceInfo,
    cache: StageCache,
    base_settings: Value,
    meta: Value,
}

#[repr(C)]
pub struct ScImage {
    pub width: u32,
    pub height: u32,
    /// RGBA8, premultiplied = no, row stride = width * 4.
    pub data: *mut u8,
    pub len: usize,
}

fn cstr(p: *const c_char) -> Result<String, String> {
    if p.is_null() {
        return Err("null string".into());
    }
    unsafe { CStr::from_ptr(p) }.to_str().map(str::to_owned).map_err(|e| e.to_string())
}

fn out_string(s: impl Into<Vec<u8>>) -> *mut c_char {
    let mut v: Vec<u8> = s.into();
    v.retain(|b| *b != 0);
    CString::new(v).map(CString::into_raw).unwrap_or(std::ptr::null_mut())
}

fn set_err(err: *mut *mut c_char, msg: String) {
    if !err.is_null() {
        unsafe { *err = out_string(msg) };
    }
}

fn guarded<T>(err: *mut *mut c_char, fallback: T, f: impl FnOnce() -> Result<T, String>) -> T {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(v)) => v,
        Ok(Err(e)) => {
            set_err(err, e);
            fallback
        }
        Err(p) => {
            let msg = p
                .downcast_ref::<&str>()
                .map(|s| s.to_string())
                .or_else(|| p.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "engine panic".into());
            set_err(err, format!("engine panic: {msg}"));
            fallback
        }
    }
}

fn format_name(f: lightcraft_raw::RawFormat) -> String {
    format!("{f:?}").to_uppercase()
}

fn open(path: &str, preview_edge: usize) -> Result<ScPhoto, String> {
    let bytes = std::fs::read(path).map_err(|e| format!("{path}: {e}"))?;
    let raw_format = lightcraft_raw::probe(&bytes);
    // developed size of the original (for memory planning of full-resolution exports)
    let raw_size = raw_format.and_then(|_| lightcraft_raw::probe_info(&bytes).ok()).map(|i| i.developed_size());
    let (preview, info) = lightcraft_engine::files::load_vec(bytes, preview_edge.max(64))?;

    let mut session = Session::new().with_fs().with_system_clock();
    let r = session.execute("library.import", &json!({ "paths": [path] })).map_err(|e| e.to_string())?;
    let id = r["imported"][0].as_u64().ok_or_else(|| format!("{path}: not a readable photo"))?;
    let id = PhotoId(id);
    session
        .execute("library.select", &json!({ "ids": [id.0], "active": id.0 }))
        .map_err(|e| e.to_string())?;
    let settings = session
        .develop_of(id)
        .map(|s| (*s).clone())
        .unwrap_or_else(|| if info.raw { DevelopSettings::for_raw(info.as_shot_temp, info.as_shot_tint) } else { DevelopSettings::default() });
    let full_size = raw_size.unwrap_or((preview.width, preview.height));
    let meta = json!({
        "fullWidth": full_size.0,
        "fullHeight": full_size.1,
        "rawFormat": raw_format.map(format_name),
        "rawSupported": raw_format.map(|f| f.is_supported()),
        "isRaw": info.raw,
        "asShotTemp": info.as_shot_temp,
        "asShotTint": info.as_shot_tint,
        "relativeWB": info.relative_wb,
        "previewWidth": preview.width,
        "previewHeight": preview.height,
    });
    Ok(ScPhoto { path: path.to_string(), session, id, preview: Arc::new(preview), info, cache: StageCache::default(), base_settings: settings.to_json(), meta })
}

fn parse_settings(json: &str) -> Result<DevelopSettings, String> {
    let v: Value = serde_json::from_str(json).map_err(|e| format!("settings JSON: {e}"))?;
    DevelopSettings::from_json(&v).map_err(|e| format!("settings: {e}"))
}

/// Opens an image file (raw or rendered) and decodes a preview whose long edge is at most `preview_edge`.
#[unsafe(no_mangle)]
pub extern "C" fn sc_photo_open(path: *const c_char, preview_edge: u32, err: *mut *mut c_char) -> *mut ScPhoto {
    guarded(err, std::ptr::null_mut(), || {
        let path = cstr(path)?;
        open(&path, preview_edge as usize).map(|p| Box::into_raw(Box::new(p)))
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn sc_photo_free(p: *mut ScPhoto) {
    if !p.is_null() {
        drop(unsafe { Box::from_raw(p) });
    }
}

/// JSON object with facts about the opened source (format, raw, as-shot white balance, preview size).
#[unsafe(no_mangle)]
pub extern "C" fn sc_photo_info_json(p: *const ScPhoto) -> *mut c_char {
    match unsafe { p.as_ref() } {
        Some(p) => out_string(p.meta.to_string()),
        None => std::ptr::null_mut(),
    }
}

/// The engine's starting develop settings for this photo (full JSON, schema of `DevelopSettings`).
#[unsafe(no_mangle)]
pub extern "C" fn sc_photo_default_settings_json(p: *const ScPhoto) -> *mut c_char {
    match unsafe { p.as_ref() } {
        Some(p) => out_string(p.base_settings.to_string()),
        None => std::ptr::null_mut(),
    }
}

/// Renders the preview source with `settings_json` into an RGBA8 image fitting `max_w × max_h`.
#[unsafe(no_mangle)]
pub extern "C" fn sc_photo_render(
    p: *mut ScPhoto,
    settings_json: *const c_char,
    max_w: u32,
    max_h: u32,
    draft: bool,
    err: *mut *mut c_char,
) -> *mut ScImage {
    guarded(err, std::ptr::null_mut(), || {
        let p = unsafe { p.as_mut() }.ok_or("null photo")?;
        let s = parse_settings(&cstr(settings_json)?)?;
        let mut req = RenderRequest::fit(max_w.max(1) as usize, max_h.max(1) as usize);
        if draft {
            req.quality = lightcraft_pipeline::Quality::Draft;
        }
        let out = lightcraft_pipeline::render_cached(&p.preview, &p.info, &s, &req, &p.cache);
        let (w, h) = (out.image.width as u32, out.image.height as u32);
        let mut bytes: Vec<u8> = out.image.data.into_iter().flatten().collect();
        bytes.shrink_to_fit();
        let len = bytes.len();
        let data = Box::into_raw(bytes.into_boxed_slice()) as *mut u8;
        Ok(Box::into_raw(Box::new(ScImage { width: w, height: h, data, len })))
    })
}

/// Lightroom-style "Auto": the engine's automatic tone settings for this photo under
/// `settings_json` (white balance and process are taken into account), plus the automatic
/// B&W mix. Returns JSON `{"light":{…},"color":{…},"bw_mix":{…}}` (develop-settings paths).
#[unsafe(no_mangle)]
pub extern "C" fn sc_photo_auto_json(p: *mut ScPhoto, settings_json: *const c_char, err: *mut *mut c_char) -> *mut c_char {
    guarded(err, std::ptr::null_mut(), || {
        let p = unsafe { p.as_ref() }.ok_or("null photo")?;
        let s = parse_settings(&cstr(settings_json)?)?;
        let t = lightcraft_pipeline::auto::auto_tone(&p.preview, &p.info, &s);
        let bw = lightcraft_pipeline::auto::auto_bw_mix(&p.preview, &p.info, &s);
        let names = ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"];
        let bw_mix: serde_json::Map<String, serde_json::Value> =
            names.iter().zip(bw.iter()).map(|(n, v)| (n.to_string(), serde_json::json!(v))).collect();
        let out = serde_json::json!({
            "light": {"exposure": t.exposure, "contrast": t.contrast, "highlights": t.highlights,
                      "shadows": t.shadows, "whites": t.whites, "blacks": t.blacks},
            "color": {"vibrance": t.vibrance, "saturation": t.saturation},
            "bw_mix": bw_mix,
        });
        Ok(out_string(out.to_string()))
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn sc_image_free(img: *mut ScImage) {
    if img.is_null() {
        return;
    }
    let img = unsafe { Box::from_raw(img) };
    if !img.data.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(img.data, img.len)) });
    }
}

/// Exports the full-resolution original with `settings_json` to `out_path`.
/// `format`: "jpg", "png", "tif", "webp", "avif" or "dng"; `long_edge` 0 = full size.
/// Returns a JSON string `{width, height, bytes}` or null with `err` set.
#[unsafe(no_mangle)]
pub extern "C" fn sc_photo_export(
    p: *mut ScPhoto,
    settings_json: *const c_char,
    out_path: *const c_char,
    format: *const c_char,
    quality: u8,
    long_edge: u32,
    err: *mut *mut c_char,
) -> *mut c_char {
    guarded(err, std::ptr::null_mut(), || {
        let p = unsafe { p.as_mut() }.ok_or("null photo")?;
        let s = parse_settings(&cstr(settings_json)?)?;
        let out_path = cstr(out_path)?;
        let format = cstr(format)?;
        p.session.set_develop(p.id, s, "Studio").map_err(|e| e.to_string())?;
        let mut params = json!({ "quality": quality.clamp(1, 100) });
        if long_edge > 0 {
            params["longEdge"] = json!(long_edge);
        }
        let mut o = ExportOptions::from_params(&params).map_err(|e| e.to_string())?;
        o.format = ExportFormat::parse(&format).ok_or_else(|| format!("unknown export format {format}"))?;
        let e = export_photo(&mut p.session, p.id, &o, 1)?;
        write_file(&out_path, &e.bytes)?;
        Ok(out_string(json!({ "width": e.width, "height": e.height, "bytes": e.bytes.len() }).to_string()))
    })
}

/// Renders the original at full resolution (or fitting `long_edge`) into one RGBA8 image, tile by
/// tile with `PixelWindow`, so memory stays near "source + output" instead of the export pipeline's
/// full-frame intermediates. `tile` is the tile edge in output pixels (0 = 1024).
#[unsafe(no_mangle)]
pub extern "C" fn sc_photo_render_tiled(
    p: *mut ScPhoto,
    settings_json: *const c_char,
    long_edge: u32,
    tile: u32,
    err: *mut *mut c_char,
) -> *mut ScImage {
    guarded(err, std::ptr::null_mut(), || {
        let p = unsafe { p.as_mut() }.ok_or("null photo")?;
        let s = parse_settings(&cstr(settings_json)?)?;
        let bytes = std::fs::read(&p.path).map_err(|e| format!("{}: {e}", p.path))?;
        let max_edge = if long_edge > 0 { long_edge as usize } else { usize::MAX / 4 };
        let (src, info) = lightcraft_engine::files::load_vec(bytes, max_edge)?;
        let (nw, nh) = lightcraft_pipeline::native_output_size(src.width, src.height, &s);
        let (mut w, mut h) = (nw.round().max(1.0) as usize, nh.round().max(1.0) as usize);
        if long_edge > 0 && w.max(h) > long_edge as usize {
            let k = long_edge as f64 / w.max(h) as f64;
            w = ((w as f64) * k).round().max(1.0) as usize;
            h = ((h as f64) * k).round().max(1.0) as usize;
        }
        let mut base = RenderRequest::fit(w, h);
        let (fw, fh) = lightcraft_pipeline::output_size(src.width, src.height, &s, &base);
        base.max_w = fw;
        base.max_h = fh;
        let t = if tile == 0 { 1024 } else { tile as usize };
        let margin = 64usize;
        let mut out = vec![0u8; fw * fh * 4];
        let mut y = 0;
        while y < fh {
            let th = t.min(fh - y);
            let mut x = 0;
            while x < fw {
                let tw = t.min(fw - x);
                let (x0, y0) = (x.saturating_sub(margin), y.saturating_sub(margin));
                let win = lightcraft_pipeline::PixelWindow { x: x0, y: y0, w: (x + tw + margin).min(fw) - x0, h: (y + th + margin).min(fh) - y0 }
                    .clamped(fw, fh);
                let mut req = base;
                req.window = Some(win);
                let r = lightcraft_pipeline::render(&src, &info, &s, &req);
                if r.image.width != win.w || r.image.height != win.h {
                    return Err(format!("tile {}x{} != window {}x{}", r.image.width, r.image.height, win.w, win.h));
                }
                for row in 0..th {
                    let sy = y + row - win.y;
                    let src_off = (sy * win.w + (x - win.x)) * 4;
                    let dst_off = ((y + row) * fw + x) * 4;
                    let px = &r.image.data[src_off / 4..src_off / 4 + tw];
                    for (i, c) in px.iter().enumerate() {
                        out[dst_off + i * 4..dst_off + i * 4 + 4].copy_from_slice(c);
                    }
                }
                x += tw;
            }
            y += th;
        }
        let len = out.len();
        let data = Box::into_raw(out.into_boxed_slice()) as *mut u8;
        Ok(Box::into_raw(Box::new(ScImage { width: fw as u32, height: fh as u32, data, len })))
    })
}

/// Recognises a raw container from a file's bytes without decoding it:
/// `{"format": "NEF", "supported": true}` or `{"format": null}`.
#[unsafe(no_mangle)]
pub extern "C" fn sc_raw_probe(path: *const c_char, err: *mut *mut c_char) -> *mut c_char {
    guarded(err, std::ptr::null_mut(), || {
        let path = cstr(path)?;
        let bytes = std::fs::read(&path).map_err(|e| format!("{path}: {e}"))?;
        let f = lightcraft_raw::probe(&bytes);
        let decoded = f.map(|_| lightcraft_raw::probe_info(&bytes).is_ok());
        Ok(out_string(
            json!({ "format": f.map(format_name), "supported": f.map(|f| f.is_supported()), "headerReadable": decoded }).to_string(),
        ))
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn sc_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(unsafe { CString::from_raw(s) });
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn sc_engine_version() -> *mut c_char {
    out_string(format!("studio-photo-engine {} / lightcraft 3b4279f", env!("CARGO_PKG_VERSION")))
}

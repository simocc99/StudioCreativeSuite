//! Runs every file given on the command line through the same C ABI the app uses:
//! probe → open (full raw decode, not the embedded JPEG) → render a preview → export a JPEG.
//! Usage: cargo run --release --example rawcheck -- OUT_DIR FILE...
use std::ffi::{CStr, CString, c_char};
use std::time::Instant;

use studio_photo_engine::*;

fn take(s: *mut c_char) -> Option<String> {
    if s.is_null() {
        return None;
    }
    let r = unsafe { CStr::from_ptr(s) }.to_string_lossy().into_owned();
    sc_string_free(s);
    Some(r)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let out_dir = &args[0];
    let mut failures = 0;
    for path in &args[1..] {
        let name = std::path::Path::new(path).file_name().unwrap().to_string_lossy().to_string();
        let c = CString::new(path.as_str()).unwrap();
        let mut err: *mut c_char = std::ptr::null_mut();
        let probe = take(sc_raw_probe(c.as_ptr(), &mut err)).unwrap_or_default();
        let t = Instant::now();
        let p = sc_photo_open(c.as_ptr(), 1600, &mut err);
        if p.is_null() {
            println!("FAIL {name}: open: {}", take(err).unwrap_or_default());
            failures += 1;
            continue;
        }
        let t_open = t.elapsed();
        let info = take(sc_photo_info_json(p)).unwrap();
        let settings = take(sc_photo_default_settings_json(p)).unwrap();
        if std::env::var("DUMP").is_ok() { println!("{settings}"); }
        let mut v: serde_json::Value = serde_json::from_str(&settings).unwrap();
        v["light"]["exposure"] = serde_json::json!(0.5);
        let s = CString::new(v.to_string()).unwrap();
        let img = sc_photo_render(p, s.as_ptr(), 1024, 1024, false, &mut err);
        if img.is_null() {
            println!("FAIL {name}: render: {}", take(err).unwrap_or_default());
            failures += 1;
            sc_photo_free(p);
            continue;
        }
        let (w, h, px) = unsafe {
            let i = &*img;
            (i.width, i.height, std::slice::from_raw_parts(i.data, i.len).to_vec())
        };
        sc_image_free(img);
        // a real development is not a flat frame: measure luminance spread
        let lum: Vec<f64> = px.chunks(4).map(|p| 0.2126 * p[0] as f64 + 0.7152 * p[1] as f64 + 0.0722 * p[2] as f64).collect();
        let mean = lum.iter().sum::<f64>() / lum.len() as f64;
        let sd = (lum.iter().map(|l| (l - mean).powi(2)).sum::<f64>() / lum.len() as f64).sqrt();
        let out = CString::new(format!("{out_dir}/{name}.jpg")).unwrap();
        let fmt = CString::new("jpg").unwrap();
        let t2 = Instant::now();
        let exp = take(sc_photo_export(p, s.as_ptr(), out.as_ptr(), fmt.as_ptr(), 90, 2048, &mut err));
        let t_exp = t2.elapsed();
        sc_photo_free(p);
        match exp {
            Some(e) => println!(
                "OK   {name}\n     probe={probe}\n     info={info}\n     preview={w}x{h} mean={mean:.1} sd={sd:.1} open={t_open:.2?} export={t_exp:.2?} -> {e}"
            ),
            None => {
                println!("FAIL {name}: export: {}", take(err).unwrap_or_default());
                failures += 1;
            }
        }
    }
    std::process::exit(if failures == 0 { 0 } else { 1 });
}

//! Compares the tiled full-resolution render with a single-window render and reports timing.
//! Usage: tiledcheck FILE MODE   (MODE: compare | tiled | export)
use std::ffi::{CString, c_char};
use std::time::Instant;
use studio_photo_engine::*;

fn grab(img: *mut ScImage) -> (u32, u32, Vec<u8>) {
    assert!(!img.is_null(), "render failed");
    let r = unsafe { ((*img).width, (*img).height, std::slice::from_raw_parts((*img).data, (*img).len).to_vec()) };
    sc_image_free(img);
    r
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let path = CString::new(a[1].clone()).unwrap();
    let mut err: *mut c_char = std::ptr::null_mut();
    let p = sc_photo_open(path.as_ptr(), 1200, &mut err);
    let s = unsafe { std::ffi::CStr::from_ptr(sc_photo_default_settings_json(p)) }.to_owned();
    let t = Instant::now();
    match a[2].as_str() {
        "compare" => {
            let (w1, h1, one) = grab(sc_photo_render_tiled(p, s.as_ptr(), 2048, 100_000, &mut err));
            let (w2, h2, tiles) = grab(sc_photo_render_tiled(p, s.as_ptr(), 2048, 300, &mut err));
            let mut diff = 0u64;
            let mut maxd = 0u8;
            for (x, y) in one.iter().zip(&tiles) {
                let d = x.abs_diff(*y);
                diff += d as u64;
                maxd = maxd.max(d);
            }
            println!("single {w1}x{h1} vs tiles(300) {w2}x{h2}: mean abs diff {:.4}, max {maxd}", diff as f64 / one.len() as f64);
        }
        "tiled" => {
            let (w, h, _) = grab(sc_photo_render_tiled(p, s.as_ptr(), 0, 1024, &mut err));
            println!("tiled full {w}x{h} in {:.2?}", t.elapsed());
        }
        _ => {
            let out = CString::new("/tmp/tiledcheck.jpg").unwrap();
            let f = CString::new("jpg").unwrap();
            let r = sc_photo_export(p, s.as_ptr(), out.as_ptr(), f.as_ptr(), 90, 0, &mut err);
            println!("export {} in {:.2?}", if r.is_null() { "FAILED".into() } else { unsafe { std::ffi::CStr::from_ptr(r) }.to_string_lossy().into_owned() }, t.elapsed());
        }
    }
    sc_photo_free(p);
}

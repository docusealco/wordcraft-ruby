//! C ABI over WordCraft (<https://github.com/storytold/wordcraft>) for the wordcraft Ruby gem.
//!
//! ```c
//! typedef struct { uint8_t *data; size_t len; size_t cap; } WcBuffer;
//! typedef struct WcDocument WcDocument;
//!
//! // 0 ok, 1 error, 2 panic, -1 bad args
//! int32_t wc_open(const uint8_t *docx, size_t docx_len, uint32_t flags,
//!                 WcDocument **out_doc, char **out_error);
//! int32_t wc_page_count(const WcDocument *doc, size_t *out_count, char **out_error);
//! int32_t wc_to_pdf(const WcDocument *doc, WcBuffer *out_pdf, char **out_error);
//! int32_t wc_render(const WcDocument *doc, size_t page, float scale, uint32_t format, uint8_t quality,
//!                   WcBuffer *out_image, uint32_t *out_width, uint32_t *out_height, char **out_error);
//! void    wc_close(WcDocument *doc);
//!
//! void    wc_free_buffer(WcBuffer buf);
//! void    wc_free_error(char *err);
//! int32_t wc_add_font(const uint8_t *font, size_t font_len);  // faces added, -1 on failure
//! int64_t wc_load_system_fonts(void);                         // faces cataloged, -1 on failure
//! ```
//!
//! Everything handed out is owned by the caller and released with `wc_close` / `wc_free_buffer` /
//! `wc_free_error`. Panics are caught here: none unwinds into, or aborts, the host process.

use std::cell::OnceCell;
use std::ffi::{CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;

use wordcraft_engine::doc::Document;
use wordcraft_engine::layout::{DocLayout, LayoutCache, LayoutOptions, layout};

/// `wc_open` flag: Print Markup, i.e. tracked changes and comments shown as in Word's
/// "All Markup" view.
pub const WC_MARKUP: u32 = 1;

pub const WC_RGBA: u32 = 0;
pub const WC_PNG: u32 = 1;
pub const WC_JPEG: u32 = 2;

const OK: i32 = 0;
const ERR_CONVERT: i32 = 1;
const ERR_PANIC: i32 = 2;
const ERR_ARGS: i32 = -1;

/// A byte buffer handed to the caller. `cap` travels with `len` so that `wc_free_buffer` can
/// rebuild the exact `Vec` that produced it.
#[repr(C)]
pub struct WcBuffer {
    pub data: *mut u8,
    pub len: usize,
    pub cap: usize,
}

impl WcBuffer {
    fn empty() -> Self {
        WcBuffer { data: ptr::null_mut(), len: 0, cap: 0 }
    }

    fn from_vec(v: Vec<u8>) -> Self {
        let mut v = std::mem::ManuallyDrop::new(v);
        WcBuffer { data: v.as_mut_ptr(), len: v.len(), cap: v.capacity() }
    }
}

pub struct WcDocument {
    doc: Document,
    markup: bool,
    layout: OnceCell<DocLayout>,
}

impl WcDocument {
    fn open(docx: &[u8], flags: u32) -> Result<Self, String> {
        if docx.is_empty() {
            return Err("empty document".into());
        }
        let doc = wordcraft_engine::io::open_bytes("document.docx", docx)?;
        Ok(WcDocument { doc, markup: flags & WC_MARKUP != 0, layout: OnceCell::new() })
    }

    fn layout(&self) -> &DocLayout {
        self.layout.get_or_init(|| {
            let opts = LayoutOptions { hide_deleted: !self.markup, comment_balloons: self.markup, ..Default::default() };
            layout(&self.doc, &mut LayoutCache::new(), &opts)
        })
    }

    fn to_pdf(&self) -> Result<Vec<u8>, String> {
        let opts = wordcraft_pdf::PdfOptions { include_markup: self.markup, comments: self.markup, ..Default::default() };
        wordcraft_pdf::export_layout(&self.doc, self.layout(), &opts).map_err(|e| e.to_string())
    }

    fn render(&self, page: usize, scale: f32, format: u32, quality: u8) -> Result<(Vec<u8>, u32, u32), String> {
        let layout_page = self.layout().pages.get(page).ok_or_else(|| format!("page {} does not exist", page.saturating_add(1)))?;
        let image = wordcraft_render::render_page(&self.doc, layout_page, scale, &wordcraft_render::RenderOptions::default());
        let bytes = match format {
            WC_RGBA => image.to_straight(),
            WC_PNG => image.to_png(),
            WC_JPEG => image.to_jpeg(quality),
            _ => return Err(format!("unknown image format {format}")),
        };
        if bytes.is_empty() {
            return Err("could not encode the page image".into());
        }
        Ok((bytes, image.width, image.height))
    }
}

fn panic_message(payload: &(dyn std::any::Any + Send)) -> String {
    payload
        .downcast_ref::<&str>()
        .map(|s| (*s).to_string())
        .or_else(|| payload.downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "unknown panic".to_string())
}

/// # Safety
/// `out_error` is null or writable.
unsafe fn set_error(out_error: *mut *mut c_char, message: &str) {
    if out_error.is_null() {
        return;
    }
    let message = CString::new(message.replace('\0', " ")).unwrap_or_default();
    // SAFETY: checked non-null; the caller guarantees it is writable.
    unsafe { *out_error = message.into_raw() };
}

unsafe fn clear_error(out_error: *mut *mut c_char) {
    if !out_error.is_null() {
        unsafe { *out_error = ptr::null_mut() };
    }
}

unsafe fn null_argument(out_error: *mut *mut c_char, function: &str) -> i32 {
    unsafe { set_error(out_error, &format!("{function}: null argument")) };
    ERR_ARGS
}

unsafe fn guard<T>(out_error: *mut *mut c_char, f: impl FnOnce() -> Result<T, String>) -> Result<T, i32> {
    let (code, message) = match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(value)) => return Ok(value),
        Ok(Err(message)) => (ERR_CONVERT, message),
        Err(payload) => (ERR_PANIC, format!("internal error: {}", panic_message(payload.as_ref()))),
    };
    unsafe { set_error(out_error, &message) };
    Err(code)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wc_open(
    docx: *const u8,
    docx_len: usize,
    flags: u32,
    out_doc: *mut *mut WcDocument,
    out_error: *mut *mut c_char,
) -> i32 {
    unsafe { clear_error(out_error) };
    if docx.is_null() || out_doc.is_null() {
        return unsafe { null_argument(out_error, "wc_open") };
    }
    unsafe { *out_doc = ptr::null_mut() };
    let bytes = unsafe { std::slice::from_raw_parts(docx, docx_len) };

    match unsafe { guard(out_error, || WcDocument::open(bytes, flags)) } {
        Ok(doc) => {
            unsafe { *out_doc = Box::into_raw(Box::new(doc)) };
            OK
        }
        Err(code) => code,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wc_page_count(doc: *const WcDocument, out_count: *mut usize, out_error: *mut *mut c_char) -> i32 {
    unsafe { clear_error(out_error) };
    if doc.is_null() || out_count.is_null() {
        return unsafe { null_argument(out_error, "wc_page_count") };
    }
    let doc = unsafe { &*doc };

    match unsafe { guard(out_error, || Ok(doc.layout().pages.len())) } {
        Ok(count) => {
            unsafe { *out_count = count };
            OK
        }
        Err(code) => code,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wc_to_pdf(doc: *const WcDocument, out_pdf: *mut WcBuffer, out_error: *mut *mut c_char) -> i32 {
    unsafe { clear_error(out_error) };
    if doc.is_null() || out_pdf.is_null() {
        return unsafe { null_argument(out_error, "wc_to_pdf") };
    }
    unsafe { *out_pdf = WcBuffer::empty() };
    let doc = unsafe { &*doc };

    match unsafe { guard(out_error, || doc.to_pdf()) } {
        Ok(pdf) => {
            unsafe { *out_pdf = WcBuffer::from_vec(pdf) };
            OK
        }
        Err(code) => code,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wc_render(
    doc: *const WcDocument,
    page: usize,
    scale: f32,
    format: u32,
    quality: u8,
    out_image: *mut WcBuffer,
    out_width: *mut u32,
    out_height: *mut u32,
    out_error: *mut *mut c_char,
) -> i32 {
    unsafe { clear_error(out_error) };
    if doc.is_null() || out_image.is_null() || out_width.is_null() || out_height.is_null() {
        return unsafe { null_argument(out_error, "wc_render") };
    }
    unsafe { *out_image = WcBuffer::empty() };
    let doc = unsafe { &*doc };

    match unsafe { guard(out_error, || doc.render(page, scale, format, quality)) } {
        Ok((bytes, width, height)) => {
            unsafe {
                *out_image = WcBuffer::from_vec(bytes);
                *out_width = width;
                *out_height = height;
            }
            OK
        }
        Err(code) => code,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn wc_close(doc: *mut WcDocument) {
    if doc.is_null() {
        return;
    }
    drop(unsafe { Box::from_raw(doc) });
}

/// Releases a buffer from `wc_to_pdf` or `wc_render`. A no-op on an empty buffer.
///
/// # Safety
/// `buf` came from `wc_to_pdf` or `wc_render`, unmodified, and is freed once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wc_free_buffer(buf: WcBuffer) {
    if buf.data.is_null() {
        return;
    }
    // SAFETY: `buf` describes a Vec made by `WcBuffer::from_vec`.
    drop(unsafe { Vec::from_raw_parts(buf.data, buf.len, buf.cap) });
}

/// Releases an error message from a `wc_*` call. A no-op on null.
///
/// # Safety
/// `err` came from a `wc_*` call, unmodified, and is freed once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wc_free_error(err: *mut c_char) {
    if err.is_null() {
        return;
    }
    // SAFETY: `err` was made by `CString::into_raw`.
    drop(unsafe { CString::from_raw(err) });
}

/// Adds a font (TTF, OTF, TTC, WOFF or WOFF2 bytes) for every later conversion in this process.
/// Returns the number of faces added (0 when they were all present or the file doesn't parse), or
/// -1 on bad arguments or a panic.
///
/// # Safety
/// `font` points to `font_len` readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wc_add_font(font: *const u8, font_len: usize) -> i32 {
    if font.is_null() || font_len == 0 {
        return -1;
    }
    // SAFETY: the caller guarantees `font_len` readable bytes at `font`.
    let bytes = unsafe { std::slice::from_raw_parts(font, font_len) }.to_vec();
    let decoded = wordcraft_fonts::decode_font_file(&bytes).unwrap_or(bytes);
    catch_unwind(AssertUnwindSafe(|| wordcraft_fonts::FontDb::global().add_document_fonts(vec![(decoded, String::new())])))
        .map(|n| i32::try_from(n).unwrap_or(i32::MAX))
        .unwrap_or(-1)
}

/// Catalogs the installed system fonts now (otherwise the first conversion that needs them does).
/// Returns the number of faces cataloged, or -1 on a panic.
#[unsafe(no_mangle)]
pub extern "C" fn wc_load_system_fonts() -> i64 {
    catch_unwind(|| wordcraft_fonts::FontDb::global().load_system_fonts())
        .map(|n| i64::try_from(n).unwrap_or(i64::MAX))
        .unwrap_or(-1)
}

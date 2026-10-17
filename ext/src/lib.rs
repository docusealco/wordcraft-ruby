//! C ABI over WordCraft (<https://github.com/storytold/wordcraft>) for the wordcraft Ruby gem.
//!
//! ```c
//! typedef struct { uint8_t *data; size_t len; size_t cap; } WcBuffer;
//!
//! int32_t wc_convert(const uint8_t *docx, size_t docx_len, uint32_t flags,
//!                    WcBuffer *out_pdf, char **out_error);  // 0 ok, 1 error, 2 panic, -1 bad args
//! void    wc_free_buffer(WcBuffer buf);
//! void    wc_free_error(char *err);
//! int32_t wc_add_font(const uint8_t *font, size_t font_len);  // faces added, -1 on failure
//! int64_t wc_load_system_fonts(void);                         // faces cataloged, -1 on failure
//! ```
//!
//! Everything handed out is owned by the caller and released with `wc_free_buffer` /
//! `wc_free_error`. Panics are caught here: none unwinds into, or aborts, the host process.

use std::ffi::{CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;

/// `wc_convert` flag: Print Markup, i.e. tracked changes and comments shown as in Word's
/// "All Markup" view.
pub const WC_MARKUP: u32 = 1;

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

fn convert(docx: &[u8], flags: u32) -> Result<Vec<u8>, String> {
    if docx.is_empty() {
        return Err("empty document".into());
    }
    let doc = wordcraft_engine::io::open_bytes("document.docx", docx)?;
    let markup = flags & WC_MARKUP != 0;
    let opts = wordcraft_engine::io::ExportOptions { markup, comments: markup, ..Default::default() };
    wordcraft_engine::io::save_bytes_opts("document.pdf", &doc, &opts)
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

/// Converts `docx_len` bytes of DOCX at `docx` to PDF. On success writes the PDF to `*out_pdf`
/// and returns 0; otherwise writes a message to `*out_error` and returns non-zero.
///
/// # Safety
/// `docx` points to `docx_len` readable bytes; `out_pdf` and `out_error` are null or writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wc_convert(
    docx: *const u8,
    docx_len: usize,
    flags: u32,
    out_pdf: *mut WcBuffer,
    out_error: *mut *mut c_char,
) -> i32 {
    if !out_pdf.is_null() {
        // SAFETY: checked non-null; the caller guarantees it is writable.
        unsafe { *out_pdf = WcBuffer::empty() };
    }
    if !out_error.is_null() {
        // SAFETY: as above.
        unsafe { *out_error = ptr::null_mut() };
    }
    if docx.is_null() || out_pdf.is_null() {
        // SAFETY: out_error is null or writable.
        unsafe { set_error(out_error, "wc_convert: null argument") };
        return ERR_ARGS;
    }

    // SAFETY: the caller guarantees `docx_len` readable bytes at `docx`.
    let bytes = unsafe { std::slice::from_raw_parts(docx, docx_len) };

    match catch_unwind(AssertUnwindSafe(|| convert(bytes, flags))) {
        Ok(Ok(pdf)) => {
            // SAFETY: checked non-null above.
            unsafe { *out_pdf = WcBuffer::from_vec(pdf) };
            OK
        }
        Ok(Err(message)) => {
            // SAFETY: out_error is null or writable.
            unsafe { set_error(out_error, &message) };
            ERR_CONVERT
        }
        Err(payload) => {
            // SAFETY: out_error is null or writable.
            unsafe { set_error(out_error, &format!("internal error: {}", panic_message(payload.as_ref()))) };
            ERR_PANIC
        }
    }
}

/// Releases a buffer from `wc_convert`. A no-op on an empty buffer.
///
/// # Safety
/// `buf` came from `wc_convert`, unmodified, and is freed once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn wc_free_buffer(buf: WcBuffer) {
    if buf.data.is_null() {
        return;
    }
    // SAFETY: `buf` describes a Vec made by `WcBuffer::from_vec`.
    drop(unsafe { Vec::from_raw_parts(buf.data, buf.len, buf.cap) });
}

/// Releases an error message from `wc_convert`. A no-op on null.
///
/// # Safety
/// `err` came from `wc_convert`, unmodified, and is freed once.
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
    catch_unwind(AssertUnwindSafe(|| wordcraft_fonts::FontDb::global().add_document_fonts(vec![decoded])))
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

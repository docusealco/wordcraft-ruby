# WordCraft

Fast DOCX to PDF and page image conversion for Ruby. Ruby FFI bindings for [WordCraft](https://github.com/storytold/wordcraft), a pure Rust word processor engine.

- **In-process.** No LibreOffice, no headless browser, no conversion service.
- **Fast.** A typical document converts in tens of milliseconds.
- **Thread-friendly.** Conversions release the GVL, so Puma and Sidekiq threads convert in parallel.
- **Self-contained.** Fonts are bundled; no system packages needed.
- **Prebuilt.** Native libraries for macOS and Linux (glibc and musl) ship inside the platform gems.

## Installation

```ruby
# Gemfile
gem 'wordcraft'
```

Requires Ruby 3.1+.

## Quick start

```ruby
require 'wordcraft'

WordCraft.open('contract.docx') do |doc|
  File.binwrite('contract.pdf', doc.to_pdf)
  File.binwrite('page-1.png', doc.to_png(page: 1))
end
```

## API

### Open a document

`WordCraft.open(path, markup: false) { |doc| ... } → the block's value`

`WordCraft.open_buffer(input, markup: false) { |doc| ... } → the block's value`

Without a block, both return a `WordCraft::Document`.

Opens the document and lays it out once. The PDF, the page count and every page image come from that one layout.

| Argument | Type | |
|---|---|---|
| `path` | `String` or `Pathname` | The file to open. |
| `input` | `String` or `IO` | The DOCX bytes, or an IO to read them from (`StringIO`, `File`, an upload). The IO is rewound after it's read. |
| `markup:` | `Boolean`, optional | Show tracked changes and comments, as in Word's "All Markup" view. Off by default. |

With a block, the document is closed when the block returns or raises. Without a block, close it yourself: a document left open is freed only when Ruby garbage-collects it, which can be much later.

Raises `WordCraft::Error` when the document can't be opened. RTF and `.doc` files open too.

```ruby
pdf = WordCraft.open('contract.docx', &:to_pdf)
pdf = WordCraft.open_buffer(docx, &:to_pdf)

doc = WordCraft.open_buffer(upload)
begin
  pdf = doc.to_pdf
  thumbnail = doc.to_jpeg(page: 1, dpi: 72)
ensure
  doc.close
end
```

### Document

| Method | Returns |
|---|---|
| `doc.page_count` | `Integer` |
| `doc.to_pdf` | PDF bytes |
| `doc.to_png(page:, dpi: 144)` | PNG bytes of one page |
| `doc.to_jpeg(page:, dpi: 144, quality: 85)` | JPEG bytes of one page; `quality` is 1 to 100 |
| `doc.to_rgba(page:, dpi: 144)` | `[pixels, width, height]`: 8-bit RGBA, row by row, `width * height * 4` bytes |
| `doc.close` | `nil`. Frees the document; calling it again does nothing. |
| `doc.closed?` | `Boolean` |

`page:` counts from 1. Page images match the PDF's pages. A US Letter page at 144 dpi is 1224 × 1584 pixels.

A document isn't thread-safe: use each one from a single thread. Separate documents convert in parallel.

`to_rgba` skips image encoding, for handing pages straight to an image library:

```ruby
pixels, width, height = doc.to_rgba(page: 1)
image = Vips::Image.new_from_memory(pixels, width, height, 4, :uchar)
```

### Fonts

`WordCraft.add_font(bytes)` / `WordCraft.add_font_file(path)` make a font available to every document opened after. Both return the number of faces added.

`WordCraft.load_system_fonts` loads the installed system fonts up front instead of on the first conversion. Call it at boot.

```ruby
WordCraft.add_font_file('/app/fonts/Brand-Regular.ttf')
WordCraft.load_system_fonts
```

### Errors

`WordCraft::Error` is raised when a document can't be opened or converted, and when a closed document is used. A page that doesn't exist, a `dpi` that isn't positive or a `quality` outside 1 to 100 raises `ArgumentError`.

```ruby
begin
  pdf = WordCraft.open_buffer(upload, &:to_pdf)
rescue WordCraft::Error => e
  Rails.logger.warn("DOCX conversion failed: #{e.message}")
end
```

## Examples

Send a converted upload from a Rails controller:

```ruby
def create
  pdf = WordCraft.open_buffer(params[:file], &:to_pdf)

  send_data pdf, type: 'application/pdf', filename: 'document.pdf'
rescue WordCraft::Error => e
  render plain: e.message, status: :unprocessable_entity
end
```

Convert an Active Storage attachment:

```ruby
pdf = WordCraft.open_buffer(document.file.download, &:to_pdf)

document.pdf.attach(io: StringIO.new(pdf), filename: "#{document.file.filename.base}.pdf",
                    content_type: 'application/pdf')
```

Attach a preview of every page:

```ruby
WordCraft.open_buffer(document.file.download) do |doc|
  (1..doc.page_count).each do |page|
    document.previews.attach(io: StringIO.new(doc.to_jpeg(page:, dpi: 72)), filename: "page-#{page}.jpg",
                             content_type: 'image/jpeg')
  end
end
```

## Fonts

WordCraft uses the fonts embedded in the document, then installed system fonts, then its bundled fonts. For Word's proprietary fonts it picks metric-compatible open ones when they are installed. For page breaks closest to Word, install them:

```dockerfile
# Alpine
RUN apk add --no-cache font-liberation font-carlito
# Debian / Ubuntu
RUN apt-get install -y --no-install-recommends fonts-liberation2 fonts-crosextra-carlito
```

## Alpine (musl) performance

musl's `malloc` slows conversions down, especially in parallel. Preload jemalloc:

```dockerfile
RUN apk add --no-cache jemalloc
ENV LD_PRELOAD=/usr/lib/libjemalloc.so.2
```

## Untrusted input

Using this library to convert untrusted documents (user uploads, files from the internet) is not recommended. The conversion runs native code inside your Ruby process with no sandbox.

If you convert untrusted documents, you must use an isolated, sandboxed process.

## License

MIT. The native library bundles WordCraft (MIT OR Apache-2.0) and the Source Sans 3, Source Serif 4, Inter and JetBrains Mono fonts (OFL-1.1); their licenses and WordCraft's attribution list are in `licenses/`, and WordCraft's notices in `NOTICE`.

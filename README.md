# WordCraft

Fast DOCX to PDF conversion for Ruby. Ruby FFI bindings for [WordCraft](https://github.com/storytold/wordcraft), a pure Rust word processor engine.

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

pdf = WordCraft.convert(File.binread('contract.docx'))
File.binwrite('contract.pdf', pdf)
```

## API

### Convert DOCX bytes

`WordCraft.convert(docx, markup: false) → String`

Converts a DOCX document to PDF and returns the PDF bytes.

| Argument | Type | |
|---|---|---|
| `docx` | `String` | The DOCX file's bytes. |
| `markup:` | `Boolean`, optional | Show tracked changes and comments, as in Word's "All Markup" view. Off by default. |

Raises `WordCraft::Error` when the document can't be opened or converted. RTF and `.doc` files are converted too.

```ruby
pdf = WordCraft.convert(docx)
pdf = WordCraft.convert(docx, markup: true)
```

### Convert a file

`WordCraft.convert_file(input_path, output_path, markup: false) → String`

Reads `input_path`, converts it, and writes the PDF to `output_path`. Returns `output_path`.

```ruby
WordCraft.convert_file('in.docx', 'out.pdf')
```

### Fonts

`WordCraft.add_font(bytes)` / `WordCraft.add_font_file(path)` make a font available to every later conversion. Both return the number of faces added.

`WordCraft.load_system_fonts` loads the installed system fonts up front instead of on the first conversion. Call it at boot.

```ruby
WordCraft.add_font_file('/app/fonts/Brand-Regular.ttf')
WordCraft.load_system_fonts
```

### Errors

`WordCraft::Error` is raised for every conversion failure.

```ruby
begin
  WordCraft.convert(upload.read)
rescue WordCraft::Error => e
  Rails.logger.warn("DOCX conversion failed: #{e.message}")
end
```

## Examples

Send a converted upload from a Rails controller:

```ruby
def create
  pdf = WordCraft.convert(params[:file].read)

  send_data pdf, type: 'application/pdf', filename: 'document.pdf'
rescue WordCraft::Error => e
  render plain: e.message, status: :unprocessable_entity
end
```

Convert an Active Storage attachment:

```ruby
pdf = WordCraft.convert(document.file.download)

document.pdf.attach(io: StringIO.new(pdf), filename: "#{document.file.filename.base}.pdf",
                    content_type: 'application/pdf')
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

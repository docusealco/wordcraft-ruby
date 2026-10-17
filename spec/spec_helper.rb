# frozen_string_literal: true

require 'wordcraft'
require 'stringio'
require 'zip'

module DocxHelper
  CONTENT_TYPES = <<~XML
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
  XML

  RELS = <<~XML
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
  XML

  def build_docx(*paragraphs)
    body = paragraphs.map { |text| "<w:p><w:r><w:t>#{text}</w:t></w:r></w:p>" }.join

    document = <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>#{body}<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body>
      </w:document>
    XML

    entries = { '[Content_Types].xml' => CONTENT_TYPES, '_rels/.rels' => RELS, 'word/document.xml' => document }

    buffer = Zip::OutputStream.write_buffer(StringIO.new) do |zip|
      entries.each do |name, xml|
        zip.put_next_entry(name)
        zip.write(xml)
      end
    end

    buffer.string
  end
end

RSpec.configure do |config|
  config.include DocxHelper
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end

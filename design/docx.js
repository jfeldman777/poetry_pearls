(function () {
  var W_NS = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  var R_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  var REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/';
  var HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

  function esc(s) {
    return String(s)
      .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, '')
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function run(text, o) {
    o = o || {};
    var rPr = (o.style ? '<w:rStyle w:val="' + o.style + '"/>' : '') +
      (o.b ? '<w:b/><w:bCs/>' : '') +
      (o.color ? '<w:color w:val="' + o.color + '"/>' : '') +
      (o.sz ? '<w:sz w:val="' + o.sz + '"/><w:szCs w:val="' + o.sz + '"/>' : '') +
      (o.en ? '<w:lang w:val="en-US"/>' : '');
    return '<w:r>' + (rPr ? '<w:rPr>' + rPr + '</w:rPr>' : '') + '<w:t xml:space="preserve">' + esc(text) + '</w:t></w:r>';
  }

  function para(runs, o) {
    o = o || {};
    var pPr = (o.style ? '<w:pStyle w:val="' + o.style + '"/>' : '') +
      (o.keep ? '<w:keepNext/>' : '') +
      (o.after != null ? '<w:spacing w:before="' + (o.before || 0) + '" w:after="' + o.after + '"/>' : '') +
      (o.center ? '<w:jc w:val="center"/>' : '');
    return '<w:p>' + (pPr ? '<w:pPr>' + pPr + '</w:pPr>' : '') + (runs || '') + '</w:p>';
  }

  function verse(text, en) {
    return text.replace(/\r/g, '').split('\n').map(function (line) {
      line = line.replace(/\s+$/, '');
      return para(line ? run(line, { en: en }) : '');
    }).join('');
  }

  // poems: [{ title, poet, url, parts: [{ title, poet, text, credit, en }] }] — the first part goes under the poem heading.
  function documentXml(poems, opts, links) {
    var out = [];
    out.push(para(run(opts.site, { color: '808080' }), { center: true, after: 0 }));
    out.push(para(run(opts.title, { b: true, sz: 40 }), { center: true, before: 120, after: 240 }));
    poems.forEach(function (poem) {
      out.push(para(run(poem.title), { style: 'Heading1' }));
      poem.parts.forEach(function (part, i) {
        if (i) out.push(para(run(part.title, { en: part.en }), { style: 'Heading2' }));
        var poet = i ? part.poet : poem.poet;
        if (poet) out.push(para(run(poet, { en: part.en }), { style: 'PoemPoet' }));
        out.push(verse(part.text, part.en));
        if (part.credit) out.push(para(run(part.credit), { style: 'PoemInfo' }));
      });
      if (poem.url) {
        var id = 'rIdLink' + (links.length + 1);
        links.push({ id: id, url: poem.url });
        out.push(para('<w:hyperlink r:id="' + id + '">' + run(poem.url, { style: 'Hyperlink' }) + '</w:hyperlink>', { style: 'PoemInfo' }));
      }
    });
    return HEAD + '<w:document xmlns:w="' + W_NS + '" xmlns:r="' + R_NS + '"><w:body>' + out.join('') +
      '<w:sectPr><w:footerReference w:type="default" r:id="rIdFooter"/>' +
      '<w:pgSz w:w="11906" w:h="16838"/>' +
      '<w:pgMar w:top="1134" w:right="1247" w:bottom="1134" w:left="1247" w:header="567" w:footer="567" w:gutter="0"/>' +
      '<w:cols w:space="708"/></w:sectPr></w:body></w:document>';
  }

  function paraStyle(id, name, pPr, rPr) {
    return '<w:style w:type="paragraph" w:customStyle="1" w:styleId="' + id + '"><w:name w:val="' + name + '"/>' +
      '<w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr>' + pPr + '</w:pPr><w:rPr>' + rPr + '</w:rPr></w:style>';
  }

  var stylesXml = HEAD +
    '<w:styles xmlns:w="' + W_NS + '">' +
    '<w:docDefaults><w:rPrDefault><w:rPr>' +
    '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="Times New Roman" w:cs="Times New Roman"/>' +
    '<w:sz w:val="24"/><w:szCs w:val="24"/><w:lang w:val="ru-RU" w:eastAsia="ru-RU" w:bidi="ar-SA"/>' +
    '</w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:before="0" w:after="0" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>' +
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>' +
    '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>' +
    '<w:pPr><w:keepNext/><w:spacing w:before="720" w:after="60"/><w:outlineLvl w:val="0"/></w:pPr>' +
    '<w:rPr><w:b/><w:bCs/><w:sz w:val="30"/><w:szCs w:val="30"/></w:rPr></w:style>' +
    '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>' +
    '<w:pPr><w:keepNext/><w:spacing w:before="400" w:after="60"/><w:outlineLvl w:val="1"/></w:pPr>' +
    '<w:rPr><w:b/><w:bCs/><w:i/><w:iCs/><w:sz w:val="26"/><w:szCs w:val="26"/></w:rPr></w:style>' +
    paraStyle('PoemPoet', 'Poem poet', '<w:keepNext/><w:spacing w:before="0" w:after="240"/>', '<w:i/><w:iCs/><w:color w:val="595959"/>') +
    paraStyle('PoemInfo', 'Poem info', '<w:spacing w:before="160" w:after="0"/>', '<w:color w:val="808080"/><w:sz w:val="20"/><w:szCs w:val="20"/>') +
    '<w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="2B5D7C"/><w:u w:val="single"/></w:rPr></w:style>' +
    '<w:style w:type="paragraph" w:styleId="Footer"><w:name w:val="footer"/><w:basedOn w:val="Normal"/>' +
    '<w:pPr><w:jc w:val="center"/></w:pPr><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>' +
    '</w:styles>';

  var settingsXml = HEAD +
    '<w:settings xmlns:w="' + W_NS + '"><w:defaultTabStop w:val="708"/><w:characterSpacingControl w:val="doNotCompress"/>' +
    '<w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>' +
    '</w:settings>';

  var footerXml = HEAD +
    '<w:ftr xmlns:w="' + W_NS + '" xmlns:r="' + R_NS + '"><w:p><w:pPr><w:pStyle w:val="Footer"/></w:pPr>' +
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>' +
    '<w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r>' +
    '</w:p></w:ftr>';

  function coreXml(opts) {
    return HEAD +
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" ' +
      'xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>' + esc(opts.title) + '</dc:title><dc:creator>' + esc(opts.site) + '</dc:creator></cp:coreProperties>';
  }

  var contentTypesXml = HEAD +
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
    '<Default Extension="xml" ContentType="application/xml"/>' +
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>' +
    '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>' +
    '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>' +
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>' +
    '</Types>';

  var rootRelsXml = HEAD +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="' + REL + 'officeDocument" Target="word/document.xml"/>' +
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>' +
    '</Relationships>';

  function documentRelsXml(links) {
    return HEAD +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rIdStyles" Type="' + REL + 'styles" Target="styles.xml"/>' +
      '<Relationship Id="rIdSettings" Type="' + REL + 'settings" Target="settings.xml"/>' +
      '<Relationship Id="rIdFooter" Type="' + REL + 'footer" Target="footer1.xml"/>' +
      links.map(function (l) {
        return '<Relationship Id="' + l.id + '" Type="' + REL + 'hyperlink" Target="' + esc(l.url) + '" TargetMode="External"/>';
      }).join('') +
      '</Relationships>';
  }

  // ZIP without compression.
  var CRC_TABLE = (function () {
    var table = new Uint32Array(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      table[n] = c >>> 0;
    }
    return table;
  })();

  function crc32(bytes) {
    var c = 0xFFFFFFFF;
    for (var i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
  }

  function zip(files) {
    var encoder = new TextEncoder();
    var parts = [];
    var central = [];
    var offset = 0;
    files.forEach(function (file) {
      var name = encoder.encode(file.name);
      var data = encoder.encode(file.data);
      var crc = crc32(data);

      var local = new DataView(new ArrayBuffer(30));
      local.setUint32(0, 0x04034b50, true);
      local.setUint16(4, 20, true);
      local.setUint16(6, 0x0800, true);
      local.setUint16(12, 0x21, true);
      local.setUint32(14, crc, true);
      local.setUint32(18, data.length, true);
      local.setUint32(22, data.length, true);
      local.setUint16(26, name.length, true);
      parts.push(new Uint8Array(local.buffer), name, data);

      var entry = new DataView(new ArrayBuffer(46));
      entry.setUint32(0, 0x02014b50, true);
      entry.setUint16(4, 20, true);
      entry.setUint16(6, 20, true);
      entry.setUint16(8, 0x0800, true);
      entry.setUint16(14, 0x21, true);
      entry.setUint32(16, crc, true);
      entry.setUint32(20, data.length, true);
      entry.setUint32(24, data.length, true);
      entry.setUint16(28, name.length, true);
      entry.setUint32(42, offset, true);
      central.push(new Uint8Array(entry.buffer), name);

      offset += 30 + name.length + data.length;
    });
    var centralSize = central.reduce(function (sum, part) { return sum + part.length; }, 0);
    var end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true);
    end.setUint16(8, files.length, true);
    end.setUint16(10, files.length, true);
    end.setUint32(12, centralSize, true);
    end.setUint32(16, offset, true);
    return new Blob(parts.concat(central, [new Uint8Array(end.buffer)]), {
      type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    });
  }

  // opts: { title, site }
  function build(poems, opts) {
    var links = [];
    var document = documentXml(poems, opts, links);
    return zip([
      { name: '[Content_Types].xml', data: contentTypesXml },
      { name: '_rels/.rels', data: rootRelsXml },
      { name: 'docProps/core.xml', data: coreXml(opts) },
      { name: 'word/document.xml', data: document },
      { name: 'word/_rels/document.xml.rels', data: documentRelsXml(links) },
      { name: 'word/styles.xml', data: stylesXml },
      { name: 'word/settings.xml', data: settingsXml },
      { name: 'word/footer1.xml', data: footerXml }
    ]);
  }

  window.PearlsDocx = { build: build };
})();

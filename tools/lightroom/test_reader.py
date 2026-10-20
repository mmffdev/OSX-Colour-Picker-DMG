"""Exercise the read-only reader without depending on a Lightroom installation."""
from pathlib import Path
import subprocess
import urllib.parse
import tempfile
import struct

reader = Path(__file__).resolve().parents[2] / '.build/lightroom/Colorgain.lrplugin/ColorgainMetadataReader'
def read(path):
    output = subprocess.check_output([str(reader), str(path)], text=True)
    return {key: urllib.parse.unquote(value) for key, value in (line.split('\t', 1) for line in output.splitlines())}

with tempfile.TemporaryDirectory() as folder:
    p = Path(folder) / "test ' $(no).xmp"
    xml = '<r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><r:Description xmlns:c="urn:colorgain:metadata:1.0:"><c:colorgain>XXXXX &amp; café\nnext</c:colorgain></r:Description></r:RDF>'
    p.write_text(xml)
    assert read(p)['value'] == 'XXXXX & café\nnext'
    p.write_text('<broken>')
    assert read(p)['status'] == 'Could not refresh'
    p.write_text('<!DOCTYPE x [<!ENTITY e SYSTEM "file:///etc/passwd">]><x>&e;</x>')
    assert read(p)['status'] == 'Could not refresh'
    p.write_bytes(b'II*\0' + struct.pack('<I', 99999))
    p = p.rename(p.with_suffix('.dng'))
    assert read(p)['status'] == 'Could not refresh'
    assert read(Path(folder) / 'missing.dng')['status'] == 'Could not refresh'
    p.write_bytes(b'II*\0' + struct.pack('<I', 8) + struct.pack('<H', 0) + struct.pack('<I', 0))
    assert read(p)['status'] == 'No Colorgain fields in this source'
    packet = xml.encode()
    for order, magic in [('<', b'II'), ('>', b'MM')]:
        p.write_bytes(magic + struct.pack(order+'HI',42,8) + struct.pack(order+'H',1) + struct.pack(order+'HHII',700,1,len(packet),26) + struct.pack(order+'I',0) + packet)
        before = p.read_bytes()
        assert read(p)['value'] == 'XXXXX & café\nnext'
        assert p.read_bytes() == before
    p.with_suffix('.xmp').write_text('<r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><r:Description xmlns:c="urn:colorgain:metadata:1.0:" c:colorgain="SIDECAR"/></r:RDF>')
    assert read(p)['value'] == 'SIDECAR'
    p.with_suffix('.xmp').write_text('<r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><r:Description/></r:RDF>')
    assert read(p)['value'] == 'XXXXX & café\nnext'
    assert read(p)['source'] == str(p)
    p.with_suffix('.xmp').write_text('<broken>')
    assert read(p)['status'] == 'Could not refresh'
print('PASS: XMP attributes/elements, namespace prefixes, UTF-8, malformed XML/TIFF, entity rejection, missing source, empty metadata, both TIFF byte orders, read-only bytes, sidecar precedence')

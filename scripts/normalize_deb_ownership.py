"""Normalize only the ownership metadata of a freshly built Theos deb."""
from pathlib import Path
import gzip
import io
import lzma
import sys
import tarfile


def normalize(package):
    blob = package.read_bytes()
    if not blob.startswith(b'!<arch>\n'):
        raise ValueError('Not a Debian ar archive')
    result = bytearray(blob[:8])
    offset = 8
    while offset < len(blob):
        header = blob[offset:offset + 60]
        if len(header) != 60 or header[58:60] != b'`\n':
            raise ValueError('Malformed ar member')
        name = header[:16].decode().strip().rstrip('/')
        size = int(header[48:58])
        payload = blob[offset + 60:offset + 60 + size]
        if len(payload) != size:
            raise ValueError('Truncated ar member')
        offset += 60 + size + size % 2
        if name.startswith(('control.tar', 'data.tar')):
            output = io.BytesIO()
            raw = lzma.decompress(payload) if name.endswith('.lzma') else payload
            with tarfile.open(fileobj=io.BytesIO(raw), mode='r:*') as source:
                with tarfile.open(fileobj=output, mode='w', format=tarfile.GNU_FORMAT) as target:
                    for member in source:
                        member.uid = member.gid = 0
                        member.uname, member.gname = 'root', 'wheel'
                        member.pax_headers = {k: v for k, v in member.pax_headers.items()
                                              if k not in ('uid', 'gid', 'uname', 'gname')}
                        target.addfile(member, source.extractfile(member) if member.isfile() else None)
            payload = output.getvalue()
            if name.endswith('.gz'):
                payload = gzip.compress(payload, mtime=0)
            elif name.endswith('.lzma'):
                payload = lzma.compress(payload, format=lzma.FORMAT_ALONE)
            elif name.endswith('.xz'):
                payload = lzma.compress(payload, format=lzma.FORMAT_XZ)
            elif not name.endswith('.tar'):
                raise ValueError(f'Unsupported compression: {name}')
        result.extend(header[:48] + str(len(payload)).encode().ljust(10) + b'`\n')
        result.extend(payload)
        if len(payload) % 2:
            result.extend(b'\n')
    temporary = package.with_suffix(package.suffix + '.tmp')
    temporary.write_bytes(result)
    temporary.replace(package)
    print(f'Normalized root:wheel ownership: {package.name}')


if __name__ == '__main__':
    normalize(Path(sys.argv[1]))

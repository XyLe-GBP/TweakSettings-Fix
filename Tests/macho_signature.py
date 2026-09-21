"""Validate ldid CodeDirectory page and embedded entitlement hashes (not Apple trust).

Layout: Apple's CS_CodeDirectory / LC_CODE_SIGNATURE and TN3126.
https://developer.apple.com/documentation/technotes/tn3126-inside-code-signing-hashes
"""
import hashlib
import struct


def verify_signature(binary):
    assert binary[:4] == b'\xcf\xfa\xed\xfe', 'Expected a thin, little-endian Mach-O 64'
    count = struct.unpack_from('<I', binary, 16)[0]
    offset = 32
    signature = None
    for _ in range(count):
        command, size = struct.unpack_from('<II', binary, offset)
        assert size >= 8 and offset + size <= len(binary)
        if command == 0x1d:
            start, length = struct.unpack_from('<II', binary, offset + 8)
            signature = binary[start:start + length]
        offset += size
    assert signature is not None
    magic, length, count = struct.unpack_from('>III', signature)
    assert magic == 0xfade0cc0 and length <= len(signature)
    blobs = {}
    for index in range(count):
        slot, offset = struct.unpack_from('>II', signature, 12 + index * 8)
        _, length = struct.unpack_from('>II', signature, offset)
        blobs[slot] = signature[offset:offset + length]
    directories = [blob for blob in blobs.values() if blob[:4] == b'\xfa\xde\x0c\x02']
    assert directories and 5 in blobs, 'Missing code directory or entitlements'
    for directory in directories:
        (_, length, version, flags, hashes, identifier,
         special_count, code_count, limit) = struct.unpack_from('>9I', directory)
        hash_size, hash_type, platform, page_power = struct.unpack_from('4B', directory, 36)
        algorithm = {1: 'sha1', 2: 'sha256', 3: 'sha256', 4: 'sha384'}[hash_type]
        page_size = 1 << page_power
        assert limit <= start and code_count == (limit + page_size - 1) // page_size
        assert length == len(directory) and hashes + code_count * hash_size <= length
        for index in range(code_count):
            page = binary[index * page_size:min((index + 1) * page_size, limit)]
            digest = hashlib.new(algorithm, page).digest()[:hash_size]
            actual = directory[hashes + index * hash_size:hashes + (index + 1) * hash_size]
            assert digest == actual, f'Code page {index} hash mismatch'
        for slot in (2, 5, 7):  # requirements, XML entitlements, DER entitlements
            if slot in blobs and slot <= special_count:
                digest = hashlib.new(algorithm, blobs[slot]).digest()[:hash_size]
                actual = directory[hashes - slot * hash_size:hashes - (slot - 1) * hash_size]
                assert digest == actual, f'Special slot {slot} hash mismatch'

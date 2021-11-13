import math
import re
import click

def bs(x, w):
    return bin(x & ((1 << w) - 1))[2:].rjust(w, '0')

def k(x, y):
    return (y << 5) | x

def cw(b, k):
    return ("K" if k else "D") + f"{b & 0x1f}.{b >> 5}"

def popcnt(n, w):
    s = 0
    for i in range(w):
        s += (n >> i) & 1
    return s

def rd(init, code):
    v = 1 if init == 1 else -1
    for i in range(10):
        v += 1 if (code >> i) & 1 else -1
    if v == 1:
        return 1
    if v == -1:
        return 0
    return None

def rd_err_strict(init, code):
    v = 1 if init else -1
    limits = [2, 3, 2, 3, 2, 1, 2, 1, 2, 1]
    for i, l in enumerate(limits):
        v += 1 if (code >> i) & 1 else -1
        if abs(v) > l:
            return True
    return False

def rd_err_loose(init, code):
    v = 1 if init else -1
    limits = [2, 3, 4, 3, 2, 1, 2, 3, 2, 1]
    for i, l in enumerate(limits):
        v += 1 if (code >> i) & 1 else -1
        if abs(v) > l:
            return True
    return False

class Encoding:
    def __init__(self, word, rd_i):
        self.word = word
        self.rd_i = rd_i
        self.rd_o = rd(rd_i, word)
        self.rd_changes = self.rd_i != self.rd_o

    def __str__(self):
        return bs(self.word, 10)

class Entry:
    def __init__(self, data, k, enc0, enc1):
        self.data = data
        self.k = bool(k)
        self.enc = [Encoding(enc0, 0), Encoding(enc1, 1)]

    def __str__(self):
        return f"{'DK'[int(self.k)]}{self.data&0x1f}.{self.data>>5} ({self.data:#02x})"

class T8b10b:
    controls = [k(28, x) for x in range(8)] + [k(23, 7), k(27, 7), k(29, 7), k(30, 7)]
    def _init():
        # From IEEE-820.3 Section 3, 36.2.4, Table 36-1 and 36-2
        table = """
        D0.0 00 000 00000 100111 0100 011000 1011
        D1.0 01 000 00001 011101 0100 100010 1011
        D2.0 02 000 00010 101101 0100 010010 1011
        D3.0 03 000 00011 110001 1011 110001 0100
        D4.0 04 000 00100 110101 0100 001010 1011
        D5.0 05 000 00101 101001 1011 101001 0100
        D6.0 06 000 00110 011001 1011 011001 0100
        D7.0 07 000 00111 111000 1011 000111 0100
        D8.0 08 000 01000 111001 0100 000110 1011
        D9.0 09 000 01001 100101 1011 100101 0100
        D10.0 0A 000 01010 010101 1011 010101 0100
        D11.0 0B 000 01011 110100 1011 110100 0100
        D12.0 0C 000 01100 001101 1011 001101 0100
        D13.0 0D 000 01101 101100 1011 101100 0100
        D14.0 0E 000 01110 011100 1011 011100 0100
        D15.0 0F 000 01111 010111 0100 101000 1011
        D16.0 10 000 10000 011011 0100 100100 1011
        D17.0 11 000 10001 100011 1011 100011 0100
        D18.0 12 000 10010 010011 1011 010011 0100
        D19.0 13 000 10011 110010 1011 110010 0100
        D20.0 14 000 10100 001011 1011 001011 0100
        D21.0 15 000 10101 101010 1011 101010 0100
        D22.0 16 000 10110 011010 1011 011010 0100
        D23.0 17 000 10111 111010 0100 000101 1011
        D24.0 18 000 11000 110011 0100 001100 1011
        D25.0 19 000 11001 100110 1011 100110 0100
        D26.0 1A 000 11010 010110 1011 010110 0100
        D27.0 1B 000 11011 110110 0100 001001 1011
        D28.0 1C 000 11100 001110 1011 001110 0100
        D29.0 1D 000 11101 101110 0100 010001 1011
        D30.0 1E 000 11110 011110 0100 100001 1011
        D31.0 1F 000 11111 101011 0100 010100 1011
        D0.1 20 001 00000 100111 1001 011000 1001
        D1.1 21 001 00001 011101 1001 100010 1001
        D2.1 22 001 00010 101101 1001 010010 1001
        D3.1 23 001 00011 110001 1001 110001 1001
        D4.1 24 001 00100 110101 1001 001010 1001
        D5.1 25 001 00101 101001 1001 101001 1001
        D6.1 26 001 00110 011001 1001 011001 1001
        D7.1 27 001 00111 111000 1001 000111 1001
        D8.1 28 001 01000 111001 1001 000110 1001
        D9.1 29 001 01001 100101 1001 100101 1001
        D10.1 2A 001 01010 010101 1001 010101 1001
        D11.1 2B 001 01011 110100 1001 110100 1001
        D12.1 2C 001 01100 001101 1001 001101 1001
        D13.1 2D 001 01101 101100 1001 101100 1001
        D14.1 2E 001 01110 011100 1001 011100 1001
        D15.1 2F 001 01111 010111 1001 101000 1001
        D16.1 30 001 10000 011011 1001 100100 1001
        D17.1 31 001 10001 100011 1001 100011 1001
        D18.1 32 001 10010 010011 1001 010011 1001
        D19.1 33 001 10011 110010 1001 110010 1001
        D20.1 34 001 10100 001011 1001 001011 1001
        D21.1 35 001 10101 101010 1001 101010 1001
        D22.1 36 001 10110 011010 1001 011010 1001
        D23.1 37 001 10111 111010 1001 000101 1001
        D24.1 38 001 11000 110011 1001 001100 1001
        D25.1 39 001 11001 100110 1001 100110 1001
        D26.1 3A 001 11010 010110 1001 010110 1001
        D27.1 3B 001 11011 110110 1001 001001 1001
        D28.1 3C 001 11100 001110 1001 001110 1001
        D29.1 3D 001 11101 101110 1001 010001 1001
        D30.1 3E 001 11110 011110 1001 100001 1001
        D31.1 3F 001 11111 101011 1001 010100 1001
        D0.2 40 010 00000 100111 0101 011000 0101
        D1.2 41 010 00001 011101 0101 100010 0101
        D2.2 42 010 00010 101101 0101 010010 0101
        D3.2 43 010 00011 110001 0101 110001 0101
        D4.2 44 010 00100 110101 0101 001010 0101
        D5.2 45 010 00101 101001 0101 101001 0101
        D6.2 46 010 00110 011001 0101 011001 0101
        D7.2 47 010 00111 111000 0101 000111 0101
        D8.2 48 010 01000 111001 0101 000110 0101
        D9.2 49 010 01001 100101 0101 100101 0101
        D10.2 4A 010 01010 010101 0101 010101 0101
        D11.2 4B 010 01011 110100 0101 110100 0101
        D12.2 4C 010 01100 001101 0101 001101 0101
        D13.2 4D 010 01101 101100 0101 101100 0101
        D14.2 4E 010 01110 011100 0101 011100 0101
        D15.2 4F 010 01111 010111 0101 101000 0101
        D16.2 50 010 10000 011011 0101 100100 0101
        D17.2 51 010 10001 100011 0101 100011 0101
        D18.2 52 010 10010 010011 0101 010011 0101
        D19.2 53 010 10011 110010 0101 110010 0101
        D20.2 54 010 10100 001011 0101 001011 0101
        D21.2 55 010 10101 101010 0101 101010 0101
        D22.2 56 010 10110 011010 0101 011010 0101
        D23.2 57 010 10111 111010 0101 000101 0101
        D24.2 58 010 11000 110011 0101 001100 0101
        D25.2 59 010 11001 100110 0101 100110 0101
        D26.2 5A 010 11010 010110 0101 010110 0101
        D27.2 5B 010 11011 110110 0101 001001 0101
        D28.2 5C 010 11100 001110 0101 001110 0101
        D29.2 5D 010 11101 101110 0101 010001 0101
        D30.2 5E 010 11110 011110 0101 100001 0101
        D31.2 5F 010 11111 101011 0101 010100 0101
        D0.3 60 011 00000 100111 0011 011000 1100
        D1.3 61 011 00001 011101 0011 100010 1100
        D2.3 62 011 00010 101101 0011 010010 1100
        D3.3 63 011 00011 110001 1100 110001 0011
        D4.3 64 011 00100 110101 0011 001010 1100
        D5.3 65 011 00101 101001 1100 101001 0011
        D6.3 66 011 00110 011001 1100 011001 0011
        D7.3 67 011 00111 111000 1100 000111 0011
        D8.3 68 011 01000 111001 0011 000110 1100
        D9.3 69 011 01001 100101 1100 100101 0011
        D10.3 6A 011 01010 010101 1100 010101 0011
        D11.3 6B 011 01011 110100 1100 110100 0011
        D12.3 6C 011 01100 001101 1100 001101 0011
        D13.3 6D 011 01101 101100 1100 101100 0011
        D14.3 6E 011 01110 011100 1100 011100 0011
        D15.3 6F 011 01111 010111 0011 101000 1100
        D16.3 70 011 10000 011011 0011 100100 1100
        D17.3 71 011 10001 100011 1100 100011 0011
        D18.3 72 011 10010 010011 1100 010011 0011
        D19.3 73 011 10011 110010 1100 110010 0011
        D20.3 74 011 10100 001011 1100 001011 0011
        D21.3 75 011 10101 101010 1100 101010 0011
        D22.3 76 011 10110 011010 1100 011010 0011
        D23.3 77 011 10111 111010 0011 000101 1100
        D24.3 78 011 11000 110011 0011 001100 1100
        D25.3 79 011 11001 100110 1100 100110 0011
        D26.3 7A 011 11010 010110 1100 010110 0011
        D27.3 7B 011 11011 110110 0011 001001 1100
        D28.3 7C 011 11100 001110 1100 001110 0011
        D29.3 7D 011 11101 101110 0011 010001 1100
        D30.3 7E 011 11110 011110 0011 100001 1100
        D31.3 7F 011 11111 101011 0011 010100 1100
        D0.4 80 100 00000 100111 0010 011000 1101
        D1.4 81 100 00001 011101 0010 100010 1101
        D2.4 82 100 00010 101101 0010 010010 1101
        D3.4 83 100 00011 110001 1101 110001 0010
        D4.4 84 100 00100 110101 0010 001010 1101
        D5.4 85 100 00101 101001 1101 101001 0010
        D6.4 86 100 00110 011001 1101 011001 0010
        D7.4 87 100 00111 111000 1101 000111 0010
        D8.4 88 100 01000 111001 0010 000110 1101
        D9.4 89 100 01001 100101 1101 100101 0010
        D10.4 8A 100 01010 010101 1101 010101 0010
        D11.4 8B 100 01011 110100 1101 110100 0010
        D12.4 8C 100 01100 001101 1101 001101 0010
        D13.4 8D 100 01101 101100 1101 101100 0010
        D14.4 8E 100 01110 011100 1101 011100 0010
        D15.4 8F 100 01111 010111 0010 101000 1101
        D16.4 90 100 10000 011011 0010 100100 1101
        D17.4 91 100 10001 100011 1101 100011 0010
        D18.4 92 100 10010 010011 1101 010011 0010
        D19.4 93 100 10011 110010 1101 110010 0010
        D20.4 94 100 10100 001011 1101 001011 0010
        D21.4 95 100 10101 101010 1101 101010 0010
        D22.4 96 100 10110 011010 1101 011010 0010
        D23.4 97 100 10111 111010 0010 000101 1101
        D24.4 98 100 11000 110011 0010 001100 1101
        D25.4 99 100 11001 100110 1101 100110 0010
        D26.4 9A 100 11010 010110 1101 010110 0010
        D27.4 9B 100 11011 110110 0010 001001 1101
        D28.4 9C 100 11100 001110 1101 001110 0010
        D29.4 9D 100 11101 101110 0010 010001 1101
        D30.4 9E 100 11110 011110 0010 100001 1101
        D31.4 9F 100 11111 101011 0010 010100 1101
        D0.5 A0 101 00000 100111 1010 011000 1010
        D1.5 A1 101 00001 011101 1010 100010 1010
        D2.5 A2 101 00010 101101 1010 010010 1010
        D3.5 A3 101 00011 110001 1010 110001 1010
        D4.5 A4 101 00100 110101 1010 001010 1010
        D5.5 A5 101 00101 101001 1010 101001 1010
        D6.5 A6 101 00110 011001 1010 011001 1010
        D7.5 A7 101 00111 111000 1010 000111 1010
        D8.5 A8 101 01000 111001 1010 000110 1010
        D9.5 A9 101 01001 100101 1010 100101 1010
        D10.5 AA 101 01010 010101 1010 010101 1010
        D11.5 AB 101 01011 110100 1010 110100 1010
        D12.5 AC 101 01100 001101 1010 001101 1010
        D13.5 AD 101 01101 101100 1010 101100 1010
        D14.5 AE 101 01110 011100 1010 011100 1010
        D15.5 AF 101 01111 010111 1010 101000 1010
        D16.5 B0 101 10000 011011 1010 100100 1010
        D17.5 B1 101 10001 100011 1010 100011 1010
        D18.5 B2 101 10010 010011 1010 010011 1010
        D19.5 B3 101 10011 110010 1010 110010 1010
        D20.5 B4 101 10100 001011 1010 001011 1010
        D21.5 B5 101 10101 101010 1010 101010 1010
        D22.5 B6 101 10110 011010 1010 011010 1010
        D23.5 B7 101 10111 111010 1010 000101 1010
        D24.5 B8 101 11000 110011 1010 001100 1010
        D25.5 B9 101 11001 100110 1010 100110 1010
        D26.5 BA 101 11010 010110 1010 010110 1010
        D27.5 BB 101 11011 110110 1010 001001 1010
        D28.5 BC 101 11100 001110 1010 001110 1010
        D29.5 BD 101 11101 101110 1010 010001 1010
        D30.5 BE 101 11110 011110 1010 100001 1010
        D31.5 BF 101 11111 101011 1010 010100 1010
        D0.6 C0 110 00000 100111 0110 011000 0110
        D1.6 C1 110 00001 011101 0110 100010 0110
        D2.6 C2 110 00010 101101 0110 010010 0110
        D3.6 C3 110 00011 110001 0110 110001 0110
        D4.6 C4 110 00100 110101 0110 001010 0110
        D5.6 C5 110 00101 101001 0110 101001 0110
        D6.6 C6 110 00110 011001 0110 011001 0110
        D7.6 C7 110 00111 111000 0110 000111 0110
        D8.6 C8 110 01000 111001 0110 000110 0110
        D9.6 C9 110 01001 100101 0110 100101 0110
        D10.6 CA 110 01010 010101 0110 010101 0110
        D11.6 CB 110 01011 110100 0110 110100 0110
        D12.6 CC 110 01100 001101 0110 001101 0110
        D13.6 CD 110 01101 101100 0110 101100 0110
        D14.6 CE 110 01110 011100 0110 011100 0110
        D15.6 CF 110 01111 010111 0110 101000 0110
        D16.6 D0 110 10000 011011 0110 100100 0110
        D17.6 D1 110 10001 100011 0110 100011 0110
        D18.6 D2 110 10010 010011 0110 010011 0110
        D19.6 D3 110 10011 110010 0110 110010 0110
        D20.6 D4 110 10100 001011 0110 001011 0110
        D21.6 D5 110 10101 101010 0110 101010 0110
        D22.6 D6 110 10110 011010 0110 011010 0110
        D23.6 D7 110 10111 111010 0110 000101 0110
        D24.6 D8 110 11000 110011 0110 001100 0110
        D25.6 D9 110 11001 100110 0110 100110 0110
        D26.6 DA 110 11010 010110 0110 010110 0110
        D27.6 DB 110 11011 110110 0110 001001 0110
        D28.6 DC 110 11100 001110 0110 001110 0110
        D29.6 DD 110 11101 101110 0110 010001 0110
        D30.6 DE 110 11110 011110 0110 100001 0110
        D31.6 DF 110 11111 101011 0110 010100 0110
        D0.7 E0 111 00000 100111 0001 011000 1110
        D1.7 E1 111 00001 011101 0001 100010 1110
        D2.7 E2 111 00010 101101 0001 010010 1110
        D3.7 E3 111 00011 110001 1110 110001 0001
        D4.7 E4 111 00100 110101 0001 001010 1110
        D5.7 E5 111 00101 101001 1110 101001 0001
        D6.7 E6 111 00110 011001 1110 011001 0001
        D7.7 E7 111 00111 111000 1110 000111 0001
        D8.7 E8 111 01000 111001 0001 000110 1110
        D9.7 E9 111 01001 100101 1110 100101 0001
        D10.7 EA 111 01010 010101 1110 010101 0001
        D11.7 EB 111 01011 110100 1110 110100 1000
        D12.7 EC 111 01100 001101 1110 001101 0001
        D13.7 ED 111 01101 101100 1110 101100 1000
        D14.7 EE 111 01110 011100 1110 011100 1000
        D15.7 EF 111 01111 010111 0001 101000 1110
        D16.7 F0 111 10000 011011 0001 100100 1110
        D17.7 F1 111 10001 100011 0111 100011 0001
        D18.7 F2 111 10010 010011 0111 010011 0001
        D19.7 F3 111 10011 110010 1110 110010 0001
        D20.7 F4 111 10100 001011 0111 001011 0001
        D21.7 F5 111 10101 101010 1110 101010 0001
        D22.7 F6 111 10110 011010 1110 011010 0001
        D23.7 F7 111 10111 111010 0001 000101 1110
        D24.7 F8 111 11000 110011 0001 001100 1110
        D25.7 F9 111 11001 100110 1110 100110 0001
        D26.7 FA 111 11010 010110 1110 010110 0001
        D27.7 FB 111 11011 110110 0001 001001 1110
        D28.7 FC 111 11100 001110 1110 001110 0001
        D29.7 FD 111 11101 101110 0001 010001 1110
        D30.7 FE 111 11110 011110 0001 100001 1110
        D31.7 FF 111 11111 101011 0001 010100 1110
        K28.0 1C 000 11100 001111 0100 110000 1011
        K28.1 3C 001 11100 001111 1001 110000 0110
        K28.2 5C 010 11100 001111 0101 110000 1010
        K28.3 7C 011 11100 001111 0011 110000 1100
        K28.4 9C 100 11100 001111 0010 110000 1101
        K28.5 BC 101 11100 001111 1010 110000 0101
        K28.6 DC 110 11100 001111 0110 110000 1001
        K28.7 FC 111 11100 001111 1000 110000 0111
        K23.7 F7 111 10111 111010 1000 000101 0111
        K27.7 FB 111 11011 110110 1000 001001 0111
        K29.7 FD 111 11101 101110 1000 010001 0111
        K30.7 FE 111 11110 011110 1000 100001 0111
        """

        codec = []
        entries = []
        for l in table.split("\n"):
            l = l.strip()
            if not l:
                continue
            name, d_hex, HGF, EDCBA, abcdei_m, fghj_m, abcdei_p, fghj_p = l.split()
            d_bin = int("0b"+(HGF+EDCBA), 2)
            d_hex = int(d_hex, 16)
            assert d_bin == d_hex
            code_m = int("0b"+(abcdei_m+fghj_m)[::-1], 2)
            rd_m = rd(0, code_m)
            assert rd_m is not None
            code_p = int("0b"+(abcdei_p+fghj_p)[::-1], 2)
            rd_p = rd(1, code_p)
            assert rd_p is not None
            is_k = bool(int(name.startswith('K')))
            codec.append([0, is_k, d_bin, rd_m, code_m])
            codec.append([1, is_k, d_bin, rd_p, code_p])
            entries.append(Entry(d_bin, is_k, code_m, code_p))
        return codec, entries

    codec, entries = _init()
    encoder_map = {(e.data, e.k):e for e in entries}
    decoder_map = {e.enc[0].word:e for e in entries} | {e.enc[1].word:e for e in entries}

    @classmethod
    def codec_check(cls):
        decoder_poss = {i:set() for i in range(1024)}
        for rd_i, k_i, d_i, rd_o, d_o in cls.codec:
            decoder_poss[d_o].add((rd_i, d_i, k_i, rd_o))
        for d_o, decs in decoder_poss.items():
            assert len(decs) <= 2
            if len(decs) < 2:
                continue
            (rd_i0, d_i0, k_i0, rd_o0), (rd_i1, d_i1, k_i1, rd_o1) = decs
            if rd_i0 == rd_o0 and rd_i1 == rd_o1:
                #print("No RD change", d_o, decs)
                continue
            if d_i0 != d_i1 or k_i0 != k_i1:
                print("different decode", d_o, decs)
                continue
            if rd_o0 != rd_o1 and rd_i0 == rd_i1:
                print("Not always swap", d_o, decs)
                continue
            if rd_i0 != rd_o0 and rd_i1 != rd_o1:
                print("RD always changes", d_o, decs)
                continue
            print("other", d_o, decs)

    def __init__(self):
        pass

    def enc_dump(self, code, k, rd_i):
        k = int(bool(k))
        try:
            entry = self.encoder_map[(code, bool(k))]
        except KeyError:
            entry = Entry(code, bool(k), 0, 0)
            print(f"Enc {entry}, rd={rd_i} -> Decode error")
            return
        print(f"Enc {entry}, rd={rd_i} -> {entry.enc[rd_i]}, rd={entry.enc[rd_i].rd_o}")

    def dec_dump(self, word, rd = None):
        try:
            entry = self.decoder_map[word]
        except KeyError:
            for r in ([rd] if rd is not None else [0,1]):
                print(f"Dec {bs(word, 10)}, rd={r} -> Decode error{', Disparity error' if rd_err_strict(r, word) else ''}")
            return
        for r in ([rd] if rd is not None else [0,1]):
            if entry.enc[r].word == word:
                print(f"Dec {bs(word, 10)}, rd={r} -> {entry}, rd={entry.enc[r].rd_o}{', Disparity error' if r != entry.enc[r].rd_i else ''}")

    def enc_table_gen(self):
        """rd_i, k, d_i -> rd_o, d_o"""
        def enc_index(rd, k, code):
            return (rd << 9) | (k << 8) | code

        def enc_value(rd, code):
            return (rd << 10) | code

        enc_table = ["-----------"] * 1024

        for (d_i, k_i), entry in self.encoder_map.items():
            for rd_i in [0, 1]:
                index = enc_index(rd_i, k_i, d_i)
                value = bs(enc_value(entry.enc[rd_i].rd_o, entry.enc[rd_i].word), 11)
                assert enc_table[index] == "-----------"
                enc_table[index] = value

        return enc_table, [f"enc_lut_data_{x}" for x in range(10)] + ["enc_lut_rd"]

    def dec_table_gen(self):
        """d_o -> rd_swap, rderr1, rderr0, error1, error0, k_i, d_i"""
        dec_table = []
        # Fill in disp error
        for d_o in range(1024):
            rderr0 = int(rd_err_strict(0, d_o))
            rderr1 = int(rd_err_strict(1, d_o))
            dec_table.append(f"-{rderr1}{rderr0}11---------")

        for d_o, entry in self.decoder_map.items():
            ok0 = int(entry.enc[0].word == d_o)
            ok1 = int(entry.enc[1].word == d_o)
            if ok0 and ok1:
                assert entry.enc[0].rd_changes == entry.enc[1].rd_changes
            dec_table[d_o] = str(int(entry.enc[ok1].rd_changes)) \
                             + dec_table[d_o][1:-11] \
                             + f"{1-ok1}{1-ok0}{int(entry.k)}{bs(entry.data, 8)}"

        for d in dec_table:
            assert len(d) == 14

        return dec_table, [f"dec_lut_data_{x}" for x in range(8)] + ["dec_lut_k", "dec_lut_err0", "dec_lut_err1", "dec_lut_rderr0", "dec_lut_rderr1", "dec_lut_rd_swap"]
                    
    def enc_table_check(self):
        enc_table, names = self.enc_table_gen()
        for index, value in enumerate(enc_table):
            rd_i = (index >> 9) & 1
            k_i = (index >> 8) & 1
            d_i = index & 0xff
            exists = value[-1] != '-'
            if not exists:
                assert k_i and d_i not in self.controls, (k_i, d_i)
                continue
            rd_o = int(value[0:1], 2)
            d_o = int(value[1:11], 2)

            entry = self.encoder_map[(d_i, bool(k_i))]
            assert entry.enc[rd_i].word == d_o, (rd_i, str(entry), bs(entry.enc[rd_i].word, 10), bs(d_o, 10))
            assert entry.enc[rd_i].rd_o == rd_o

    def dec_table_check(self):
        dec_table, names = self.dec_table_gen()
        for index, value in enumerate(dec_table):
            d_o = index
            rderr1 = int(value[-13], 2)
            rderr0 = int(value[-12], 2)
            err1 = int(value[-11], 2)
            err0 = int(value[-10], 2)

            try:
                entry = self.decoder_map[d_o]
            except KeyError:
                assert err1 and err0
                continue
            for rd, (enc, err, rderr) in enumerate(zip(entry.enc,
                                                       [err0, err1],
                                                       [rderr0, rderr1])):
                if not err:
                    rd_toggle = int(value[-14], 2)
                    k_i = int(value[-9], 2)
                    d_i = int(value[-8:], 2)
                    assert enc.word == d_o
                    assert entry.data == d_i
                    assert (rd ^ rd_toggle) == enc.rd_o

    def lut_dump(self):
        enc_table, enc_table_names = self.enc_table_gen()
        dec_table, dec_table_names = self.dec_table_gen()

        luts = {}
        for i, o in enumerate(enc_table_names):
            luts[o] = "".join(x[-1-i] for x in enc_table)

        for i, o in enumerate(dec_table_names):
            luts[o] = "".join(x[-1-i] for x in dec_table)
        for name, lut in luts.items():
            print(f"  constant {name} : std_ulogic_vector(0 to {len(lut)-1}) := \"\"")
            cs = 64
            for off in range(0, len(lut), cs):
                part = lut[off : off + cs]
                end = ";" if off + cs >= len(lut) else ""
                print(f"    & \"{part}\"{end}")

    def minbool_dump(self):
        enc_table, enc_table_names = self.enc_table_gen()
        dec_table, dec_table_names = self.dec_table_gen()

        luts = {}
        for i, o in enumerate(enc_table_names):
            luts[o] = "".join(x[-1-i] for x in enc_table)

        for i, o in enumerate(dec_table_names):
            luts[o] = "".join(x[-1-i] for x in dec_table)

        for name, lut in luts.items():
            n = int(math.log2(len(lut)))
            print(f"   std::vector<uint16_t> {name}_on {'{'}{','.join(str(i) for i, v in enumerate(lut) if v == '1')}{'}'};")
            print(f"   std::vector<uint16_t> {name}_dc {'{'}{','.join(str(i) for i, v in enumerate(lut) if v == '-')}{'}'};")
            print(f"   std::vector<MinTerm<{n}> > {name}_solution = minimize_boolean<{n}>({name}_on, {name}_dc);");
            print(f"   dump(\"{name}\", {name}_solution);")

    def logicmin_dump(self):
        import logicmin

        for (table, names) in [self.enc_table_gen(), self.dec_table_gen()]:
            kw = int(math.log2(len(table)))
            ew = len(table[0])
            assert len(names) == ew

            for bit, name in enumerate(names):
                enc_tt = logicmin.TT(kw, 1)
                for key, v in enumerate(table):
                    enc_tt.add(bs(key, kw), v[-bit-1])
                enc_sols = enc_tt.solve()

                code = enc_sols.printN( xnames=[f'k({i})' for i in range(kw-1, -1, -1)], ynames=['r'], syntax='VHDL')
                code = code.replace("r <= ", "return ")
                code = code.replace(" or ", "\n        or ")
                
                print(f"  function {name}(k : in std_ulogic_vector({kw-1} downto 0)) return std_ulogic")
                print(f"  is")
                print(f"  begin")
                print("     ", code, ";")
                print(f"  end function;")

    def control_dump(self):
        for d_i in T8b10b.controls:
            for rd_i in [0, 1]:
                self.enc_dump(d_i, 1, rd_i)

        for rd_i, is_k, d_i, rd_o, code_o in self.codec[-24:]:
            self.dec_dump(code_o, rd_i)

        for i, c in enumerate([
                0b0010111100, 0b1101000011, 0b1001111100, 0b0110000011,
                0b1010111100, 0b0101000011, 0b1100111100, 0b0011000011,
                0b0100111100, 0b1011000011, 0b0101111100, 0b1010000011,
                0b0110111100, 0b1001000011, 0b0001111100, 0b1110000011,
                0b0001010111, 0b1110101000, 0b0001011011, 0b1110100100,
                0b0001011101, 0b1110100010, 0b0001011110, 0b1110100001,
        ]):
            self.dec_dump(c, rd = i & 1)

@click.group()
def group():
    pass

@group.command(help = "Dump LUTs")
def lut_dump():
    T8b10b().lut_dump()

@group.command(help = "Dump minbool code (https://github.com/madmann91/minbool)")
def minbool_dump():
    T8b10b().minbool_dump()

@group.command(help = "Dump logicmin")
def logicmin_dump():
    T8b10b().logicmin_dump()

@group.command(help = "Check LUTs")
def lut_check():
    t = T8b10b()
    t.codec_check()
    t.enc_table_check()
    t.dec_table_check()

@group.command(help = "Dump control codes")
def control_dump():
    T8b10b().control_dump()

@group.command(help = "Encode")
@click.option('-k', '--control', default = False)
@click.argument("data", type = str)
@click.option("--rd", type = str)
def encode(control, data, rd):
    data = data.lower()
    m = re.match(r"(?P<dk>[DK])(?P<x>\d+)\.(?P<y>\d+)", data, re.I)
    if m:
        control = m.group('dk').lower() == 'k'
        data = ((int(m.group("y")) & 0x7) << 5)
        data |= int(m.group("x")) & 0x1f
    else:
        control = int(control)
        if data.startswith("0b") and len(data) == 10:
            data = int(data, 2)
        elif data.startswith("0x") and len(data) == 4:
            data = int(data, 16)
        elif len(data) == 2:
            data = int(data, 16)
        elif len(data) == 8:
            data = int(data, 2)
        else:
            data = int(data)
    rd = int(rd == '1')
    T8b10b().enc_dump(data, control, rd)

@group.command(help = "Decode")
@click.argument("word", type = str)
@click.option("--rd", type = int, default = None)
def decode(word, rd):
    if word.startswith("0b") and len(word) == 12:
        word = int(word, 2)
    elif word.startswith("0x") and len(word) == 5:
        word = int(word, 16)
    elif len(word) == 3:
        word = int(word, 16)
    elif len(word) == 10:
        word = int(word, 2)
    else:
        word = int(word)

    if rd is not None:
        rd = int(bool(rd))
    T8b10b().dec_dump(word, rd)

if __name__ == "__main__":
    group()

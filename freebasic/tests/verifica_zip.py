"""verifica_zip.py - verifica o arhiva cu zipfile din biblioteca standard Python, independent de miniz.

  python -I verifica_zip.py ARHIVA [--zip64 | --clasic] [--intrari N] [--dimensiune NUME OCTETI]
                            [--peste-4g NUME] [--citeste NUME] [--testzip]

Optiunile se pot repeta (--dimensiune, --peste-4g, --citeste). Mereu: sfarsitul directorului central
(EOCD si, daca exista, locatorul si recordul zip64) e citit direct din fisier si comparat cu ce vede
zipfile, iar antetul local al fiecarei intrari e gasit la offsetul din directorul central, cu acelasi
nume. Iese cu 0 daca totul e bine, 1 altfel; scrie un rezumat (folosit de grupul 8 din test_margini).
"""

import os
import struct
import sys
import zipfile

EOCD = b"PK\x05\x06"
LOC64 = b"PK\x06\x07"
EOCD64 = b"PK\x06\x06"
LOCAL = b"PK\x03\x04"


def end_records(f, size):
    """EOCD clasic si, daca exista, recordul zip64: (eocd, eocd64 sau None)."""
    tail = min(size, 65535 + 22)
    f.seek(size - tail)
    buf = f.read(tail)
    at = buf.rfind(EOCD)
    if at < 0:
        raise ValueError("lipseste EOCD")
    eocd_ofs = size - tail + at
    (_, disk, cd_disk, n_disk, n, cd_size, cd_ofs, clen) = struct.unpack("<IHHHHIIH", buf[at:at + 22])
    eocd = dict(ofs=eocd_ofs, n=n, n_disk=n_disk, cd_size=cd_size, cd_ofs=cd_ofs)
    eocd64 = None
    if eocd_ofs >= 20:
        f.seek(eocd_ofs - 20)
        loc = f.read(20)
        if loc[:4] == LOC64:
            (_, _, rec_ofs, _) = struct.unpack("<IIQI", loc)
            f.seek(rec_ofs)
            rec = f.read(56)
            if rec[:4] != EOCD64:
                raise ValueError("locatorul zip64 arata la %d, unde nu e recordul zip64" % rec_ofs)
            (_, _, _, _, _, _, n64_disk, n64, cd64_size, cd64_ofs) = struct.unpack("<IQHHIIQQQQ", rec)
            eocd64 = dict(ofs=rec_ofs, n=n64, n_disk=n64_disk, cd_size=cd64_size, cd_ofs=cd64_ofs)
    return eocd, eocd64


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    path = argv[1]
    want64 = None
    count = None
    sizes, above, reads = [], [], []
    testzip = False
    i = 2
    while i < len(argv):
        a = argv[i]
        if a == "--zip64":
            want64 = True
        elif a == "--clasic":
            want64 = False
        elif a == "--intrari":
            count = int(argv[i + 1])
            i += 1
        elif a == "--dimensiune":
            sizes.append((argv[i + 1], int(argv[i + 2])))
            i += 2
        elif a == "--peste-4g":
            above.append(argv[i + 1])
            i += 1
        elif a == "--citeste":
            reads.append(argv[i + 1])
            i += 1
        elif a == "--testzip":
            testzip = True
        else:
            print("optiune necunoscuta: " + a)
            return 2
        i += 1

    errors = []
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        eocd, eocd64 = end_records(f, size)
        end = eocd64 if eocd64 else eocd
        if want64 is True and eocd64 is None:
            errors.append("fara record zip64, desi arhiva are %d octeti" % size)
        if want64 is False and eocd64 is not None:
            errors.append("are record zip64, desi trebuia sa fie clasica")
        if eocd64 is None and (end["cd_ofs"] + end["cd_size"] != eocd["ofs"]):
            errors.append("EOCD: directorul central (%d + %d) nu se termina la EOCD (%d)"
                          % (end["cd_ofs"], end["cd_size"], eocd["ofs"]))
        if eocd64 is not None and (end["cd_ofs"] + end["cd_size"] != eocd64["ofs"]):
            errors.append("zip64: directorul central (%d + %d) nu se termina la recordul zip64 (%d)"
                          % (end["cd_ofs"], end["cd_size"], eocd64["ofs"]))
        # in EOCD-ul clasic, un camp care nu incape trebuie sa fie santinela 0xFFFF / 0xFFFFFFFF
        if eocd64 is not None:
            if eocd64["n"] > 0xFFFF and eocd["n"] != 0xFFFF:
                errors.append("EOCD: %d intrari, fara santinela 0xFFFF" % eocd64["n"])
            if eocd64["cd_ofs"] > 0xFFFFFFFF and eocd["cd_ofs"] != 0xFFFFFFFF:
                errors.append("EOCD: offsetul directorului central %d, fara santinela" % eocd64["cd_ofs"])

        zf = zipfile.ZipFile(path)
        infos = zf.infolist()
        if end["n"] != len(infos):
            errors.append("EOCD spune %d intrari, zipfile vede %d" % (end["n"], len(infos)))
        if count is not None and len(infos) != count:
            errors.append("%d intrari, asteptate %d" % (len(infos), count))

        # antetul local al fiecarei intrari, la offsetul din directorul central
        bad_local = 0
        for info in infos:
            f.seek(info.header_offset)
            h = f.read(30)
            ok = len(h) == 30 and h[:4] == LOCAL
            if ok:
                nlen = struct.unpack("<H", h[26:28])[0]
                ok = f.read(nlen) == info.orig_filename.encode("utf-8")
            if not ok:
                bad_local += 1
                if bad_local <= 5:
                    errors.append("antet local gresit la %d pentru %r" % (info.header_offset, info.filename))
        if bad_local > 5:
            errors.append("%d antete locale gresite" % bad_local)

        byname = {info.filename: info for info in infos}
        for name, want in sizes:
            info = byname.get(name)
            if info is None:
                errors.append("lipseste " + name)
            elif info.file_size != want:
                errors.append("%s: %d octeti, asteptati %d" % (name, info.file_size, want))
        for name in above:
            info = byname.get(name)
            if info is None:
                errors.append("lipseste " + name)
            elif info.header_offset <= 0xFFFFFFFF:
                errors.append("%s: antetul local la %d, nu peste 4 GB" % (name, info.header_offset))
        for name in reads:
            try:
                n = 0
                with zf.open(name) as e:       # zipfile verifica CRC-ul la sfarsit
                    while True:
                        b = e.read(1 << 20)
                        if not b:
                            break
                        n += len(b)
                if n != byname[name].file_size:
                    errors.append("%s: citit %d octeti din %d" % (name, n, byname[name].file_size))
            except Exception as ex:
                errors.append("%s: %s" % (name, ex))
        if testzip:
            try:
                bad = zf.testzip()
                if bad is not None:
                    errors.append("testzip: prima intrare stricata " + bad)
            except Exception as ex:
                errors.append("testzip: %s" % ex)
        zf.close()

    print("%d octeti, %d intrari, %s, director central la %d, ultimul antet local la %d"
          % (size, len(infos), "zip64" if eocd64 else "clasic", end["cd_ofs"],
             max((i.header_offset for i in infos), default=0)))
    for e in errors:
        print("EROARE: " + e)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

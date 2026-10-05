from pathlib import Path

import pymupdf

Table = tuple[int, list[list[str]]]  # (page number, rows)


def extract_tables(pdf: Path) -> list[Table]:
    # ponytail: digital PDFs only; scanned pages need OCR (Apple Vision) later
    found: list[Table] = []
    with pymupdf.open(pdf) as doc:
        for page in doc:
            for t in page.find_tables().tables:
                rows = [[c or "" for c in r] for r in t.extract()]
                if rows:
                    found.append((page.number + 1, rows))
    return found

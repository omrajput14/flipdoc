from pathlib import Path

from openpyxl import Workbook

from flipdoc.extract import Table


def write_xlsx(tables: list[Table], out: Path) -> None:
    wb = Workbook()
    wb.remove(wb.active)
    for i, (page, rows) in enumerate(tables, 1):
        ws = wb.create_sheet(f"p{page}-t{i}")
        for r in rows:
            ws.append(r)
    wb.save(out)

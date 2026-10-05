from pathlib import Path

import typer

from flipdoc.extract import extract_tables
from flipdoc.xlsx import write_xlsx

app = typer.Typer(add_completion=False)


@app.callback()
def _root() -> None:
    """Flipdoc: transform documents from the command line."""


@app.command()
def tables(pdf: Path = typer.Argument(..., exists=True, dir_okay=False), out: Path = typer.Option(None, "--out", "-o")) -> None:
    """Extract every table in PDF into an .xlsx next to it (one sheet per table)."""
    found = extract_tables(pdf)
    if not found:
        typer.echo("No tables found.", err=True)
        raise typer.Exit(1)
    out = out or pdf.with_suffix(".xlsx")
    write_xlsx(found, out)
    typer.echo(f"{len(found)} table(s) -> {out}")

# Flipdoc

Right-click a PDF on your Mac and get its tables as an Excel file. Everything runs locally.

## Requirements

- macOS
- [uv](https://docs.astral.sh/uv/) (`curl -LsSf https://astral.sh/uv/install.sh | sh`)

## Install

```bash
git clone https://github.com/omrajput14/flipdoc.git
cd flipdoc
uv sync
```

## Usage

```bash
uv run flipdoc tables invoice.pdf            # writes invoice.xlsx next to the PDF
uv run flipdoc tables invoice.pdf -o out.xlsx
```

Each table becomes its own sheet, named by page and table number (`p2-t3`).

## Right-click in Finder

1. Open **Automator** → **New** → **Quick Action**.
2. Set *Workflow receives current* to **PDF files** in **Finder**.
3. Add **Run Shell Script**, set *Pass input* to **as arguments**, and enter the full path to the script:
   ```bash
   /path/to/flipdoc/quick-action/run.sh "$@"
   ```
4. Save as `Flipdoc: Tables → Excel`.

Right-click any PDF → **Quick Actions** → **Flipdoc: Tables → Excel**. A notification shows the result.

## Limitations

- Only PDFs with a text layer. Scanned PDFs return "No tables found" (OCR is planned).
- Tables are detected from ruling lines and layout; borderless or irregular tables may come out wrong.

## Development

```bash
uv run pytest
```

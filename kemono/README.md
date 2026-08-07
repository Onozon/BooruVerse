# kemono (Python)

Kemono.cr parser and PyQt6 desktop GUI.

## Setup

```bash
python3 -m venv ../.venv
source ../.venv/bin/activate
pip install -r requirements.txt
```

## Run

```bash
python kemono_gui_v6.py
```

Or use the interactive downloader:

```bash
python interactive_downloader.py
```

## Layout

- `kemono_parser.py` — scraping / API helpers
- `kemono_gui_v6.py` — current GUI
- `config.json` — defaults (base URL, delays, file types)
- `legacy/` — older GUI versions

Session cookies belong in `session_cookie.txt` (gitignored). Never commit credentials.

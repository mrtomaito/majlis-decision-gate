# -*- coding: utf-8 -*-
import os
import sys
import subprocess
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

BROWSER = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if not os.path.isfile(BROWSER):
    BROWSER = r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"

def render_html_to_pdf(html_path: str, pdf_path: str) -> bool:
    html_file = Path(html_path).resolve()
    pdf_file = Path(pdf_path).resolve()
    
    if not html_file.is_file():
        print(f"Error: HTML file not found: {html_file}")
        return False
        
    pdf_file.parent.mkdir(parents=True, exist_ok=True)
    
    args = [
        BROWSER,
        "--headless=new",
        "--disable-gpu",
        "--no-pdf-header-footer",
        "--run-all-compositor-stages-before-draw",
        "--virtual-time-budget=5000",
        f"--print-to-pdf={str(pdf_file)}",
        html_file.as_uri(),
    ]
    
    print(f"Rendering {html_file.name} -> {pdf_file.name}...")
    res = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
    
    if res.returncode == 0 and pdf_file.exists() and pdf_file.stat().st_size > 0:
        print(f"SUCCESS: Generated {pdf_file.name} ({pdf_file.stat().st_size:,} bytes)")
        return True
    else:
        print(f"FAILED: code {res.returncode}, stderr: {res.stderr}")
        return False

if __name__ == "__main__":
    if len(sys.argv) > 2:
        render_html_to_pdf(sys.argv[1], sys.argv[2])
    else:
        print("Usage: python render_pdf.py <input.html> <output.pdf>")

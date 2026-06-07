import subprocess
from pathlib import Path
from pdf2image import convert_from_path


class SlideImager:
    def __init__(self, output_dir: str = "./slide_images"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)

    def convert(self, pptx_path: str, doc_id: str) -> list[str]:
        doc_dir = self.output_dir / doc_id
        doc_dir.mkdir(exist_ok=True)

        subprocess.run([
            "libreoffice", "--headless", "--convert-to", "pdf",
            "--outdir", str(doc_dir), pptx_path
        ], check=True, capture_output=True)

        pdf_path = doc_dir / (Path(pptx_path).stem + ".pdf")

        images = convert_from_path(str(pdf_path), dpi=200)
        png_paths = []
        for i, img in enumerate(images, start=1):
            p = doc_dir / f"slide_{i:02d}.png"
            img.save(p, "PNG", optimize=True)
            png_paths.append(str(p))

        pdf_path.unlink()
        return png_paths
from markdown_pdf import MarkdownPdf
from markdown_pdf import Section

pdf = MarkdownPdf(toc_level=2)
pdf.add_section(Section(open('1uPay_Hackathon_Doc.md', encoding='utf-8').read(), toc=False))
pdf.save('1uPay_Hackathon_Doc.pdf')
print('PDF generated successfully!')

const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch(); const pg = await b.newPage();
  await pg.goto('file:///tmp/claude-0/enun/out.html'); await pg.waitForTimeout(500);
  await pg.pdf({ path: '/tmp/claude-0/enun/enunciado_explicado.pdf', format: 'A4', printBackground: true,
    displayHeaderFooter: true, headerTemplate: '<div></div>',
    footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#777;font-family:DejaVu Sans">WA2 · O enunciado explicado · <span class="pageNumber"></span>/<span class="totalPages"></span></div>',
    margin: { top: '16mm', bottom: '18mm', left: '16mm', right: '16mm' } });
  await b.close();
})();

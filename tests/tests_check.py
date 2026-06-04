from pathlib import Path
import re,subprocess
root=Path(__file__).resolve().parents[1]
required=['index.html','assets/css/styles.css','assets/js/app.js','assets/js/state.js','assets/js/login.js','assets/js/navigation.js','assets/js/members.js','assets/js/expenses.js','assets/js/revenues.js','assets/js/committees.js','assets/js/attendance.js','assets/js/reports.js','assets/js/settings.js','assets/js/backup.js','assets/js/permissions.js','assets/js/sync.js','assets/js/export.js','assets/js/audit.js','README.md','CHANGELOG.md','DEPLOYMENT.md','TEST_REPORT.md','manifest.webmanifest','sw.js','package.json','supabase.sql','icon-192.svg','icon-512.svg']
for f in required: assert (root/f).exists(),f'missing {f}'
html=(root/'index.html').read_text(encoding='utf-8')
assert 'onclick=' not in html
ids=re.findall(r'id="([^"]+)"',html); assert len(ids)==len(set(ids))
assert 'admin / 1234' not in html and 'finance / 2222' not in html
for js in (root/'assets/js').glob('*.js'): subprocess.run(['node','--check',str(js)],check=True)
print('ALL TESTS PASSED - REBUILD 1.0.0')

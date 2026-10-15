import os

files_to_fix = [
    'lib/pages/crn.dart',
    'lib/pages/invoice_page.dart',
    'lib/pages/quotation_page.dart'
]

for filepath in files_to_fix:
    with open(filepath, 'r') as f:
        content = f.read()

    # 1. Fix _buildActiveDraftData customer check
    content = content.replace(
        'if (_rows.isEmpty && _selectedCustomer == null) return null;',
        'if (_rows.isEmpty) return null;'
    )

    # 2. Update timer to 2000ms
    content = content.replace(
        '_draftPersistTimer = Timer(const Duration(milliseconds: 300), writeDraft);',
        '_draftPersistTimer = Timer(const Duration(milliseconds: 2000), writeDraft);'
    )

    # 3. Make all draft saves immediate
    content = content.replace('_persistActiveDraft()', '_persistActiveDraft(immediate: true)')

    # 4. Revert the one in the text controller listener to keep the debounce for typing
    revert_snippet = '''  void _scheduleDraftPersistFromController() {
    _persistActiveDraft(immediate: true);
  }'''
    fixed_snippet = '''  void _scheduleDraftPersistFromController() {
    _persistActiveDraft();
  }'''
    content = content.replace(revert_snippet, fixed_snippet)

    with open(filepath, 'w') as f:
        f.write(content)

print("Fixed draft logic in all files.")

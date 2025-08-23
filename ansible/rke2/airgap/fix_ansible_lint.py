#!/usr/bin/env python3

import re
import sys

def fix_fqcn(content):
    """Replace builtin modules with their FQCN equivalents"""
    replacements = {
        'file:': 'ansible.builtin.file:',
        'template:': 'ansible.builtin.template:',
        'stat:': 'ansible.builtin.stat:',
        'command:': 'ansible.builtin.command:',
        'fail:': 'ansible.builtin.fail:',
        'debug:': 'ansible.builtin.debug:',
        'unarchive:': 'ansible.builtin.unarchive:',
        'copy:': 'ansible.builtin.copy:',
        'shell:': 'ansible.builtin.shell:',
        'systemd:': 'ansible.builtin.systemd:',
        'wait_for:': 'ansible.builtin.wait_for:',
        'slurp:': 'ansible.builtin.slurp:',
        'set_fact:': 'ansible.builtin.set_fact:',
        'pause:': 'ansible.builtin.pause:',
        'fetch:': 'ansible.builtin.fetch:',
        'get_url:': 'ansible.builtin.get_url:',
        'include_role:': 'ansible.builtin.include_role:',
    }
    
    for old, new in replacements.items():
        content = content.replace(old, new)
    
    return content

def fix_truthy_values(content):
    """Fix truthy values"""
    # Replace 'yes' with true and 'no' with false
    content = re.sub(r':\s*yes$', ': true', content, flags=re.MULTILINE)
    content = re.sub(r':\s*no$', ': false', content, flags=re.MULTILINE)
    return content

def fix_trailing_spaces(content):
    """Remove trailing spaces"""
    lines = content.split('\n')
    fixed_lines = [line.rstrip() for line in lines]
    return '\n'.join(fixed_lines)

def main():
    if len(sys.argv) != 2:
        print("Usage: fix_ansible_lint.py <file>")
        sys.exit(1)
    
    filename = sys.argv[1]
    
    with open(filename, 'r') as f:
        content = f.read()
    
    # Apply fixes
    content = fix_fqcn(content)
    content = fix_truthy_values(content)
    content = fix_trailing_spaces(content)
    
    with open(filename, 'w') as f:
        f.write(content)
    
    print(f"Fixed {filename}")

if __name__ == '__main__':
    main()
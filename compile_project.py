#!/usr/bin/env python3
"""
Project Source Code Compiler
Reads all files in a directory and compiles them into a single output.
Supports .gitignore-style pattern matching via .compileignore file.
"""

import os
import sys
import re
import argparse
from pathlib import Path
from typing import List, Set, Optional


class GitignoreParser:
    """Parser for .gitignore-style patterns"""
    
    def __init__(self, patterns: List[str], base_path: Path):
        self.base_path = base_path.resolve()
        self.rules = []
        
        for pattern in patterns:
            pattern = pattern.strip()
            # Skip empty lines and comments
            if not pattern or pattern.startswith('#'):
                continue
            
            # Check if pattern is negation
            negate = pattern.startswith('!')
            if negate:
                pattern = pattern[1:]
            
            # Check if pattern should match only directories
            dir_only = pattern.endswith('/')
            if dir_only:
                pattern = pattern[:-1]
            
            self.rules.append({
                'pattern': pattern,
                'negate': negate,
                'dir_only': dir_only
            })
    
    def _match_pattern(self, pattern: str, path: str, is_dir: bool) -> bool:
        """Check if a path matches a gitignore pattern"""
        # If pattern starts with /, it's relative to base directory
        if pattern.startswith('/'):
            pattern = pattern[1:]
            # Match from root
            regex_pattern = self._pattern_to_regex(pattern)
            return bool(re.match(regex_pattern + r'(/|$)', path))
        
        # If pattern contains /, match full path
        if '/' in pattern:
            regex_pattern = self._pattern_to_regex(pattern)
            return bool(re.search(r'(^|/)' + regex_pattern + r'(/|$)', path))
        
        # Otherwise, match basename anywhere in tree
        regex_pattern = self._pattern_to_regex(pattern)
        parts = path.split('/')
        for part in parts:
            if re.match(regex_pattern + '$', part):
                return True
        
        return False
    
    def _pattern_to_regex(self, pattern: str) -> str:
        """Convert gitignore pattern to regex"""
        # Escape special regex characters except * and ?
        pattern = re.escape(pattern)
        
        # Replace escaped wildcards with regex equivalents
        pattern = pattern.replace(r'\*\*', '<!DOUBLESTAR!>')
        pattern = pattern.replace(r'\*', '[^/]*')
        pattern = pattern.replace('<!DOUBLESTAR!>', '.*')
        pattern = pattern.replace(r'\?', '[^/]')
        
        return pattern
    
    def is_ignored(self, path: Path) -> bool:
        """Check if a path should be ignored"""
        try:
            rel_path = path.resolve().relative_to(self.base_path)
        except ValueError:
            # Path is outside base_path
            return True
        
        rel_path_str = str(rel_path).replace(os.sep, '/')
        is_dir = path.is_dir()
        
        ignored = False
        
        for rule in self.rules:
            # Skip directory-only rules for files
            if rule['dir_only'] and not is_dir:
                continue
            
            if self._match_pattern(rule['pattern'], rel_path_str, is_dir):
                ignored = not rule['negate']
        
        return ignored


def load_ignore_patterns(directory: Path, ignore_file: Optional[str] = None) -> List[str]:
    """Load ignore patterns from file"""
    patterns = []
    
    # Default patterns to always ignore
    default_patterns = [
        '.git/',
        '__pycache__/',
        '*.pyc',
        '.DS_Store',
        'node_modules/',
        '.env',
    ]
    patterns.extend(default_patterns)
    
    # Determine which ignore file to use
    if ignore_file:
        # User specified a custom ignore file
        ignore_path = Path(ignore_file)
    else:
        # Use default .compileignore in the directory
        ignore_path = directory / '.compileignore'
    
    # Load patterns from the ignore file if it exists
    if ignore_path.exists():
        with open(ignore_path, 'r', encoding='utf-8', errors='ignore') as f:
            patterns.extend(f.readlines())
    
    return patterns


def is_binary_file(file_path: Path, sample_size: int = 8192) -> bool:
    """Check if a file is binary by reading a sample"""
    try:
        with open(file_path, 'rb') as f:
            chunk = f.read(sample_size)
            if b'\x00' in chunk:  # Null bytes indicate binary
                return True
            # Check for high ratio of non-text bytes
            text_chars = bytearray({7, 8, 9, 10, 12, 13, 27} | set(range(0x20, 0x100)))
            non_text = sum(1 for byte in chunk if byte not in text_chars)
            return non_text / len(chunk) > 0.3 if chunk else False
    except Exception:
        return True


def compile_project(
    directory: Path,
    output: Optional[Path] = None,
    ignore_file: Optional[str] = None,
    include_binary: bool = False,
    verbose: bool = False
) -> str:
    """Compile all source files in directory into a single string"""
    
    directory = directory.resolve()
    
    if not directory.exists():
        raise ValueError(f"Directory does not exist: {directory}")
    
    if not directory.is_dir():
        raise ValueError(f"Path is not a directory: {directory}")
    
    # Load ignore patterns
    patterns = load_ignore_patterns(directory, ignore_file)
    parser = GitignoreParser(patterns, directory)
    
    compiled_output = []
    file_count = 0
    skipped_count = 0
    
    # Walk through directory
    for root, dirs, files in os.walk(directory):
        root_path = Path(root)
        
        # Filter ignored directories (modify in place to prevent os.walk from entering them)
        # We need to check the directory path itself, not just the name
        filtered_dirs = []
        for d in dirs:
            dir_path = root_path / d
            if not parser.is_ignored(dir_path):
                filtered_dirs.append(d)
            elif verbose:
                try:
                    rel_dir = dir_path.relative_to(directory)
                    print(f"Skipped (ignored directory): {rel_dir}/", file=sys.stderr)
                except ValueError:
                    pass
        dirs[:] = filtered_dirs
        
        for file in sorted(files):
            file_path = root_path / file
            
            # Skip ignored files
            if parser.is_ignored(file_path):
                if verbose:
                    print(f"Skipped (ignored): {file_path.relative_to(directory)}", file=sys.stderr)
                skipped_count += 1
                continue
            
            # Skip binary files unless explicitly included
            if not include_binary and is_binary_file(file_path):
                if verbose:
                    print(f"Skipped (binary): {file_path.relative_to(directory)}", file=sys.stderr)
                skipped_count += 1
                continue
            
            # Read file content
            try:
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                
                rel_path = file_path.relative_to(directory)
                
                # Add file header
                compiled_output.append(f"\n{'='*80}")
                compiled_output.append(f"File: {rel_path}")
                compiled_output.append(f"{'='*80}\n")
                compiled_output.append(content)
                compiled_output.append("\n")
                
                file_count += 1
                if verbose:
                    print(f"Added: {rel_path}", file=sys.stderr)
                    
            except Exception as e:
                if verbose:
                    print(f"Error reading {file_path.relative_to(directory)}: {e}", file=sys.stderr)
                skipped_count += 1
    
    result = '\n'.join(compiled_output)
    
    if verbose:
        print(f"\nSummary:", file=sys.stderr)
        print(f"  Files compiled: {file_count}", file=sys.stderr)
        print(f"  Files skipped: {skipped_count}", file=sys.stderr)
        print(f"  Total size: {len(result)} characters", file=sys.stderr)
    
    # Write to output file or stdout
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        with open(output, 'w', encoding='utf-8') as f:
            f.write(result)
        if verbose:
            print(f"\nOutput written to: {output}", file=sys.stderr)
    
    return result


def main():
    parser = argparse.ArgumentParser(
        description='Compile all source files in a directory into a single output.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Compile current directory to stdout
  %(prog)s .
  
  # Compile directory to file
  %(prog)s /path/to/project -o output.txt
  
  # Use custom ignore file
  %(prog)s . -i custom.ignore -o compiled.txt
  
  # Include binary files and show verbose output
  %(prog)s . --include-binary -v
        """
    )
    
    parser.add_argument(
        'directory',
        type=Path,
        help='Directory to compile'
    )
    
    parser.add_argument(
        '-o', '--output',
        type=Path,
        help='Output file (if not specified, writes to stdout)'
    )
    
    parser.add_argument(
        '-i', '--ignore-file',
        type=str,
        help='Custom ignore file (default: .compileignore in target directory)'
    )
    
    parser.add_argument(
        '--include-binary',
        action='store_true',
        help='Include binary files in output'
    )
    
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Verbose output (to stderr)'
    )
    
    args = parser.parse_args()
    
    try:
        result = compile_project(
            directory=args.directory,
            output=args.output,
            ignore_file=args.ignore_file,
            include_binary=args.include_binary,
            verbose=args.verbose
        )
        
        # If no output file specified, write to stdout
        if not args.output:
            print(result)
            
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
